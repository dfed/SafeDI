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

/// Public mocks (`@Instantiable(generateMock: .public)`): how the macro's argument reaches the tool, and the mock the
/// declaring module generates.
struct SafeDIToolPublicMockTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – the argument

	@Test(arguments: [
		("true", MockGeneration.internal),
		(".internal", .internal),
		("MockGeneration.internal", .internal),
		(".public", .public),
		("MockGeneration.public", .public),
		("false", .none),
		(".none", .none),
		("MockGeneration.none", .none),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_plansMockFile_whenGenerateMockSpellsCaseThatGeneratesOne(spelling: String, mockGeneration: MockGeneration) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: \(spelling))
				public struct Service: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generateOutput.module.instantiables.map(\.generateMock) == [mockGeneration])
		#expect(output.mockFiles.keys.sorted() == (mockGeneration.generatesMock ? ["Service+SafeDIMock.swift"] : []))
	}

	// MARK: Tests – what keeps a public mock from being generated

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicMockedTypeIsNestedInNarrowerType() async {
		// M1.8: the type spells `public`, which the macro accepts, but `Internals` keeps it `internal`.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["X.swift"]):2:33: error: `Internals.X` cannot have a public mock because `Internals` is `internal`. Make `Internals` `public`, or use `generateMock: .internal`.
			\(fixtures["X.swift"]):2:33-2:40: fixit: .internal
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					enum Internals {
					    @Instantiable(generateMock: .public) public struct X: Instantiable {
					        public init() {}
					    }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [MultiModuleIntegration.moduleInfo, .swiftPackagePlugin])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicMockedTypeIsDeclaredInExtensionOfNarrowerInstantiableType(integration: MultiModuleIntegration) async {
		// cross-row-2: `Inner` is declared in an extension of `Outer`, whose own `@Instantiable` declaration is `package`,
		// so code that names `Outer.Inner` reaches it at most from within the package, as when it is nested directly.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let path = switch integration {
			case .moduleInfo:
				fixtures["Feature"]!["Outer.swift"]
			case .swiftPackagePlugin:
				NormalizedFilePath(fixtures["Feature"]!.compilerPath(of: "Outer.swift")).path
			}
			return """
			\(path):7:33: error: `Outer.Inner` cannot have a public mock because `Outer` is `package`. Make `Outer` `public`, or use `generateMock: .internal`.
			\(path):7:33-7:40: fixit: .internal
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "pkg", swiftFileContentByFilePath: ["Outer.swift": """
					@Instantiable
					package final class Outer: Instantiable {
					    package init() {}
					}

					extension Outer {
					    @Instantiable(generateMock: .public)
					    public final class Inner: Instantiable {
					        public init() {}
					    }
					}
					"""]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingInnermostNarrowerType_whenPublicMockedTypeIsNestedInNarrowerTypeInsidePublicTypesExtension() async {
		// gap-534-529-3: `Space` is `public` and `Inner`, declared in its extension, is `package`, so `Inner` is what
		// keeps `Shelf` from being `public`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Shelf.swift"]):5:37: error: `Space.Inner.Shelf` cannot have a public mock because `Space.Inner` is `package`. Make `Space.Inner` `public`, or use `generateMock: .internal`.
			\(fixtures["Feature"]!["Shelf.swift"]):5:37-5:44: fixit: .internal
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "pkg", swiftFileContentByFilePath: ["Shelf.swift": """
					public enum Space {}

					extension Space {
					    package enum Inner {
					        @Instantiable(generateMock: .public)
					        public final class Shelf: Instantiable {
					            public init() {}
					        }
					    }
					}
					"""]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsPlainErrorAtDeclaration_whenTypeThatMacroRejectsForBeingNarrowerDeclaresPublicMock() async {
		// F10: the macro rejects `generateMock: .public` on an `internal` type, but `generate` runs before the macro
		// expands, so the tool says so at the declaration rather than reporting the tier its `internal` type caps.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["FeedScreen.swift"]):6:1: error: `FeedScreen` is `internal` and declares `generateMock: .public`. The @Instantiable macro rejects that: `generateMock: .public` requires a `public` or `open` type. Declare `FeedScreen` `public`, or use `generateMock: .internal`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "pkg", swiftFileContentByFilePath: ["FeedScreen.swift": """
					@Instantiable
					package final class FeedService: Instantiable {
					    package init() {}
					}

					@Instantiable(generateMock: .public)
					final class FeedScreen: Instantiable {
					    public init(service: FeedService) {
					        self.service = service
					    }

					    @Forwarded let service: FeedService
					}
					"""]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsPlainErrorAtDeclaration_whenPackageSeamWithHoleDeclaresPublicMock() async {
		// BZ-5: an adopter narrows a seam to `package` first, as the guide does, and meets this before `internal`: the plain
		// error, not the tier error the seam's hole and `internal` tree would otherwise draw.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["ProfileScreen.swift"]):3:1: error: `ProfileScreen` is `package` and declares `generateMock: .public`. The @Instantiable macro rejects that: `generateMock: .public` requires a `public` or `open` type. Declare `ProfileScreen` `public`, or use `generateMock: .internal`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "pkg", swiftFileContentByFilePath: ["ProfileScreen.swift": """
					package protocol AvatarProviding {}

					@Instantiable(generateDependencyTree: true, generateMock: .public)
					package struct ProfileScreen: Instantiable {
					    package init(avatarProvider: any AvatarProviding, formatter: BioFormatter) {
					        self.avatarProvider = avatarProvider
					        self.formatter = formatter
					    }

					    @Instantiated let avatarProvider: any AvatarProviding
					    @Instantiated let formatter: BioFormatter
					}

					@Instantiable
					struct BioFormatter: Instantiable {
					    init() {}
					}
					"""]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases, [(declaration: "package enum Space {}", level: "package"), (declaration: "enum Space {}", level: "internal")])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtGenerateMockArgument_whenPublicMockedTypeIsDeclaredInExtensionOfNarrowerNamespaceInFileOfItsOwn(integration: MultiModuleIntegration, namespace: (declaration: String, level: String)) async {
		// gap-534-529-2: `Space`, declared in a file without a SafeDI marker, keeps `Space.Shelf` from being `public`, as an
		// enclosing type keeps a type declared directly inside it; the check reads `Space`'s plain declaration.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let shelfPath = Self.path(of: "Shelf.swift", in: "Feature", fixtures, integration)
			return """
			\(shelfPath):6:33: error: `Space.Shelf` cannot have a public mock because `Space` is `\(namespace.level)`. Make `Space` `public`, or use `generateMock: .internal`.
			\(shelfPath):6:33-6:40: fixit: .internal
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [Self.featureExtendingNamespace(declaredAs: namespace.declaration)], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesPublicMock_whenPublicMockedTypeIsDeclaredInExtensionOfPublicNamespaceInFileOfItsOwn(integration: MultiModuleIntegration) async throws {
		// gap-534-529-2's twin: a `public` `Space` bounds nothing narrower.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [Self.featureExtendingNamespace(declaredAs: "public enum Space {}")], integration: integration, filesToDelete: &filesToDelete)
		let mockCode = """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Space.Shelf {
		    public static func mock() -> Space.Shelf {
		        Space.Shelf()
		    }
		}

		extension Space.Shelf {
		    public enum __safeDI_Space_Shelf_mock_CBF29CE484222325 {}
		}
		#endif
		"""
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + mockCode])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles["Shelf+SafeDIMock.swift"] == generatedFileHeader + mockCode)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicMockForwardsPackageType() async {
		// M2.7: a forwarded parameter is required, so a narrower one makes the public tier impossible. Cause (i).
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Feature.swift"]):1:29: error: SafeDI cannot generate the public mock of `Feature`: its `public` tier, which `generateMock: .public` requires, cannot take `user: User`, which `Feature` forwards, and cannot pass `nil` for it, since it is required. `User`'s own `@Instantiable` declaration is `package`. Declare `User` `public`; give `User` a `mockOnly` mock; or use `generateMock: .internal`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: .public)
					public struct Feature: Instantiable {
					    package init(user: User) {
					        self.user = user
					    }

					    @Forwarded let user: User
					}
					""",
					"""
					@Instantiable
					package struct User: Instantiable {
					    package init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicMockedTreeReceivesPlainTypeOnlyNarrowerInitializersMention() async {
		// M2.9b, M2.10: a received parameter nothing builds is required. Cause (ii), with a note at the receive.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:29: error: SafeDI cannot generate the public mock of `Service`: its `public` tier, which `generateMock: .public` requires, cannot take `token: [3 of Int]`, which the initializer of `TokenCache` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in this module or on a type that receives it is `internal` (`TokenCache.init(token:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; receive it with `onlyIfAvailable: true` and an optional type; make `TokenCache.init(token:)` `public`; or use `generateMock: .internal`.
			\(fixtures["TokenCache.swift"]):7:5: note: `TokenCache` receives `token: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    init(tokenCache: TokenCache) {
					        self.tokenCache = tokenCache
					    }

					    @Instantiated let tokenCache: TokenCache
					}
					""",
					"""
					@Instantiable
					public struct TokenCache: Instantiable {
					    init(token: [3 of Int]) {
					        self.token = token
					    }

					    @Received let token: [3 of Int]
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – the parameters of a public mock

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesPublicMockWithNoParameters_whenTypeHasNoDependencies() async throws {
		// M2.16, M3.16: no tree and no default, so no `SafeDIOverrides`; the guard enum still names the signature.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    public static func mock() -> Service {
			        Service()
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_CBF29CE484222325 {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOptionalDefaultAsParameterWithProvider_whenPublicMockHasNoTree() async throws {
		// M2.16b: no tree, so no `SafeDIOverrides`: the optional-typed default is a parameter that defaults to its
		// provider; the non-optional one is `T? = nil`, resolved in the body; a magic literal is kept (M6.11).
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public enum Defaults {
				    public static let name: String? = "service"
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    public init(name: String? = Defaults.name, retries: Int = 3, onTap: @escaping () -> Void = {}, file: String = #fileID) {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    // These providers evaluate `Service`'s own defaults outside any actor, since SafeDI sees no isolation on it. If one
			    // reads the state of an actor `Service` takes from a conformance or a superclass and does not compile, give its
			    // `@Instantiable` `mockAttributes: "@MainActor"` (or that actor).
			    @usableFromInline nonisolated static func __safeDI_publicMockDefault_name() -> String? { Defaults.name }

			    public static func mock(
			        name: String? = Service.__safeDI_publicMockDefault_name(),
			        retries: Int? = nil,
			        onTap: (() -> Void)? = nil,
			        file: String = #fileID
			    ) -> Service {
			        let retries = retries ?? (3)
			        let onTap = onTap ?? ({})
			        return Service(name: name, retries: retries, onTap: onTap, file: file)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_39A4AE30EA852266 {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresPublicTierWithEmptyParameterList_whenEveryParameterIsNarrowerThanPublic() async throws {
		// The `public` tier takes nothing, since `token` is of the internal `Token`: it is declared `mock()`, and passes
		// `nil` for `token` to the internal tier.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    init(token: Token?) {
				        self.token = token
				    }

				    @Received(onlyIfAvailable: true) let token: Token?
				}
				""",
				"struct Token {}",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    public static func mock() -> Service {
			        Service.mock(token: nil)
			    }

			    static func mock(
			        token: Token? = nil
			    ) -> Service {
			        return Service(token: token)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_47EDF6CE3DA4FFE0 {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_putsMockAttributesOnPublicTierWithEmptyParameterList_whenEveryParameterIsNarrowerThanPublic() async throws {
		// The mock's attributes lead the `public` tier's declaration when it takes nothing, as they lead every tier's.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(mockAttributes: "@MainActor", generateMock: .public)
				public struct Service: Instantiable {
				    init(token: Token?) {
				        self.token = token
				    }

				    @Received(onlyIfAvailable: true) let token: Token?
				}
				""",
				"struct Token {}",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @MainActor public static func mock() -> Service {
			        Service.mock(token: nil)
			    }

			    @MainActor static func mock(
			        token: Token? = nil
			    ) -> Service {
			        return Service(token: token)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_47EDF6CE3DA4FFE0 {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesOwnDefaultsProviderFromPublicTierWithEmptyParameterList_whenOwnDefaultIsOfNarrowerType() async throws {
		// With no tree, `label`, of the internal `Label`, is a parameter of the internal tier that defaults to its
		// provider; the `public` tier takes nothing and passes the provider's value, the declaration's default.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				struct Label {
				    init() {}
				}

				@Instantiable(generateMock: .public)
				public struct Dashboard: Instantiable {
				    static let defaultLabel: Label? = Label()

				    init(label: Label? = defaultLabel) {
				        self.label = label
				    }

				    let label: Label?
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
			"Dashboard+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Dashboard {
			    // These providers evaluate `Dashboard`'s own defaults outside any actor, since SafeDI sees no isolation on it. If one
			    // reads the state of an actor `Dashboard` takes from a conformance or a superclass and does not compile, give its
			    // `@Instantiable` `mockAttributes: "@MainActor"` (or that actor).
			    nonisolated static func __safeDI_publicMockDefault_label() -> Label? { defaultLabel }

			    public static func mock() -> Dashboard {
			        Dashboard.mock(label: Dashboard.__safeDI_publicMockDefault_label())
			    }

			    static func mock(
			        label: Label? = Dashboard.__safeDI_publicMockDefault_label()
			    ) -> Dashboard {
			        return Dashboard(label: label)
			    }
			}

			extension Dashboard {
			    public enum __safeDI_Dashboard_mock_91ACC954C2301BF6 {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsNextNarrowerTierFromPublicTierWithEmptyParameterList_whenParametersAreOfTwoNarrowerLevels() async throws {
		// `theme` is of the `package` `Theme` and `token` of the internal `Token`: the `public` tier takes nothing and
		// calls the `package` tier, which takes `theme` and calls the internal tier.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
				import SafeDI

				package struct Theme {}

				struct Token {}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    init(theme: Theme?, token: Token?) {
				        self.theme = theme
				        self.token = token
				    }

				    @Received(onlyIfAvailable: true) let theme: Theme?
				    @Received(onlyIfAvailable: true) let token: Token?
				}
				"""]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Service {
		    public static func mock() -> Service {
		        Service.mock(theme: nil)
		    }

		    package static func mock(
		        theme: Theme? = nil
		    ) -> Service {
		        Service.mock(theme: theme, token: nil)
		    }

		    static func mock(
		        theme: Theme? = nil,
		        token: Token? = nil
		    ) -> Service {
		        return Service(theme: theme, token: token)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_mock_6FDAA95DDC48E6C6 {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicTierWithEmptyArgumentList_whenAnotherPackagesPublicMockTreeBuildsTypeWhosePublicTierTakesNothing() async throws {
		// `Mid` is in another package, so `Outer`'s tree calls `Screen`'s `public` tier, which takes nothing: the call
		// passes nothing.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Screen.swift": """
				import SafeDI

				package struct Theme {}

				@Instantiable(generateMock: .public)
				public struct Screen: Instantiable {
				    package init(theme: Theme?) {
				        self.theme = theme
				    }

				    @Received(onlyIfAvailable: true) let theme: Theme?
				}
				"""]),
				ModuleFixture(name: "Mid", packageName: "mid", swiftFileContentByFilePath: ["Outer.swift": """
				import Core
				import SafeDI

				@Instantiable(generateMock: .public)
				public struct Outer: Instantiable {
				    package init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated let screen: Screen
				}
				"""], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

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
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Outer {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            screen: (() -> Screen)? = nil
		        ) {
		            self.screen = screen
		        }

		        public private(set) var screen: (() -> Screen)?
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        _ = Screen.__safeDI_Screen_mock_68FAB8E0F700DD87.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let screen = if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder() } else { Screen.mock() }
		        return Outer(screen: screen)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_mock_51799E6AA5E7B634 {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesReceivedDependenciesAsOptionalParameters_whenPublicMockBuildsOrIsHandedThem() async throws {
		// M5.1a, M5.3, M5.4, M2.11, M2.19, M2.20: each received dependency the mock builds is `T? = nil`, an instance
		// winning over the override; one received only if available that nothing provides is a parameter rather than an
		// override; two forms of one label are two parameters named apart; label order. `Token` is internal, so its
		// parameter is on the internal tier only.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    public init(child: Child) {
				        self.child = child
				    }

				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public struct Child: Instantiable {
				    init(zebra: Zebra, apple: Apple, appleBuilder: Instantiator<Apple>, token: Token?) {
				        self.zebra = zebra
				        self.apple = apple
				        self.appleBuilder = appleBuilder
				        self.token = token
				    }

				    @Received let zebra: Zebra
				    @Received let apple: Apple
				    @Received let appleBuilder: Instantiator<Apple>
				    @Received(onlyIfAvailable: true) let token: Token?
				}
				""",
				"@Instantiable\npublic struct Zebra: Instantiable {\n    public init() {}\n}",
				"@Instantiable\npublic struct Apple: Instantiable {\n    public init() {}\n}",
				"struct Token {}",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            zebra: (() -> Zebra)? = nil,
			            apple: (() -> Apple)? = nil,
			            appleBuilder: (() -> Apple)? = nil
			        ) {
			            self.zebra = zebra
			            self.apple = apple
			            self.appleBuilder = appleBuilder
			            self.child = nil
			        }

			        init(
			            zebra: (() -> Zebra)? = nil,
			            apple: (() -> Apple)? = nil,
			            appleBuilder: (() -> Apple)? = nil,
			            child: ((Zebra, Apple, Instantiator<Apple>, Token?) -> Child)? = nil
			        ) {
			            self.zebra = zebra
			            self.apple = apple
			            self.appleBuilder = appleBuilder
			            self.child = child
			        }

			        public private(set) var zebra: (() -> Zebra)?
			        public private(set) var apple: (() -> Apple)?
			        public private(set) var appleBuilder: (() -> Apple)?
			        private(set) var child: ((Zebra, Apple, Instantiator<Apple>, Token?) -> Child)?
			    }

			    public static func mock(
			        apple: Apple? = nil,
			        appleBuilder: Instantiator<Apple>? = nil,
			        zebra: Zebra? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        Service.mock(apple: apple, appleBuilder: appleBuilder, token: nil, zebra: zebra, safeDIOverrides: safeDIOverrides)
			    }

			    static func mock(
			        apple: Apple? = nil,
			        appleBuilder: Instantiator<Apple>? = nil,
			        token: Token? = nil,
			        zebra: Zebra? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let zebra = if let zebra { zebra } else if let safeDIBuilder = safeDIOverrides.zebra { safeDIBuilder() } else { Zebra() }
			        let apple = if let apple { apple } else if let safeDIBuilder = safeDIOverrides.apple { safeDIBuilder() } else { Apple() }
			        func __safeDI_appleBuilder() -> Apple {
			            if let safeDIBuilder = safeDIOverrides.appleBuilder { safeDIBuilder() } else { Apple() }
			        }
			        let appleBuilder = if let appleBuilder { appleBuilder } else { Instantiator<Apple>(__safeDI_appleBuilder) }
			        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(zebra, apple, appleBuilder, token) } else { Child(zebra: zebra, apple: apple, appleBuilder: appleBuilder, token: token) }
			        return Service(child: child)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_C2149D3536A3C96F {}
			}
			#endif
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsOnlyIfAvailableRenameFromPublicMocksParameter_whenNothingInPublicMocksTreeDeclaresItsDependency(integration: MultiModuleIntegration) async throws {
		// The public-mock twin of `mock_bindsAliasFromOverrideOfItsDependency_asProductionBindsItToNil_whenSiblingOfDeclaringTypeDeclaresItsLabel`:
		// nothing in `Holder`'s tree declares `x`, so `Child`'s `onlyIfAvailable` rename of it is bound from the public mock's
		// `x: X? = nil` parameter, and `Grand` reads the rename. `Screen`'s mock, in another module, which cannot build
		// `Holder`'s internal tree, builds `x` and passes it to `Holder.mock`, so `Child` and `Grand` hold `Screen`'s `x`, as
		// they do when the tree is built inline.
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Holder.swift": """
			import SafeDI

			@Instantiable
			public final class X: Instantiable {
			    public init() {}
			}

			@Instantiable(generateMock: .public)
			public final class Holder: Instantiable {
			    init(child: Child) {
			        self.child = child
			    }

			    @Instantiated let child: Child
			}

			@Instantiable
			final class Child: Instantiable {
			    init(ax: X?, grand: Grand) {
			        self.ax = ax
			        self.grand = grand
			    }

			    @Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let ax: X?
			    @Instantiated let grand: Grand
			}

			@Instantiable
			final class Grand: Instantiable {
			    init(ax: X?) {
			        self.ax = ax
			    }

			    @Received let ax: X?
			}
			"""]),
			ModuleFixture(name: "App", packageName: "apppkg", swiftFileContentByFilePath: ["Screen.swift": """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(x: X, holder: Holder) {
			        self.x = x
			        self.holder = holder
			    }

			    @Instantiated let x: X
			    @Instantiated let holder: Holder
			}
			"""], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: integration, filesToDelete: &filesToDelete)
		let holderPath = try #require(output.modules["Core"]).fixtures.compilerPath(of: "Holder.swift")
		let coreImports = """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""
		let holderMock = """
		#if DEBUG
		extension Holder {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            child: __safeDI_Core_Child_MockConfiguration = .init()
		        ) {
		            self.child = child
		        }

		        public private(set) var child: __safeDI_Core_Child_MockConfiguration
		    }

		    public static func mock(
		        x: X? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Holder {
		        func __safeDI_child() -> Child {
		            #sourceLocation(file: "\(holderPath)", line: 24)
		            let ax: X? = x
		            #sourceLocation()
		            let grand = if let safeDIBuilder = safeDIOverrides.child.grand { safeDIBuilder(ax) } else { Grand(ax: ax) }
		            return Child.__safeDI_init(ax: ax, grand: grand, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)
		        }
		        let child: Child = __safeDI_child()
		        return Holder(child: child)
		    }
		}

		extension Holder {
		    public enum __safeDI_Holder_mock_23D9BF4A31F0CAE5 {}
		}
		#endif
		"""
		let childConfiguration = """
		#if DEBUG
		/// Configuration for how `Child` is constructed within the public mock trees of module `Core`.
		public struct __safeDI_Core_Child_MockConfiguration {
		    public init() {
		        self.grand = nil
		        self.safeDIBuilder = nil
		    }

		    init(
		        grand: ((X?) -> Grand)? = nil,
		        _ safeDIBuilder: ((X?, Grand) -> Child)? = nil
		    ) {
		        self.grand = grand
		        self.safeDIBuilder = safeDIBuilder
		    }

		    private(set) var grand: ((X?) -> Grand)?
		    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
		    private(set) var safeDIBuilder: ((X?, Grand) -> Child)?
		}

		extension Child {
		    static func __safeDI_init(ax: X?, grand: Grand, safeDIBuilder: ((X?, Grand) -> Child)?) -> Child {
		        if let safeDIBuilder { safeDIBuilder(ax, grand) } else { Child(ax: ax, grand: grand) }
		    }
		}
		#endif

		"""
		let appImports = """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""
		let pluginComment = integration.seamCallComment(type: "Holder", declaringModule: "Core")
		let screenMock = """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            x: (() -> X)? = nil,
		            holder: Holder.SafeDIOverrides = .init()
		        ) {
		            self.x = x
		            self.holder = holder
		        }

		        private(set) var x: (() -> X)?
		        private(set) var holder: Holder.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let x = if let safeDIBuilder = safeDIOverrides.x { safeDIBuilder() } else { X() }
		        _ = Holder.__safeDI_Holder_mock_23D9BF4A31F0CAE5.self\(pluginComment)
		        let holder = Holder.mock(x: x, safeDIOverrides: safeDIOverrides.holder)
		        return Screen(x: x, holder: holder)
		    }
		}
		#endif
		"""
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + coreImports + holderMock + "\n\n" + childConfiguration])
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + appImports + screenMock])
		case .swiftPackagePlugin:
			#expect(output.modules["Core"]?.generatedFiles == [
				"Holder+SafeDIMock.swift": generatedFileHeader + coreImports + holderMock,
				"SafeDIMockConfiguration.swift": generatedFileHeader + coreImports + childConfiguration,
			])
			#expect(output.modules["App"]?.generatedFiles == [
				"Screen+SafeDIMock.swift": generatedFileHeader + appImports + screenMock,
				"SafeDIMockConfiguration.swift": generatedFileHeader + appImports,
			])
		}
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Screen.mock()"),
			DifferentialValueProbe("Holder.mock()"),
			DifferentialValueProbe(name: "Holder.mock() passed an x", expression: "Holder.mock(x: X())", knownRightExpression: "Holder.mock(safeDIOverrides: .init(x: X()))"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsCustomMockThroughPublicMock_whenTypeNamesCustomMock() async throws {
		// M10.3, M1.12, M6.6: the public mock calls the hand-written `preview`, whose level adds no tier.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public, customMockName: "preview")
				public struct Service: Instantiable {
				    public init(analytics: Analytics) {
				        self.analytics = analytics
				    }

				    static func preview(analytics: Analytics, retries: Int = 3) -> Service {
				        Service(analytics: analytics)
				    }

				    @Received let analytics: Analytics
				}
				""",
				"@Instantiable\npublic struct Analytics: Instantiable {\n    public init() {}\n}",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            analytics: (() -> Analytics)? = nil
			        ) {
			            self.analytics = analytics
			        }

			        public private(set) var analytics: (() -> Analytics)?
			    }

			    public static func mock(
			        retries: Int? = nil,
			        analytics: Analytics? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let retries = retries ?? (3)
			        let analytics = if let analytics { analytics } else if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
			        return Service.preview(analytics: analytics, retries: retries)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_9BEAAC23B11B566D {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesInternalInitializerOnly_whenEveryOverrideIsInternal() async throws {
		// M3.7, M4.4, M4.13: every member of `SafeDIOverrides` is internal, so its public initializer takes nothing; the
		// internal child's configuration is public, its default public, and its builder internal.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    init(child: Child) {
				        self.child = child
				    }

				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				struct Child: Instantiable {
				    init(grand: Grand, capacity: Int = 10) {
				        self.grand = grand
				    }

				    @Instantiated let grand: Grand
				}
				""",
				"@Instantiable\nstruct Grand: Instantiable {\n    init() {}\n}",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Child` is constructed within the public mock trees of this module.
			public struct __safeDI_Child_MockConfiguration {
			    public init(
			        capacity: Int? = nil
			    ) {
			        self.grand = nil
			        self.capacity = capacity
			        self.safeDIBuilder = nil
			    }

			    init(
			        grand: (() -> Grand)? = nil,
			        capacity: Int? = nil,
			        _ safeDIBuilder: ((Grand, Int) -> Child)? = nil
			    ) {
			        self.grand = grand
			        self.capacity = capacity
			        self.safeDIBuilder = safeDIBuilder
			    }

			    private(set) var grand: (() -> Grand)?
			    /// `nil` keeps the default of `Child`'s `capacity`.
			    public private(set) var capacity: Int?
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    private(set) var safeDIBuilder: ((Grand, Int) -> Child)?
			}

			extension Child {
			    static func __safeDI_init(grand: Grand, capacity: Int?, safeDIBuilder: ((Grand, Int) -> Child)?) -> Child {
			        let capacity = capacity ?? (10)
			        return if let safeDIBuilder { safeDIBuilder(grand, capacity) } else { Child(grand: grand, capacity: capacity) }
			    }
			}
			#endif
			""" + "\n",
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            child: __safeDI_Child_MockConfiguration = .init()
			        ) {
			            self.child = child
			        }

			        public private(set) var child: __safeDI_Child_MockConfiguration
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        func __safeDI_child() -> Child {
			            let grand = if let safeDIBuilder = safeDIOverrides.child.grand { safeDIBuilder() } else { Grand() }
			            return Child.__safeDI_init(grand: grand, capacity: safeDIOverrides.child.capacity, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)
			        }
			        let child: Child = __safeDI_child()
			        return Service(child: child)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsConfiguredChildIntoLocals_whenChildIsBuiltInSendableBuilder() async throws {
		// M4.11, M3.9, M4.23: a configured child beneath a `SendableInstantiator`: its configuration's members are
		// `@Sendable`, read into locals before the `@Sendable` builder function, and passed to the construction function.
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
				"""
				@Instantiable
				public struct Child: Instantiable, Sendable {
				    public init(grand: Grand) {
				        self.grand = grand
				    }

				    @Instantiated let grand: Grand
				}
				""",
				"""
				@Instantiable
				public struct Grand: Instantiable, Sendable {
				    public init(capacity: Int = 10, label: String? = "grand") {}
				}
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

			        public private(set) var childBuilder: __safeDI_Child_MockConfiguration
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_childBuilder__childBuilder_grand_safeDIBuilder = safeDIOverrides.childBuilder.grand.safeDIBuilder
			        let __safeDI_childBuilder__childBuilder_grand_capacity = safeDIOverrides.childBuilder.grand.capacity
			        let __safeDI_childBuilder__childBuilder_grand_label = safeDIOverrides.childBuilder.grand.label
			        let __safeDI_childBuilder__safeDIBuilder = safeDIOverrides.childBuilder.safeDIBuilder
			        @Sendable func __safeDI_childBuilder() -> Child {
			            func __safeDI_grand() -> Grand {
			                return Grand.__safeDI_init(capacity: __safeDI_childBuilder__childBuilder_grand_capacity(), label: __safeDI_childBuilder__childBuilder_grand_label(), safeDIBuilder: __safeDI_childBuilder__childBuilder_grand_safeDIBuilder)
			            }
			            let grand: Grand = __safeDI_grand()
			            return Child.__safeDI_init(grand: grand, safeDIBuilder: __safeDI_childBuilder__safeDIBuilder)
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
			/// Configuration for how `Grand` is constructed within the public mock trees of this module.
			public struct __safeDI_Grand_MockConfiguration {
			    public init(
			        capacity: @autoclosure @escaping @Sendable () -> Int? = nil,
			        label: @autoclosure @escaping @Sendable () -> String? = __safeDI_Grand_mockDefault_label(),
			        _ safeDIBuilder: (@Sendable (Int, String?) -> Grand)? = nil
			    ) {
			        self.capacity = capacity
			        self.label = label
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Grand`'s `capacity`.
			    public private(set) var capacity: @Sendable () -> Int?
			    /// The default of `Grand`'s `label` unless set.
			    public private(set) var label: @Sendable () -> String?
			    /// Overrides how `Grand` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: (@Sendable (Int, String?) -> Grand)?
			}

			extension Grand {
			    nonisolated static func __safeDI_mockDefault_label() -> String? { "grand" }
			    static func __safeDI_init(capacity: Int?, label: String?, safeDIBuilder: (@Sendable (Int, String?) -> Grand)?) -> Grand {
			        let capacity = capacity ?? (10)
			        return if let safeDIBuilder { safeDIBuilder(capacity, label) } else { Grand(capacity: capacity, label: label) }
			    }
			}
			@usableFromInline nonisolated func __safeDI_Grand_mockDefault_label() -> String? { Grand.__safeDI_mockDefault_label() }

			/// Configuration for how `Child` is constructed within the public mock trees of this module.
			public struct __safeDI_Child_MockConfiguration {
			    public init(
			        grand: __safeDI_Grand_MockConfiguration = .init(),
			        _ safeDIBuilder: (@Sendable (Grand) -> Child)? = nil
			    ) {
			        self.grand = grand
			        self.safeDIBuilder = safeDIBuilder
			    }

			    public private(set) var grand: __safeDI_Grand_MockConfiguration
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: (@Sendable (Grand) -> Child)?
			}

			extension Child {
			    static func __safeDI_init(grand: Grand, safeDIBuilder: (@Sendable (Grand) -> Child)?) -> Child {
			        if let safeDIBuilder { safeDIBuilder(grand) } else { Child(grand: grand) }
			    }
			}
			#endif
			""" + "\n",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesForwardedTypeAsOptionalParameter_whenItsMockOnlyMockDefaultsIt() async throws {
		// M2.8b: the forwarded `user` defaults to its `package` `mockOnly` mock, so the public tier takes it as `T? = nil`
		// and resolves it in the mock's module, which can call that mock; another package calls the public tier. (M2.8,
		// the same with `User` itself `package`, cannot compile: the macro declares `Feature`'s `ForwardedProperties`
		// `public`, which cannot name a `package` type.)
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
					"""
					@Instantiable(generateMock: .public)
					public struct Feature: Instantiable {
					    package init(user: User, retries: Int = 3) {
					        self.user = user
					    }

					    @Forwarded let user: User
					}
					""",
					"""
					@Instantiable
					public struct User: Instantiable {
					    package init() {}
					}
					""",
					"""
					@Instantiable(mockOnly: true)
					extension User {
					    package static func mock() -> User {
					        User()
					    }
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Caller.swift": "import Core\n\n#if DEBUG\nfunc call() {\n    _ = Feature.mock()\n    _ = Feature.mock(user: nil, retries: 1)\n}\n#endif\n"], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == [
			"Core.swift": generatedFileHeader + """
			#if DEBUG
			extension Feature {
			    public static func mock(
			        user: User? = nil,
			        retries: Int? = nil
			    ) -> Feature {
			        let user = user ?? (User.mock())
			        let retries = retries ?? (3)
			        return Feature(user: user, retries: retries)
			    }
			}

			extension Feature {
			    public enum __safeDI_Feature_mock_FA70A635B61DA184 {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenConfigurationListsPublicMockOfAnotherModule() async {
		// M12.1: `Core` generates `Service`'s public mock, so `App` calls it rather than generating another.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]?["SafeDIConfiguration.swift"] ?? ""):3:1: error: `Service` already has a public `mock()` generated by `Core`. Remove it from additionalMocksToGenerate and call `Service.mock()`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
						"""
						@Instantiable(generateMock: .public)
						public struct Service: Instantiable {
						    public init() {}
						}
						""",
					]),
					ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: [
						"SafeDIConfiguration.swift": "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Service\"])\n",
					], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func query_throwsError_whenPublicMockCannotTakeRequiredParameter() async {
		// M13.3: whether a public mock can be generated is decided for one root, which the query builds too.
		await assertThrowsQueryError(diagnostics: { moduleFiles in
			"""
			\(moduleFiles["Core"]?.first { $0.lastPathComponent == "Feature.swift" }?.path ?? ""):1:29: error: SafeDI cannot generate the public mock of `Feature`: its `public` tier, which `generateMock: .public` requires, cannot take `user: User`, which `Feature` forwards, and cannot pass `nil` for it, since it is required. `User`'s own `@Instantiable` declaration is `internal`. Declare `User` `public`; give `User` a `mockOnly` mock; or use `generateMock: .internal`.
			"""
		}) {
			try await executeSafeDIToolQuery(
				typeName: "Feature",
				modules: [
					QueryTestModule("Core", [
						"""
						@Instantiable(generateMock: .public)
						public struct Feature: Instantiable {
						    init(user: User) {
						        self.user = user
						    }

						    @Forwarded let user: User
						}
						""",
						"""
						@Instantiable
						struct User: Instantiable {
						    init() {}
						}
						""",
					]),
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_putsMockAttributesOnEveryTier_whenPublicMockedRootHasThem() async throws {
		// M1.6, M2.15: a root with a public mock keeps its generated `init()`, and its attributes go on every tier.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, mockAttributes: "@MainActor", generateMock: .public)
				public struct Root: Instantiable {
				    public init(child: Child) {
				        self.child = child
				    }

				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public struct Child: Instantiable {
				    init(token: Token?) {
				        self.token = token
				    }

				    @Received(onlyIfAvailable: true) let token: Token?
				}
				""",
				"struct Token {}",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let child = Child(token: nil)
			        self.init(child: child)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init() {
			            self.child = nil
			        }

			        init(
			            child: ((Token?) -> Child)? = nil
			        ) {
			            self.child = child
			        }

			        private(set) var child: ((Token?) -> Child)?
			    }

			    @MainActor public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        Root.mock(token: nil, safeDIOverrides: safeDIOverrides)
			    }

			    @MainActor static func mock(
			        token: Token? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(token) } else { Child(token: token) }
			        return Root(child: child)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_C173F970333E7425 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesEachKindOfParameter_whenPublicMockedTypeForwardsReceivesAndDefaults() async throws {
		// M2.6, M2.9, M2.12, M2.13, M5.21, M6.2, M15.4: a required forwarded parameter first, a forwarded one with a default as
		// `T? = nil`, an optional forwarded one defaulting to its provider, a required received dependency nothing builds,
		// a builder for an instantiated one nothing fulfills, handed a public scope struct of the values built before it,
		// a received dependency the mock builds through a builder function, an alias in the tree, and an optional default
		// whose default is `nil`, which needs no provider.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    public init(name: String, count: Int = 1, tag: String? = "tag", token: Token, thing: Thing, child: Child, onCancel: (() -> Void)? = nil) {
				        self.name = name
				        self.count = count
				        self.tag = tag
				        self.token = token
				        self.thing = thing
				        self.child = child
				    }

				    @Forwarded let name: String
				    @Forwarded let count: Int
				    @Forwarded let tag: String?
				    @Received let token: Token
				    @Instantiated let thing: Thing
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public struct Child: Instantiable {
				    public init(config: Config, renamed: Config) {
				        self.config = config
				        self.renamed = renamed
				    }

				    @Received let config: Config
				    @Received(fulfilledByDependencyNamed: "config", ofType: Config.self) let renamed: Config
				}
				""",
				"""
				@Instantiable
				public struct Config: Instantiable {
				    public init(capacity: Int = 2) {}
				}
				""",
				"public struct Token {\n    public init() {}\n}",
				"public struct Thing {\n    public init() {}\n}",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Config` is constructed within the public mock trees of this module.
			public struct __safeDI_Config_MockConfiguration {
			    public init(
			        capacity: Int? = nil,
			        _ safeDIBuilder: ((Int) -> Config)? = nil
			    ) {
			        self.capacity = capacity
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Config`'s `capacity`.
			    public private(set) var capacity: Int?
			    /// Overrides how `Config` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: ((Int) -> Config)?
			}

			extension Config {
			    static func __safeDI_init(capacity: Int?, safeDIBuilder: ((Int) -> Config)?) -> Config {
			        let capacity = capacity ?? (2)
			        return if let safeDIBuilder { safeDIBuilder(capacity) } else { Config(capacity: capacity) }
			    }
			}
			#endif
			""" + "\n",
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    // These providers evaluate `Service`'s own defaults outside any actor, since SafeDI sees no isolation on it. If one
			    // reads the state of an actor `Service` takes from a conformance or a superclass and does not compile, give its
			    // `@Instantiable` `mockAttributes: "@MainActor"` (or that actor).
			    @usableFromInline nonisolated static func __safeDI_publicMockDefault_tag() -> String? { "tag" }

			    @frozen public enum SafeDIMockScope_Thing {
			        case thing(thing_Values)

			        public struct thing_Values {
			            public let config: Config
			            public let child: Child
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            config: __safeDI_Config_MockConfiguration = .init(),
			            child: ((Config, Config) -> Child)? = nil,
			            onCancel: (() -> Void)? = nil
			        ) {
			            self.config = config
			            self.child = child
			            self.onCancel = onCancel
			        }

			        public private(set) var config: __safeDI_Config_MockConfiguration
			        public private(set) var child: ((Config, Config) -> Child)?
			        /// The value of `Service`'s `onCancel`, `nil` unless set.
			        public private(set) var onCancel: (() -> Void)?
			    }

			    public static func mock(
			        count: Int? = nil,
			        name: String,
			        tag: String? = Service.__safeDI_publicMockDefault_tag(),
			        token: Token,
			        thingBuilder: @escaping (Service.SafeDIMockScope_Thing) -> Thing,
			        config: Config? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let __safeDI_thingBuilder = thingBuilder
			        let count = count ?? (1)
			        func __safeDI_config() -> Config {
			            return Config.__safeDI_init(capacity: safeDIOverrides.config.capacity, safeDIBuilder: safeDIOverrides.config.safeDIBuilder)
			        }
			        let config: Config = if let config { config } else { __safeDI_config() }
			        func __safeDI_child() -> Child {
			            #sourceLocation(file: "\(output.fixtures.compilerPath(of: "Child.swift"))", line: 9)
			            let renamed: Config = config
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(config, renamed) } else { Child(config: config, renamed: renamed) }
			        }
			        let child: Child = __safeDI_child()
			        let thing: Thing = __safeDI_thingBuilder(.thing(SafeDIMockScope_Thing.thing_Values(config: config, child: child)))
			        return Service(name: name, count: count, tag: tag, token: token, thing: thing, child: child, onCancel: safeDIOverrides.onCancel)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_10B708BB4FFF7250 {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsConfiguredChildrenThroughConstructionFunctions_whenChildrenAreExtensionBasedOrErased() async throws {
		// M3.6, M4.25, M6.5: an extension-based child's construction function calls `instantiate(…)`; an erased child is
		// wrapped where the mock builds it; an optional default of `nil` needs no provider; and two types whose names
		// read the same as identifiers get configurations named apart, in sorted type order.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Root: Instantiable {
				    public init(shelf: Shelf, service: AnyService, viewModel: Feed.ViewModel, otherViewModel: Feed_ViewModel) {
				        self.shelf = shelf
				        self.service = service
				        self.viewModel = viewModel
				        self.otherViewModel = otherViewModel
				    }

				    @Instantiated let shelf: Shelf
				    @Instantiated(fulfilledByType: "ConcreteService", erasedToConcreteExistential: true) let service: AnyService
				    @Instantiated let viewModel: Feed.ViewModel
				    @Instantiated let otherViewModel: Feed_ViewModel
				}
				""",
				"""
				public struct Shelf {
				    public init() {}
				}

				@Instantiable
				extension Shelf: Instantiable {
				    public static func instantiate(capacity: Int = 3, label: String? = nil) -> Shelf {
				        Shelf()
				    }
				}
				""",
				"""
				public protocol ServiceProtocol {}

				public struct AnyService: ServiceProtocol {
				    public init(_ service: some ServiceProtocol) {}
				}

				@Instantiable
				public struct ConcreteService: ServiceProtocol, Instantiable {
				    public init(retries: Int = 2) {}
				}
				""",
				"""
				public enum Feed {
				    @Instantiable
				    public struct ViewModel: Instantiable {
				        public init(title: String? = "feed") {}
				    }
				}
				""",
				"""
				@Instantiable
				public struct Feed_ViewModel: Instantiable {
				    public init(title: String? = "other") {}
				}
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
			            shelf: __safeDI_Shelf_MockConfiguration = .init(),
			            service: __safeDI_ConcreteService_MockConfiguration = .init(),
			            viewModel: __safeDI_Feed_ViewModel_MockConfiguration = .init(),
			            otherViewModel: __safeDI_Feed_ViewModel__MockConfiguration = .init()
			        ) {
			            self.shelf = shelf
			            self.service = service
			            self.viewModel = viewModel
			            self.otherViewModel = otherViewModel
			        }

			        public private(set) var shelf: __safeDI_Shelf_MockConfiguration
			        public private(set) var service: __safeDI_ConcreteService_MockConfiguration
			        public private(set) var viewModel: __safeDI_Feed_ViewModel_MockConfiguration
			        public private(set) var otherViewModel: __safeDI_Feed_ViewModel__MockConfiguration
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_shelf() -> Shelf {
			            return Shelf.__safeDI_init(capacity: safeDIOverrides.shelf.capacity, label: safeDIOverrides.shelf.label, safeDIBuilder: safeDIOverrides.shelf.safeDIBuilder)
			        }
			        let shelf: Shelf = __safeDI_shelf()
			        func __safeDI_service() -> AnyService {
			            return AnyService(ConcreteService.__safeDI_init(retries: safeDIOverrides.service.retries, safeDIBuilder: safeDIOverrides.service.safeDIBuilder))
			        }
			        let service: AnyService = __safeDI_service()
			        func __safeDI_viewModel() -> Feed.ViewModel {
			            return Feed.ViewModel.__safeDI_init(title: safeDIOverrides.viewModel.title, safeDIBuilder: safeDIOverrides.viewModel.safeDIBuilder)
			        }
			        let viewModel: Feed.ViewModel = __safeDI_viewModel()
			        func __safeDI_otherViewModel() -> Feed_ViewModel {
			            return Feed_ViewModel.__safeDI_init(title: safeDIOverrides.otherViewModel.title, safeDIBuilder: safeDIOverrides.otherViewModel.safeDIBuilder)
			        }
			        let otherViewModel: Feed_ViewModel = __safeDI_otherViewModel()
			        return Root(shelf: shelf, service: service, viewModel: viewModel, otherViewModel: otherViewModel)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Shelf` is constructed within the public mock trees of this module.
			public struct __safeDI_Shelf_MockConfiguration {
			    public init(
			        capacity: Int? = nil,
			        label: String? = nil,
			        _ safeDIBuilder: ((Int, String?) -> Shelf)? = nil
			    ) {
			        self.capacity = capacity
			        self.label = label
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Shelf`'s `capacity`.
			    public private(set) var capacity: Int?
			    /// The default of `Shelf`'s `label` unless set.
			    public private(set) var label: String?
			    /// Overrides how `Shelf` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: ((Int, String?) -> Shelf)?
			}

			extension Shelf {
			    static func __safeDI_init(capacity: Int?, label: String?, safeDIBuilder: ((Int, String?) -> Shelf)?) -> Shelf {
			        let capacity = capacity ?? (3)
			        return if let safeDIBuilder { safeDIBuilder(capacity, label) } else { Shelf.instantiate(capacity: capacity, label: label) }
			    }
			}

			/// Configuration for how `ConcreteService` is constructed within the public mock trees of this module.
			public struct __safeDI_ConcreteService_MockConfiguration {
			    public init(
			        retries: Int? = nil,
			        _ safeDIBuilder: ((Int) -> ConcreteService)? = nil
			    ) {
			        self.retries = retries
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `ConcreteService`'s `retries`.
			    public private(set) var retries: Int?
			    /// Overrides how `ConcreteService` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: ((Int) -> ConcreteService)?
			}

			extension ConcreteService {
			    static func __safeDI_init(retries: Int?, safeDIBuilder: ((Int) -> ConcreteService)?) -> ConcreteService {
			        let retries = retries ?? (2)
			        return if let safeDIBuilder { safeDIBuilder(retries) } else { ConcreteService(retries: retries) }
			    }
			}

			/// Configuration for how `Feed.ViewModel` is constructed within the public mock trees of this module.
			public struct __safeDI_Feed_ViewModel_MockConfiguration {
			    public init(
			        title: String? = __safeDI_Feed_ViewModel_mockDefault_title(),
			        _ safeDIBuilder: ((String?) -> Feed.ViewModel)? = nil
			    ) {
			        self.title = title
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// The default of `Feed.ViewModel`'s `title` unless set.
			    public private(set) var title: String?
			    /// Overrides how `Feed.ViewModel` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: ((String?) -> Feed.ViewModel)?
			}

			extension Feed.ViewModel {
			    nonisolated static func __safeDI_mockDefault_title() -> String? { "feed" }
			    static func __safeDI_init(title: String?, safeDIBuilder: ((String?) -> Feed.ViewModel)?) -> Feed.ViewModel {
			        if let safeDIBuilder { safeDIBuilder(title) } else { Feed.ViewModel(title: title) }
			    }
			}
			@usableFromInline nonisolated func __safeDI_Feed_ViewModel_mockDefault_title() -> String? { Feed.ViewModel.__safeDI_mockDefault_title() }

			/// Configuration for how `Feed_ViewModel` is constructed within the public mock trees of this module.
			public struct __safeDI_Feed_ViewModel__MockConfiguration {
			    public init(
			        title: String? = __safeDI_Feed_ViewModel__mockDefault_title(),
			        _ safeDIBuilder: ((String?) -> Feed_ViewModel)? = nil
			    ) {
			        self.title = title
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// The default of `Feed_ViewModel`'s `title` unless set.
			    public private(set) var title: String?
			    /// Overrides how `Feed_ViewModel` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: ((String?) -> Feed_ViewModel)?
			}

			extension Feed_ViewModel {
			    nonisolated static func __safeDI_mockDefault_title() -> String? { "other" }
			    static func __safeDI_init(title: String?, safeDIBuilder: ((String?) -> Feed_ViewModel)?) -> Feed_ViewModel {
			        if let safeDIBuilder { safeDIBuilder(title) } else { Feed_ViewModel(title: title) }
			    }
			}
			@usableFromInline nonisolated func __safeDI_Feed_ViewModel__mockDefault_title() -> String? { Feed_ViewModel.__safeDI_mockDefault_title() }
			#endif
			""" + "\n",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_closesCycleWithConstantCallingEnclosingBuilder_whenPublicMockedTypeIsBuiltAgainThroughInstantiator() async throws {
		// `A.mock()` builds `b`, whose instantiator builds `C`, whose `a` builds an `A` again, whose `b` closes the cycle by
		// calling the function the mock builds `b` with.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B"]).replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: .public)\n"),
				seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let cBuilder: Instantiator<C>"]),
				seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let a: A"]),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            b: __safeDI_B_MockConfiguration = .init()
			        ) {
			            self.b = b
			        }

			        public private(set) var b: __safeDI_B_MockConfiguration
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_b() -> B {
			            func __safeDI_cBuilder() -> C {
			                func __safeDI_a() -> A {
			                    let b: B = __safeDI_b()
			                    return A.__safeDI_init(b: b, safeDIBuilder: nil)
			                }
			                let a: A = __safeDI_a()
			                return C.__safeDI_init(a: a, safeDIBuilder: safeDIOverrides.b.cBuilder.safeDIBuilder)
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return B.__safeDI_init(cBuilder: cBuilder, safeDIBuilder: safeDIOverrides.b.safeDIBuilder)
			        }
			        let b: B = __safeDI_b()
			        return A(b: b)
			    }
			}

			extension A {
			    public enum __safeDI_A_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `A` is constructed within the public mock trees of this module.
			public struct __safeDI_A_MockConfiguration {
			    public init(
			        b: __safeDI_B_MockConfiguration = .init(),
			        _ safeDIBuilder: ((B) -> A)? = nil
			    ) {
			        self.b = b
			        self.safeDIBuilder = safeDIBuilder
			    }

			    public private(set) var b: __safeDI_B_MockConfiguration
			    /// Overrides how `A` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: ((B) -> A)?
			}

			extension A {
			    static func __safeDI_init(b: B, safeDIBuilder: ((B) -> A)?) -> A {
			        if let safeDIBuilder { safeDIBuilder(b) } else { A(b: b) }
			    }
			}

			/// Configuration for how `C` is constructed within the public mock trees of this module.
			public struct __safeDI_C_MockConfiguration {
			    public init(
			        _ safeDIBuilder: ((A) -> C)? = nil
			    ) {
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// Overrides how `C` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: ((A) -> C)?
			}

			extension C {
			    static func __safeDI_init(a: A, safeDIBuilder: ((A) -> C)?) -> C {
			        if let safeDIBuilder { safeDIBuilder(a) } else { C(a: a) }
			    }
			}

			/// Configuration for how `B` is constructed within the public mock trees of this module.
			public struct __safeDI_B_MockConfiguration {
			    public init(
			        cBuilder: __safeDI_C_MockConfiguration = .init(),
			        _ safeDIBuilder: ((Instantiator<C>) -> B)? = nil
			    ) {
			        self.cBuilder = cBuilder
			        self.safeDIBuilder = safeDIBuilder
			    }

			    public private(set) var cBuilder: __safeDI_C_MockConfiguration
			    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: ((Instantiator<C>) -> B)?
			}

			extension B {
			    static func __safeDI_init(cBuilder: Instantiator<C>, safeDIBuilder: ((Instantiator<C>) -> B)?) -> B {
			        if let safeDIBuilder { safeDIBuilder(cBuilder) } else { B(cBuilder: cBuilder) }
			    }
			}
			#endif
			""" + "\n",
		])
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesCycleParameterToFunctionItPromotes_whenPublicMockPromotesDependencyCycleClosesOnBeneathScopeDeclaringLabel(lazilyInstantiated: Bool) async throws {
		// `A`'s public mock builds the `b` it receives, unless its caller passes one: `B` receives `session`, which `C`
		// declares again before closing the cycle on `b`, so the function the mock builds `b` with takes `session`, and the
		// mock passes its own.
		let b = lazilyInstantiated ? "LazilyInstantiated<B>" : "B"
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received let b: \(b)"]).replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: .public)\n"),
				seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let session: Session", "@Instantiated let cBuilder: Instantiator<C>"]),
				seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let b: \(b)"]),
				seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == (lazilyInstantiated ? [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            session: (() -> Session)? = nil,
			            b: __safeDI_B_MockConfiguration = .init()
			        ) {
			            self.session = session
			            self.b = b
			        }

			        public private(set) var session: (() -> Session)?
			        public private(set) var b: __safeDI_B_MockConfiguration
			    }

			    public static func mock(
			        b: B? = nil,
			        session: Session? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        let session = if let session { session } else if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        func __safeDI_b(session: Session) -> B {
			            func __safeDI_cBuilder() -> C {
			                let session = if let safeDIBuilder = safeDIOverrides.b.cBuilder.session { safeDIBuilder() } else { Session() }
			                let b = LazilyInstantiated<B> {
			                    __safeDI_b(session: session)
			                }
			                return C.__safeDI_init(session: session, b: b, safeDIBuilder: safeDIOverrides.b.cBuilder.safeDIBuilder)
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return B.__safeDI_init(session: session, cBuilder: cBuilder, safeDIBuilder: safeDIOverrides.b.safeDIBuilder)
			        }
			        let b = LazilyInstantiated<B> {
			            if let b { b } else { __safeDI_b(session: session) }
			        }
			        return A(b: b)
			    }
			}

			extension A {
			    public enum __safeDI_A_mock_994335C3EC9B26A0 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `C` is constructed within the public mock trees of this module.
			public struct __safeDI_C_MockConfiguration {
			    public init(
			        session: (() -> Session)? = nil,
			        _ safeDIBuilder: ((Session, LazilyInstantiated<B>) -> C)? = nil
			    ) {
			        self.session = session
			        self.safeDIBuilder = safeDIBuilder
			    }

			    public private(set) var session: (() -> Session)?
			    /// Overrides how `C` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: ((Session, LazilyInstantiated<B>) -> C)?
			}

			extension C {
			    static func __safeDI_init(session: Session, b: LazilyInstantiated<B>, safeDIBuilder: ((Session, LazilyInstantiated<B>) -> C)?) -> C {
			        if let safeDIBuilder { safeDIBuilder(session, b) } else { C(session: session, b: b) }
			    }
			}

			/// Configuration for how `B` is constructed within the public mock trees of this module.
			public struct __safeDI_B_MockConfiguration {
			    public init(
			        cBuilder: __safeDI_C_MockConfiguration = .init(),
			        _ safeDIBuilder: ((Session, Instantiator<C>) -> B)? = nil
			    ) {
			        self.cBuilder = cBuilder
			        self.safeDIBuilder = safeDIBuilder
			    }

			    public private(set) var cBuilder: __safeDI_C_MockConfiguration
			    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: ((Session, Instantiator<C>) -> B)?
			}

			extension B {
			    static func __safeDI_init(session: Session, cBuilder: Instantiator<C>, safeDIBuilder: ((Session, Instantiator<C>) -> B)?) -> B {
			        if let safeDIBuilder { safeDIBuilder(session, cBuilder) } else { B(session: session, cBuilder: cBuilder) }
			    }
			}
			#endif
			""" + "\n",
		] : [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            session: (() -> Session)? = nil,
			            b: __safeDI_B_MockConfiguration = .init()
			        ) {
			            self.session = session
			            self.b = b
			        }

			        public private(set) var session: (() -> Session)?
			        public private(set) var b: __safeDI_B_MockConfiguration
			    }

			    public static func mock(
			        b: B? = nil,
			        session: Session? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        let session = if let session { session } else if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        func __safeDI_b(session: Session) -> B {
			            func __safeDI_cBuilder() -> C {
			                let session = if let safeDIBuilder = safeDIOverrides.b.cBuilder.session { safeDIBuilder() } else { Session() }
			                let b: B = __safeDI_b(session: session)
			                return C.__safeDI_init(session: session, b: b, safeDIBuilder: safeDIOverrides.b.cBuilder.safeDIBuilder)
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return B.__safeDI_init(session: session, cBuilder: cBuilder, safeDIBuilder: safeDIOverrides.b.safeDIBuilder)
			        }
			        let b: B = if let b { b } else { __safeDI_b(session: session) }
			        return A(b: b)
			    }
			}

			extension A {
			    public enum __safeDI_A_mock_994335C3EC9B26A0 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `C` is constructed within the public mock trees of this module.
			public struct __safeDI_C_MockConfiguration {
			    public init(
			        session: (() -> Session)? = nil,
			        _ safeDIBuilder: ((Session, B) -> C)? = nil
			    ) {
			        self.session = session
			        self.safeDIBuilder = safeDIBuilder
			    }

			    public private(set) var session: (() -> Session)?
			    /// Overrides how `C` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: ((Session, B) -> C)?
			}

			extension C {
			    static func __safeDI_init(session: Session, b: B, safeDIBuilder: ((Session, B) -> C)?) -> C {
			        if let safeDIBuilder { safeDIBuilder(session, b) } else { C(session: session, b: b) }
			    }
			}

			/// Configuration for how `B` is constructed within the public mock trees of this module.
			public struct __safeDI_B_MockConfiguration {
			    public init(
			        cBuilder: __safeDI_C_MockConfiguration = .init(),
			        _ safeDIBuilder: ((Session, Instantiator<C>) -> B)? = nil
			    ) {
			        self.cBuilder = cBuilder
			        self.safeDIBuilder = safeDIBuilder
			    }

			    public private(set) var cBuilder: __safeDI_C_MockConfiguration
			    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: ((Session, Instantiator<C>) -> B)?
			}

			extension B {
			    static func __safeDI_init(session: Session, cBuilder: Instantiator<C>, safeDIBuilder: ((Session, Instantiator<C>) -> B)?) -> B {
			        if let safeDIBuilder { safeDIBuilder(session, cBuilder) } else { B(session: session, cBuilder: cBuilder) }
			    }
			}
			#endif
			""" + "\n",
		]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilAndProviders_whenConfiguredTypeIsBuiltBeneathCycleEdge() async throws {
		// M4.10: `B` -> `A` is the cycle edge, so the `A` that `A`'s public mock builds beneath `B` reads no configuration: it passes
		// `nil` for each non-optional default, which its construction function resolves, and the provider's value for the
		// optional one.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct A: Instantiable {
				    public init(bBuilder: Instantiator<B>, label: String = "a", tag: String? = "tag") {
				        self.bBuilder = bBuilder
				    }

				    @Instantiated let bBuilder: Instantiator<B>
				}
				""",
				"""
				@Instantiable
				public struct B: Instantiable {
				    public init(aBuilder: Instantiator<A>) {
				        self.aBuilder = aBuilder
				    }

				    @Instantiated let aBuilder: Instantiator<A>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    // These providers evaluate `A`'s own defaults outside any actor, since SafeDI sees no isolation on it. If one
			    // reads the state of an actor `A` takes from a conformance or a superclass and does not compile, give its
			    // `@Instantiable` `mockAttributes: "@MainActor"` (or that actor).
			    @usableFromInline nonisolated static func __safeDI_publicMockDefault_tag() -> String? { "tag" }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            bBuilder: __safeDI_B_MockConfiguration = .init(),
			            tag: String? = A.__safeDI_publicMockDefault_tag()
			        ) {
			            self.bBuilder = bBuilder
			            self.tag = tag
			        }

			        public private(set) var bBuilder: __safeDI_B_MockConfiguration
			        /// The default of `A`'s `tag` unless set; `.init(tag: nil)` passes `nil`.
			        public private(set) var tag: String?
			    }

			    public static func mock(
			        label: String? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        let label = label ?? ("a")
			        func __safeDI_bBuilder() -> B {
			            func __safeDI_aBuilder() -> A {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return A.__safeDI_init(bBuilder: bBuilder, label: nil, tag: A.__safeDI_mockDefault_tag(), safeDIBuilder: nil)
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B.__safeDI_init(aBuilder: aBuilder, safeDIBuilder: safeDIOverrides.bBuilder.safeDIBuilder)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return A(bBuilder: bBuilder, label: label, tag: safeDIOverrides.tag)
			    }
			}

			extension A {
			    public enum __safeDI_A_mock_C0F16A51E96B1930 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `A` is constructed within the public mock trees of this module.
			public struct __safeDI_A_MockConfiguration {
			    public init(
			        bBuilder: __safeDI_B_MockConfiguration = .init(),
			        label: String? = nil,
			        tag: String? = __safeDI_A_mockDefault_tag(),
			        _ safeDIBuilder: ((Instantiator<B>, String, String?) -> A)? = nil
			    ) {
			        self.bBuilder = bBuilder
			        self.label = label
			        self.tag = tag
			        self.safeDIBuilder = safeDIBuilder
			    }

			    public private(set) var bBuilder: __safeDI_B_MockConfiguration
			    /// `nil` keeps the default of `A`'s `label`.
			    public private(set) var label: String?
			    /// The default of `A`'s `tag` unless set.
			    public private(set) var tag: String?
			    /// Overrides how `A` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: ((Instantiator<B>, String, String?) -> A)?
			}

			extension A {
			    nonisolated static func __safeDI_mockDefault_tag() -> String? { "tag" }
			    static func __safeDI_init(bBuilder: Instantiator<B>, label: String?, tag: String?, safeDIBuilder: ((Instantiator<B>, String, String?) -> A)?) -> A {
			        let label = label ?? ("a")
			        return if let safeDIBuilder { safeDIBuilder(bBuilder, label, tag) } else { A(bBuilder: bBuilder, label: label, tag: tag) }
			    }
			}
			@usableFromInline nonisolated func __safeDI_A_mockDefault_tag() -> String? { A.__safeDI_mockDefault_tag() }

			/// Configuration for how `B` is constructed within the public mock trees of this module.
			public struct __safeDI_B_MockConfiguration {
			    public init(
			        _ safeDIBuilder: ((Instantiator<A>) -> B)? = nil
			    ) {
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: ((Instantiator<A>) -> B)?
			}

			extension B {
			    static func __safeDI_init(aBuilder: Instantiator<A>, safeDIBuilder: ((Instantiator<A>) -> B)?) -> B {
			        if let safeDIBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			    }
			}
			#endif
			""" + "\n",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesStagedBuilderForHole_whenHoleIsBuiltInSendableBuilderFunction() async throws {
		// M7.4: a hole beneath a `SendableInstantiator` takes a staged builder, as a seam's does (decision 22): the mock
		// calls its first stage before the `@Sendable` builder function, which calls the stage it returns.
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
				"""
				@Instantiable
				public struct Child: Instantiable, Sendable {
				    public init(thing: Thing) {
				        self.thing = thing
				    }

				    @Instantiated let thing: Thing
				}
				""",
				"public struct Thing: Sendable {\n    public init() {}\n}",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    public enum SafeDIStagedMockScope_Thing_childBuilder_thing {
			        public struct Stage1 {}

			        public struct Stage2 {}
			    }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            childBuilder: (@Sendable (Thing) -> Child)? = nil
			        ) {
			            self.childBuilder = childBuilder
			        }

			        public private(set) var childBuilder: (@Sendable (Thing) -> Child)?
			    }

			    public static func mock(
			        thingBuilder_childBuilder_thing: @escaping (Root.SafeDIStagedMockScope_Thing_childBuilder_thing.Stage1) -> @Sendable (Root.SafeDIStagedMockScope_Thing_childBuilder_thing.Stage2) -> Thing,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_thingBuilder_childBuilder_thing = thingBuilder_childBuilder_thing
			        let __safeDI_childBuilder__safeDIBuilder = safeDIOverrides.childBuilder
			        let __safeDI_thingBuilder_childBuilder_thing_Stage2 = __safeDI_thingBuilder_childBuilder_thing(SafeDIStagedMockScope_Thing_childBuilder_thing.Stage1())
			        @Sendable func __safeDI_childBuilder() -> Child {
			            let thing: Thing = __safeDI_thingBuilder_childBuilder_thing_Stage2(SafeDIStagedMockScope_Thing_childBuilder_thing.Stage2())
			            return if let safeDIBuilder = __safeDI_childBuilder__safeDIBuilder { safeDIBuilder(thing) } else { Child(thing: thing) }
			        }
			        let childBuilder = SendableInstantiator<Child>(__safeDI_childBuilder)
			        return Root(childBuilder: childBuilder)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_98589B73D761718A {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenRequiredReceivedParameterAndHoleAreNarrower() async {
		// M2.9b with two receivers, and M7.1b's hole whose type is narrower: each is reported, with a note at each receive or
		// instantiation.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:29: error: SafeDI cannot generate the public mock of `Service`: its `public` tier, which `generateMock: .public` requires, cannot take `thingBuilder`, whose case `thing` builds `Thing` for the hole `thing`, and cannot pass `nil` for it, since it is required. `Thing` is declared `internal`. Declare `Thing` `public`; declare in this module, or a module it depends on, a `mockOnly` `@Instantiable` type that fulfills `Thing` (`@Instantiable(fulfillingAdditionalTypes: [Thing.self], mockOnly: true)`), which the mock builds instead of taking `thingBuilder`, leaving production's hole as it is; or use `generateMock: .internal`.
			\(fixtures["Thing.swift"]):1:1: note: `Thing` is declared `internal` here.
			\(fixtures["Thing.swift"]):1:1-1:1: fixit: public\(" ")
			\(fixtures["Service.swift"]):10:5: note: `Service` instantiates `thing: Thing` here.
			\(fixtures["Service.swift"]):1:29: error: SafeDI cannot generate the public mock of `Service`: its `public` tier, which `generateMock: .public` requires, cannot take `token: Token`, which the initializers of `Left` and `Right` receive, and cannot pass `nil` for it, since it is required. `Token` is declared `internal`. Declare `Token` `public`; receive it with `onlyIfAvailable: true` and an optional type; or use `generateMock: .internal`.
			\(fixtures["Token.swift"]):1:1: note: `Token` is declared `internal` here.
			\(fixtures["Token.swift"]):1:1-1:1: fixit: public\(" ")
			\(fixtures["Left.swift"]):7:5: note: `Left` receives `token: Token` here.
			\(fixtures["Right.swift"]):7:5: note: `Right` receives `token: Token` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    init(left: Left, right: Right, thing: Thing) {
					        self.left = left
					        self.right = right
					        self.thing = thing
					    }

					    @Instantiated let left: Left
					    @Instantiated let thing: Thing
					    @Instantiated let right: Right
					}
					""",
					"""
					@Instantiable
					public struct Left: Instantiable {
					    init(token: Token) {
					        self.token = token
					    }

					    @Received let token: Token
					}
					""",
					"""
					@Instantiable
					public struct Right: Instantiable {
					    init(token: Token) {
					        self.token = token
					    }

					    @Received let token: Token
					}
					""",
					"struct Token {}",
					"struct Thing {}",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – the canonical fixture

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesPublicAndPackageTiers_whenCanonicalServiceTakesPackageParameter() async throws {
		// M2.2, M3.14, M3.18, M3.18b, M4.1, M4.2, M5.5, M5.3, M6.1, M6.3, M6.3b: the canonical `Service`. Its public tier
		// omits the package `session`, which its package tier takes; `name` and `policy` are fields of `SafeDIOverrides`,
		// `policy` `package`, as `Policy`'s declaration is; another package calls the public tier.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.canonicalModules(appCaller: Self.canonicalAppCaller),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == [
			"Core.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Dashboard {
			    @usableFromInline @MainActor static func __safeDI_publicMockDefault_label() -> String? { Defaults.label }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            vm: __safeDI_Core_ViewModel_MockConfiguration = .init()
			        ) {
			            self.vm = vm
			        }

			        public private(set) var vm: __safeDI_Core_ViewModel_MockConfiguration
			    }

			    public static func mock(
			        label: String? = Dashboard.__safeDI_publicMockDefault_label(),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Dashboard {
			        func __safeDI_vm() -> ViewModel {
			            return ViewModel.__safeDI_init(title: safeDIOverrides.vm.title, safeDIBuilder: safeDIOverrides.vm.safeDIBuilder)
			        }
			        let vm: ViewModel = __safeDI_vm()
			        return Dashboard(vm: vm, label: label)
			    }
			}

			extension Dashboard {
			    public enum __safeDI_Dashboard_mock_81EB86AE43991940 {}
			}
			#endif

			#if DEBUG
			extension Service {
			    // These providers evaluate `Service`'s own defaults outside any actor, since SafeDI sees no isolation on it. If one
			    // reads the state of an actor `Service` takes from a conformance or a superclass and does not compile, give its
			    // `@Instantiable` `mockAttributes: "@MainActor"` (or that actor).
			    @usableFromInline nonisolated static func __safeDI_publicMockDefault_name() -> String? { Defaults.name }
			    nonisolated static func __safeDI_publicMockDefault_policy() -> Policy? { Defaults.policy }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            logger: __safeDI_Core_FakeLogger_MockConfiguration = .init(),
			            analytics: (() -> Analytics)? = nil,
			            tokenCache: __safeDI_Core_TokenCache_MockConfiguration = .init(),
			            name: String? = Service.__safeDI_publicMockDefault_name()
			        ) {
			            self.logger = logger
			            self.analytics = analytics
			            self.session = nil
			            self.tokenCache = tokenCache
			            self.name = name
			            self.policy = Service.__safeDI_publicMockDefault_policy()
			        }

			        package init(
			            logger: __safeDI_Core_FakeLogger_MockConfiguration = .init(),
			            analytics: (() -> Analytics)? = nil,
			            session: (() -> Session)? = nil,
			            tokenCache: __safeDI_Core_TokenCache_MockConfiguration = .init(),
			            name: String? = Service.__safeDI_publicMockDefault_name(),
			            policy: Policy? = Service.__safeDI_publicMockDefault_policy()
			        ) {
			            self.logger = logger
			            self.analytics = analytics
			            self.session = session
			            self.tokenCache = tokenCache
			            self.name = name
			            self.policy = policy
			        }

			        public private(set) var logger: __safeDI_Core_FakeLogger_MockConfiguration
			        public private(set) var analytics: (() -> Analytics)?
			        package private(set) var session: (() -> Session)?
			        public private(set) var tokenCache: __safeDI_Core_TokenCache_MockConfiguration
			        /// The default of `Service`'s `name` unless set; `.init(name: nil)` passes `nil`.
			        public private(set) var name: String?
			        /// The default of `Service`'s `policy` unless set; `.init(policy: nil)` passes `nil`.
			        package private(set) var policy: Policy?
			    }

			    public static func mock(
			        retries: Int? = nil,
			        analytics: Analytics? = nil,
			        theme: Theme? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        Service.mock(retries: retries, analytics: analytics, session: nil, theme: theme, safeDIOverrides: safeDIOverrides)
			    }

			    package static func mock(
			        retries: Int? = nil,
			        analytics: Analytics? = nil,
			        session: Session? = nil,
			        theme: Theme? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let retries = retries ?? (3)
			        func __safeDI_logger() -> Logger {
			            return FakeLogger.__safeDI_mock(verbose: safeDIOverrides.logger.verbose, safeDIBuilder: safeDIOverrides.logger.safeDIBuilder)
			        }
			        let logger: Logger = __safeDI_logger()
			        func __safeDI_analytics() -> Analytics {
			            if let analytics { analytics } else if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
			        }
			        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
			        let session = if let session { session } else if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        func __safeDI_tokenCache() -> TokenCache {
			            return TokenCache.__safeDI_init(analytics: analytics.instance, session: session, theme: theme, capacity: safeDIOverrides.tokenCache.capacity, safeDIBuilder: safeDIOverrides.tokenCache.safeDIBuilder)
			        }
			        let tokenCache: TokenCache = __safeDI_tokenCache()
			        return Service(analytics: analytics, logger: logger, tokenCache: tokenCache, retries: retries, name: safeDIOverrides.name, policy: safeDIOverrides.policy)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_209346FEA041FD20 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `ViewModel` is constructed within the public mock trees of module `Core`.
			public struct __safeDI_Core_ViewModel_MockConfiguration {
			    public init(
			        title: String? = __safeDI_Core_ViewModel_mockDefault_title()
			    ) {
			        self.title = title
			        self.safeDIBuilder = nil
			    }

			    package init(
			        title: String? = __safeDI_Core_ViewModel_mockDefault_title(),
			        _ safeDIBuilder: ((String?) -> ViewModel)? = nil
			    ) {
			        self.title = title
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// The default of `ViewModel`'s `title` unless set.
			    public private(set) var title: String?
			    /// Overrides how `ViewModel` is constructed. Parameters match the type’s initializer or custom mock method.
			    package private(set) var safeDIBuilder: ((String?) -> ViewModel)?
			}

			extension ViewModel {
			    nonisolated static func __safeDI_mockDefault_title() -> String? { defaultTitle }
			    static func __safeDI_init(title: String?, safeDIBuilder: ((String?) -> ViewModel)?) -> ViewModel {
			        if let safeDIBuilder { safeDIBuilder(title) } else { ViewModel(title: title) }
			    }
			}
			@usableFromInline nonisolated func __safeDI_Core_ViewModel_mockDefault_title() -> String? { ViewModel.__safeDI_mockDefault_title() }

			/// Configuration for how `FakeLogger` is constructed within the public mock trees of module `Core`.
			public struct __safeDI_Core_FakeLogger_MockConfiguration {
			    public init(
			        verbose: Bool? = nil
			    ) {
			        self.verbose = verbose
			        self.safeDIBuilder = nil
			    }

			    package init(
			        verbose: Bool? = nil,
			        _ safeDIBuilder: ((Bool) -> FakeLogger)? = nil
			    ) {
			        self.verbose = verbose
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `FakeLogger`'s `verbose`.
			    public private(set) var verbose: Bool?
			    /// Overrides how `FakeLogger` is constructed. Parameters match the type’s initializer or custom mock method.
			    package private(set) var safeDIBuilder: ((Bool) -> FakeLogger)?
			}

			extension FakeLogger {
			    static func __safeDI_mock(verbose: Bool?, safeDIBuilder: ((Bool) -> FakeLogger)?) -> Logger {
			        let verbose = verbose ?? (false)
			        return if let safeDIBuilder { safeDIBuilder(verbose) } else { FakeLogger.mock(verbose: verbose) }
			    }
			}

			/// Configuration for how `TokenCache` is constructed within the public mock trees of module `Core`.
			public struct __safeDI_Core_TokenCache_MockConfiguration {
			    public init(
			        capacity: Int? = nil
			    ) {
			        self.capacity = capacity
			        self.safeDIBuilder = nil
			    }

			    package init(
			        capacity: Int? = nil,
			        _ safeDIBuilder: ((Analytics, Session, Theme?, Int) -> TokenCache)? = nil
			    ) {
			        self.capacity = capacity
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `TokenCache`'s `capacity`.
			    public private(set) var capacity: Int?
			    /// Overrides how `TokenCache` is constructed. Parameters match the type’s initializer or custom mock method.
			    package private(set) var safeDIBuilder: ((Analytics, Session, Theme?, Int) -> TokenCache)?
			}

			extension TokenCache {
			    static func __safeDI_init(analytics: Analytics, session: Session, theme: Theme?, capacity: Int?, safeDIBuilder: ((Analytics, Session, Theme?, Int) -> TokenCache)?) -> TokenCache {
			        let capacity = capacity ?? (defaultCapacity)
			        return if let safeDIBuilder { safeDIBuilder(analytics, session, theme, capacity) } else { TokenCache(analytics: analytics, session: session, theme: theme, capacity: capacity) }
			    }
			}
			#endif
			""" + "\n",
		])
		// The public mocks build what `Core`'s internal mocks of the same declarations build.
		try await expectValuesAgreeWithInlineMocks(of: Self.canonicalModules(appCaller: Self.canonicalAppCaller).filter { $0.name == "Core" }, output: output, probes: [DifferentialValueProbe("Service.mock()"), DifferentialValueProbe("Dashboard.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_defaultsClosureLiteralThroughProvider_whenOptionalClosureDefaultIsReachedThroughSendableInstantiatorInPublicMock() async throws {
		// The public twin of #529's cell: a closure literal default of a type built beneath a `SendableInstantiator` is a
		// `@Sendable` autoclosure member of the type's configuration, which defaults to the forwarder of the provider that
		// evaluates the literal, so no literal is ever the autoclosure itself.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Root: Instantiable {
				    public init(childBuilder: SendableInstantiator<Child>) { self.childBuilder = childBuilder }
				    @Instantiated let childBuilder: SendableInstantiator<Child>
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(onTap: (() -> Void)? = {}) { self.onTap = onTap }
				    public let onTap: (() -> Void)?
				}
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

			        public private(set) var childBuilder: __safeDI_Child_MockConfiguration
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_childBuilder__childBuilder_onTap = safeDIOverrides.childBuilder.onTap
			        let __safeDI_childBuilder__safeDIBuilder = safeDIOverrides.childBuilder.safeDIBuilder
			        @Sendable func __safeDI_childBuilder() -> Child {
			            Child.__safeDI_init(onTap: __safeDI_childBuilder__childBuilder_onTap(), safeDIBuilder: __safeDI_childBuilder__safeDIBuilder)
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
			        onTap: @autoclosure @escaping @Sendable () -> (() -> Void)? = __safeDI_Child_mockDefault_onTap(),
			        _ safeDIBuilder: (@Sendable ((() -> Void)?) -> Child)? = nil
			    ) {
			        self.onTap = onTap
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// The default of `Child`'s `onTap` unless set.
			    public private(set) var onTap: @Sendable () -> (() -> Void)?
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: (@Sendable ((() -> Void)?) -> Child)?
			}

			extension Child {
			    nonisolated static func __safeDI_mockDefault_onTap() -> (() -> Void)? { {} }
			    static func __safeDI_init(onTap: (() -> Void)?, safeDIBuilder: (@Sendable ((() -> Void)?) -> Child)?) -> Child {
			        if let safeDIBuilder { safeDIBuilder(onTap) } else { Child(onTap: onTap) }
			    }
			}
			@usableFromInline nonisolated func __safeDI_Child_mockDefault_onTap() -> (() -> Void)? { Child.__safeDI_mockDefault_onTap() }
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOptionalMembersOfTypealiasedFunctionType_whenDefaultValuedParametersDeclaredEscapingAreInPublicMock() async throws {
		// A public mock takes a non-optional default as an optional, which escapes, so a default-valued parameter of a
		// typealiased function type declared `@escaping` needs no `@escaping` there, whether the mocked type declares
		// it or a type in its tree does. (SafeDI reads the `public typealias`, so `mock()` and the configuration's
		// initializer and fields that take one are `public`.) `MockCallSite.swift` passes a closure for each.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public typealias Handler = () -> Void
				""",
				"""
				@Instantiable(generateMock: .public)
				public struct Root: Instantiable {
				    public init(child: Child, onOpen: @escaping Handler = {}) {
				        self.child = child
				        self.onOpen = onOpen
				    }
				    @Instantiated let child: Child
				    public let onOpen: Handler
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(onTap: @escaping Handler = {}) { self.onTap = onTap }
				    public let onTap: Handler
				}
				""",
			],
			swiftFileContentByFilePath: [
				"MockCallSite.swift": """
				#if DEBUG
				func mockRoot() -> Root {
				    Root.mock(onOpen: {}, safeDIOverrides: .init(child: .init(onTap: {})))
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
			            child: __safeDI_Child_MockConfiguration = .init()
			        ) {
			            self.child = child
			        }

			        public private(set) var child: __safeDI_Child_MockConfiguration
			    }

			    public static func mock(
			        onOpen: Handler? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let onOpen = onOpen ?? ({})
			        func __safeDI_child() -> Child {
			            return Child.__safeDI_init(onTap: safeDIOverrides.child.onTap, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)
			        }
			        let child: Child = __safeDI_child()
			        return Root(child: child, onOpen: onOpen)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_C30DD4EB01E3CFC4 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Child` is constructed within the public mock trees of this module.
			public struct __safeDI_Child_MockConfiguration {
			    public init(
			        onTap: Handler? = nil,
			        _ safeDIBuilder: ((@escaping Handler) -> Child)? = nil
			    ) {
			        self.onTap = onTap
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Child`'s `onTap`.
			    public private(set) var onTap: Handler?
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    public private(set) var safeDIBuilder: ((@escaping Handler) -> Child)?
			}

			extension Child {
			    static func __safeDI_init(onTap: Handler?, safeDIBuilder: ((@escaping Handler) -> Child)?) -> Child {
			        let onTap = onTap ?? ({})
			        return if let safeDIBuilder { safeDIBuilder(onTap) } else { Child(onTap: onTap) }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesStandardTypedParameterOnPublicTier_whenOnlyPackageInitializerMentionsIt() async throws {
		// The allowlist proves `Result`, `Data` and `Error` `public`, so the required parameter is on the public tier
		// although only an `internal` initializer mentions its type.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				import Foundation

				@Instantiable(generateMock: .public)
				public struct Loader: Instantiable {
				    init(outcome: Result<Data, any Error>) {
				        self.outcome = outcome
				    }

				    @Received let outcome: Result<Data, any Error>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		let imports = """
		#if canImport(Foundation)
		import Foundation
		#endif
		"""
		#expect(output.generatedFiles == [
			"Loader+SafeDIMock.swift": generatedFileHeader + imports + """


			#if DEBUG
			extension Loader {
			    public static func mock(
			        outcome: Result<Data, any Error>
			    ) -> Loader {
			        return Loader(outcome: outcome)
			    }
			}

			extension Loader {
			    public enum __safeDI_Loader_mock_78C8E153D4A0F201 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + imports + "\n\n",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesInjectedFoundationAndDispatchTypesOnPublicTier_whenOnlyInternalInitializerMentionsThem() async throws {
		// O2: `URLSession`, `DispatchQueue`, `Clock` and `Duration` are standard types a project injects and nearly never
		// declares, so the allowlist proves them `public` although only an `internal` initializer mentions them.
		// Outside Apple platforms `URLSession` is declared in `FoundationNetworking`, which the fixture imports where it can,
		// as a project that builds for Linux does.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				import Foundation
				#if canImport(FoundationNetworking)
				import FoundationNetworking
				#endif

				@Instantiable(generateMock: .public)
				public final class Client: Instantiable {
				    init(session: URLSession, queue: DispatchQueue, clock: any Clock<Duration>) {
				        self.session = session
				        self.queue = queue
				        self.clock = clock
				    }

				    @Received let session: URLSession
				    @Received let queue: DispatchQueue
				    @Received let clock: any Clock<Duration>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		let imports = """
		#if canImport(Foundation)
		import Foundation
		#endif
		#if canImport(FoundationNetworking)
		import FoundationNetworking
		#endif
		"""
		#expect(output.generatedFiles == [
			"Client+SafeDIMock.swift": generatedFileHeader + imports + """


			#if DEBUG
			extension Client {
			    public static func mock(
			        clock: any Clock<Duration>,
			        queue: DispatchQueue,
			        session: URLSession
			    ) -> Client {
			        return Client(session: session, queue: queue, clock: clock)
			    }
			}

			extension Client {
			    public enum __safeDI_Client_mock_FB334AC978DC8CED {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + imports + "\n\n",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOwnOptionalDefaultsAsParametersWithIsolatedProviders_whenTypeIsBoundToGlobalActor() async throws {
		// M6.3b: `Dashboard` is bound to the main actor, so its `mock()` is, and its own optional default reads the actor's
		// state, as an internal mock's parameter default may. The default is a parameter of `mock()` whose provider shares
		// its isolation, never a field of the nonisolated `SafeDIOverrides` initializer, whose default could not call it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public struct Theme: Instantiable {
				    public init() {}
				}
				""",
				"""
				@MainActor
				@Instantiable(generateMock: .public)
				public struct Dashboard: Instantiable {
				    static var defaultLabel: String? = "label"

				    init(theme: Theme, label: String? = defaultLabel) {
				        self.theme = theme
				    }

				    @Instantiated let theme: Theme
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Dashboard+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Dashboard {
			    @usableFromInline @MainActor static func __safeDI_publicMockDefault_label() -> String? { defaultLabel }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            theme: (() -> Theme)? = nil
			        ) {
			            self.theme = theme
			        }

			        public private(set) var theme: (() -> Theme)?
			    }

			    public static func mock(
			        label: String? = Dashboard.__safeDI_publicMockDefault_label(),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Dashboard {
			        let theme = if let safeDIBuilder = safeDIOverrides.theme { safeDIBuilder() } else { Theme() }
			        return Dashboard(theme: theme, label: label)
			    }
			}

			extension Dashboard {
			    public enum __safeDI_Dashboard_mock_81EB86AE43991940 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_isolatesProviderOfOwnOptionalDefault_whenMockAttributesBindMockToGlobalActor() async throws {
		// M2.16b, M6.3b: `mockAttributes` binds the mock of `NoTree`, whose initializer is bound to the main actor, so the
		// provider of its default, which reads the actor's state, is bound to it too.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				enum Defaults {
				    static var name: String? = "name"
				}

				@Instantiable(mockAttributes: "@MainActor", generateMock: .public)
				public final class NoTree: Instantiable {
				    @MainActor init(name: String? = Defaults.name) {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"NoTree+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension NoTree {
			    @usableFromInline @MainActor static func __safeDI_publicMockDefault_name() -> String? { Defaults.name }

			    @MainActor public static func mock(
			        name: String? = NoTree.__safeDI_publicMockDefault_name()
			    ) -> NoTree {
			        return NoTree(name: name)
			    }
			}

			extension NoTree {
			    public enum __safeDI_NoTree_mock_9B791E5044AD415C {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	/// A `@MainActor` protocol and a `@MainActor` superclass, which isolate the types that conform to or inherit from
	/// them where SafeDI cannot see it, and a type of the tree.
	private static let inferredIsolationDeclarations = """
	@MainActor
	public protocol Screenish {}

	@MainActor
	open class BaseController {
	    public init() {}
	}

	@Instantiable
	public struct Theme: Instantiable {
	    public init() {}
	}
	"""

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_commentsOnNonisolatedProviders_whenTypeIsIsolatedByConformanceSafeDICannotSee() async throws {
		// D530-3, decision 53: `ProfileView` is isolated by its conformance to `Screenish`, which SafeDI cannot see, so the
		// provider of its own optional default is `nonisolated`, as the field of `SafeDIOverrides` that calls it is, and a
		// comment above it names the opt-in for a default that reads the actor's state. A literal default compiles.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.inferredIsolationDeclarations,
				"""
				@Instantiable(generateMock: .public)
				public struct ProfileView: Instantiable, Screenish {
				    init(theme: Theme, label: String? = "label") {
				        self.theme = theme
				    }

				    @Instantiated let theme: Theme
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"ProfileView+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension ProfileView {
			    // These providers evaluate `ProfileView`'s own defaults outside any actor, since SafeDI sees no isolation on it. If one
			    // reads the state of an actor `ProfileView` takes from a conformance or a superclass and does not compile, give its
			    // `@Instantiable` `mockAttributes: "@MainActor"` (or that actor).
			    @usableFromInline nonisolated static func __safeDI_publicMockDefault_label() -> String? { "label" }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            theme: (() -> Theme)? = nil,
			            label: String? = ProfileView.__safeDI_publicMockDefault_label()
			        ) {
			            self.theme = theme
			            self.label = label
			        }

			        public private(set) var theme: (() -> Theme)?
			        /// The default of `ProfileView`'s `label` unless set; `.init(label: nil)` passes `nil`.
			        public private(set) var label: String?
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> ProfileView {
			        let theme = if let safeDIBuilder = safeDIOverrides.theme { safeDIBuilder() } else { Theme() }
			        return ProfileView(theme: theme, label: safeDIOverrides.label)
			    }
			}

			extension ProfileView {
			    public enum __safeDI_ProfileView_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_isolatesProvidersOfOwnDefaults_whenTypeIsolatedByConformanceOrSuperclassSpellsMockAttributes() async throws {
		// D530-3, decision 53: the opt-in the comment names. `ProfileView` (isolated by conformance) and `ProfileController`
		// (by inheritance) each read isolated state in their own optional default and spell `mockAttributes: "@MainActor"`,
		// so each default is a parameter of the isolated `mock()` whose provider shares its isolation.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.inferredIsolationDeclarations,
				"""
				@Instantiable(mockAttributes: "@MainActor", generateMock: .public)
				public struct ProfileView: Instantiable, Screenish {
				    static var defaultLabel: String? = "label"

				    init(theme: Theme, label: String? = defaultLabel) {
				        self.theme = theme
				    }

				    @Instantiated let theme: Theme
				}
				""",
				"""
				@Instantiable(mockAttributes: "@MainActor", generateMock: .public)
				public final class ProfileController: BaseController, Instantiable {
				    static var defaultLabel: String? = "label"

				    init(theme: Theme, label: String? = defaultLabel) {
				        self.theme = theme
				    }

				    @Instantiated let theme: Theme
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"ProfileController+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension ProfileController {
			    @usableFromInline @MainActor static func __safeDI_publicMockDefault_label() -> String? { defaultLabel }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            theme: (() -> Theme)? = nil
			        ) {
			            self.theme = theme
			        }

			        public private(set) var theme: (() -> Theme)?
			    }

			    @MainActor public static func mock(
			        label: String? = ProfileController.__safeDI_publicMockDefault_label(),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> ProfileController {
			        let theme = if let safeDIBuilder = safeDIOverrides.theme { safeDIBuilder() } else { Theme() }
			        return ProfileController(theme: theme, label: label)
			    }
			}

			extension ProfileController {
			    public enum __safeDI_ProfileController_mock_81EB86AE43991940 {}
			}
			#endif
			""",
			"ProfileView+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension ProfileView {
			    @usableFromInline @MainActor static func __safeDI_publicMockDefault_label() -> String? { defaultLabel }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            theme: (() -> Theme)? = nil
			        ) {
			            self.theme = theme
			        }

			        public private(set) var theme: (() -> Theme)?
			    }

			    @MainActor public static func mock(
			        label: String? = ProfileView.__safeDI_publicMockDefault_label(),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> ProfileView {
			        let theme = if let safeDIBuilder = safeDIOverrides.theme { safeDIBuilder() } else { Theme() }
			        return ProfileView(theme: theme, label: label)
			    }
			}

			extension ProfileView {
			    public enum __safeDI_ProfileView_mock_81EB86AE43991940 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsEveryParameterKindInEachSpelling_whenPublicMockedTypeTakesSpellingAxisFixture() async throws {
		// M15.11, R15's primary cell: closures, `@Sendable` closures, an optional closure, a tuple, an array, an existential,
		// a nested type, a closure typealias, another module's type and a plain public type, as forwarded, received,
		// only-if-available and default-valued parameters, override members and configuration fields. Another package
		// calls both tiers it can reach. `Base`'s `BaseTheme` is `public`, which `Base`'s `.safedi` does not record, so the
		// comment names it; the `package` typealias `Handler` keeps `handler` off the `public` tier.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Base", packageName: "pkg", swiftFileContentByFilePath: ["Analytics.swift": """
				import SafeDI

				@Instantiable
				public final class Analytics: Instantiable, Sendable {
				    public init() {}
				}

				/// A plain public type of another module, not `@Instantiable`.
				public struct BaseTheme: Sendable {
				    public init() {}
				}
				"""]),
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: [
					"Badge.swift": """
					import Base
					import SafeDI

					/// A public receiver outside the mocked tree whose public initializer mentions the types only package
					/// initializers would otherwise mention, so they are proven public.
					@Instantiable
					public struct Badge: Instantiable {
					    public init(auth: any Auth, theme: Theme, baseTheme: BaseTheme) {
					        self.auth = auth
					        self.theme = theme
					        self.baseTheme = baseTheme
					    }

					    @Received let auth: any Auth
					    @Received let theme: Theme
					    @Received let baseTheme: BaseTheme
					}
					""",
					"Leaf.swift": """
					import Base
					import SafeDI

					@Instantiable
					public struct Leaf: Instantiable {
					    package init(
					        onTap: @escaping () -> Void,
					        sendableTap: @escaping @Sendable () -> Void,
					        pair: (Int, Bool),
					        theme: Theme,
					        baseTheme: BaseTheme,
					        auth: any Auth,
					        inner: Outer.Inner,
					        analytics: Analytics,
					        sessionBuilder: Instantiator<Session>,
					        onDismiss: (() -> Void)?,
					        handler: Handler?,
					        optionalAuth: (any Auth)?,
					        capacity: Int = 10,
					        onDone: @escaping () -> Void = {},
					        names: [String] = [],
					        label: String? = "leaf"
					    ) {
					        self.onTap = onTap
					        self.sendableTap = sendableTap
					        self.pair = pair
					        self.theme = theme
					        self.baseTheme = baseTheme
					        self.auth = auth
					        self.inner = inner
					        self.analytics = analytics
					        self.sessionBuilder = sessionBuilder
					        self.onDismiss = onDismiss
					        self.handler = handler
					        self.optionalAuth = optionalAuth
					    }

					    @Received let onTap: () -> Void
					    @Received let sendableTap: @Sendable () -> Void
					    @Received let pair: (Int, Bool)
					    @Received let theme: Theme
					    @Received let baseTheme: BaseTheme
					    @Received let auth: any Auth
					    @Received let inner: Outer.Inner
					    @Received let analytics: Analytics
					    @Received let sessionBuilder: Instantiator<Session>
					    @Received(onlyIfAvailable: true) let onDismiss: (() -> Void)?
					    @Received(onlyIfAvailable: true) let handler: Handler?
					    @Received(onlyIfAvailable: true) let optionalAuth: (any Auth)?
					}
					""",
					"Service.swift": """
					import Base
					import SafeDI

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    package init(
					        onSelect: @escaping (String) -> Void,
					        sendableSelect: @escaping @Sendable () -> Void,
					        size: (Int, Int),
					        tags: [String],
					        inner2: Outer.Inner,
					        leaf: Leaf,
					        retries: Int = 3,
					        onFinish: @escaping () -> Void = {},
					        title: String? = "service",
					        onCancel: (() -> Void)? = nil
					    ) {
					        self.onSelect = onSelect
					        self.sendableSelect = sendableSelect
					        self.size = size
					        self.tags = tags
					        self.inner2 = inner2
					        self.leaf = leaf
					    }

					    @Forwarded let onSelect: (String) -> Void
					    @Forwarded let sendableSelect: @Sendable () -> Void
					    @Forwarded let size: (Int, Int)
					    @Forwarded let tags: [String]
					    @Forwarded let inner2: Outer.Inner
					    @Instantiated let leaf: Leaf
					}
					""",
					"Types.swift": """
					import Base
					import SafeDI

					public protocol Auth {}

					@Instantiable(fulfillingAdditionalTypes: [Auth.self])
					public struct DefaultAuth: Auth, Instantiable {
					    public init() {}
					}

					package typealias Handler = (String) -> Bool

					public enum Outer {
					    @Instantiable
					    public struct Inner: Instantiable {
					        public init() {}
					    }
					}

					@Instantiable
					public struct Session: Instantiable {
					    public init() {}
					}

					/// A plain public type, not `@Instantiable`.
					public struct Theme {
					    public init() {}
					}
					""",
				], dependencies: ["Base"]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["AppCaller.swift": """
				import Base
				import Core
				import SafeDI

				#if DEBUG
				func callPublicTier() {
				    _ = Service.mock(inner2: Outer.Inner(), onSelect: { _ in }, sendableSelect: {}, size: (1, 2), tags: [], baseTheme: BaseTheme(), onTap: {}, pair: (1, true), sendableTap: {}, theme: Theme())
				    _ = Service.mock(
				        inner2: Outer.Inner(), onSelect: { _ in }, sendableSelect: {}, size: (1, 2), tags: ["a"],
				        retries: 9, onFinish: {}, baseTheme: BaseTheme(), onTap: {}, pair: (1, true), sendableTap: {}, theme: Theme(),
				        analytics: Analytics(), auth: DefaultAuth(), inner: Outer.Inner(), onDismiss: {}, optionalAuth: DefaultAuth(),
				        sessionBuilder: Instantiator<Session> { Session() },
				        safeDIOverrides: .init(auth: { DefaultAuth() }, leaf: .init(capacity: 3, onDone: {}, names: ["n"], label: nil), title: nil, onCancel: {})
				    )
				}
				#endif
				"""], dependencies: ["Base", "Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(Base)
		import Base
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Service {
		    // These providers evaluate `Service`'s own defaults outside any actor, since SafeDI sees no isolation on it. If one
		    // reads the state of an actor `Service` takes from a conformance or a superclass and does not compile, give its
		    // `@Instantiable` `mockAttributes: "@MainActor"` (or that actor).
		    @usableFromInline nonisolated static func __safeDI_publicMockDefault_title() -> String? { "service" }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            auth: (() -> Auth)? = nil,
		            inner: (() -> Outer.Inner)? = nil,
		            analytics: (() -> Analytics)? = nil,
		            sessionBuilder: (() -> Session)? = nil,
		            leaf: __safeDI_Core_Leaf_MockConfiguration = .init(),
		            title: String? = Service.__safeDI_publicMockDefault_title(),
		            onCancel: (() -> Void)? = nil
		        ) {
		            self.auth = auth
		            self.inner = inner
		            self.analytics = analytics
		            self.sessionBuilder = sessionBuilder
		            self.leaf = leaf
		            self.title = title
		            self.onCancel = onCancel
		        }

		        public private(set) var auth: (() -> Auth)?
		        public private(set) var inner: (() -> Outer.Inner)?
		        public private(set) var analytics: (() -> Analytics)?
		        public private(set) var sessionBuilder: (() -> Session)?
		        public private(set) var leaf: __safeDI_Core_Leaf_MockConfiguration
		        /// The default of `Service`'s `title` unless set; `.init(title: nil)` passes `nil`.
		        public private(set) var title: String?
		        /// The value of `Service`'s `onCancel`, `nil` unless set.
		        public private(set) var onCancel: (() -> Void)?
		    }

		    // SafeDI counts `BaseTheme` as `public`: no module it reads declares it narrower. If `BaseTheme` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
		    public static func mock(
		        inner2: Outer.Inner,
		        onSelect: @escaping (String) -> Void,
		        sendableSelect: @escaping @Sendable () -> Void,
		        size: (Int, Int),
		        tags: [String],
		        retries: Int? = nil,
		        onFinish: (() -> Void)? = nil,
		        baseTheme: BaseTheme,
		        onTap: @escaping () -> Void,
		        pair: (Int, Bool),
		        sendableTap: @escaping @Sendable () -> Void,
		        theme: Theme,
		        analytics: Analytics? = nil,
		        auth: (any Auth)? = nil,
		        inner: Outer.Inner? = nil,
		        onDismiss: (() -> Void)? = nil,
		        optionalAuth: (any Auth)? = nil,
		        sessionBuilder: Instantiator<Session>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        Service.mock(inner2: inner2, onSelect: onSelect, sendableSelect: sendableSelect, size: size, tags: tags, retries: retries, onFinish: onFinish, baseTheme: baseTheme, onTap: onTap, pair: pair, sendableTap: sendableTap, theme: theme, analytics: analytics, auth: auth, handler: nil, inner: inner, onDismiss: onDismiss, optionalAuth: optionalAuth, sessionBuilder: sessionBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    package static func mock(
		        inner2: Outer.Inner,
		        onSelect: @escaping (String) -> Void,
		        sendableSelect: @escaping @Sendable () -> Void,
		        size: (Int, Int),
		        tags: [String],
		        retries: Int? = nil,
		        onFinish: (() -> Void)? = nil,
		        baseTheme: BaseTheme,
		        onTap: @escaping () -> Void,
		        pair: (Int, Bool),
		        sendableTap: @escaping @Sendable () -> Void,
		        theme: Theme,
		        analytics: Analytics? = nil,
		        auth: (any Auth)? = nil,
		        handler: Handler? = nil,
		        inner: Outer.Inner? = nil,
		        onDismiss: (() -> Void)? = nil,
		        optionalAuth: (any Auth)? = nil,
		        sessionBuilder: Instantiator<Session>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        let retries = retries ?? (3)
		        let onFinish = onFinish ?? ({})
		        let auth: Auth = if let auth { auth } else if let safeDIBuilder = safeDIOverrides.auth { safeDIBuilder() } else { DefaultAuth() }
		        let inner = if let inner { inner } else if let safeDIBuilder = safeDIOverrides.inner { safeDIBuilder() } else { Outer.Inner() }
		        let analytics = if let analytics { analytics } else if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_sessionBuilder() -> Session {
		            if let safeDIBuilder = safeDIOverrides.sessionBuilder { safeDIBuilder() } else { Session() }
		        }
		        let sessionBuilder = if let sessionBuilder { sessionBuilder } else { Instantiator<Session>(__safeDI_sessionBuilder) }
		        func __safeDI_leaf() -> Leaf {
		            return Leaf.__safeDI_init(onTap: onTap, sendableTap: sendableTap, pair: pair, theme: theme, baseTheme: baseTheme, auth: auth, inner: inner, analytics: analytics, sessionBuilder: sessionBuilder, onDismiss: onDismiss, handler: handler, optionalAuth: optionalAuth, capacity: safeDIOverrides.leaf.capacity, onDone: safeDIOverrides.leaf.onDone, names: safeDIOverrides.leaf.names, label: safeDIOverrides.leaf.label, safeDIBuilder: safeDIOverrides.leaf.safeDIBuilder)
		        }
		        let leaf: Leaf = __safeDI_leaf()
		        return Service(onSelect: onSelect, sendableSelect: sendableSelect, size: size, tags: tags, inner2: inner2, leaf: leaf, retries: retries, onFinish: onFinish, title: safeDIOverrides.title, onCancel: safeDIOverrides.onCancel)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_mock_191982787DB3160A {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Leaf` is constructed within the public mock trees of module `Core`.
		public struct __safeDI_Core_Leaf_MockConfiguration {
		    public init(
		        capacity: Int? = nil,
		        onDone: (() -> Void)? = nil,
		        names: [String]? = nil,
		        label: String? = __safeDI_Core_Leaf_mockDefault_label()
		    ) {
		        self.capacity = capacity
		        self.onDone = onDone
		        self.names = names
		        self.label = label
		        self.safeDIBuilder = nil
		    }

		    package init(
		        capacity: Int? = nil,
		        onDone: (() -> Void)? = nil,
		        names: [String]? = nil,
		        label: String? = __safeDI_Core_Leaf_mockDefault_label(),
		        _ safeDIBuilder: ((@escaping () -> Void, @escaping @Sendable () -> Void, (Int, Bool), Theme, BaseTheme, any Auth, Outer.Inner, Analytics, Instantiator<Session>, (() -> Void)?, Handler?, (any Auth)?, Int, @escaping () -> Void, [String], String?) -> Leaf)? = nil
		    ) {
		        self.capacity = capacity
		        self.onDone = onDone
		        self.names = names
		        self.label = label
		        self.safeDIBuilder = safeDIBuilder
		    }

		    /// `nil` keeps the default of `Leaf`'s `capacity`.
		    public private(set) var capacity: Int?
		    /// `nil` keeps the default of `Leaf`'s `onDone`.
		    public private(set) var onDone: (() -> Void)?
		    /// `nil` keeps the default of `Leaf`'s `names`.
		    public private(set) var names: [String]?
		    /// The default of `Leaf`'s `label` unless set.
		    public private(set) var label: String?
		    /// Overrides how `Leaf` is constructed. Parameters match the type’s initializer or custom mock method.
		    package private(set) var safeDIBuilder: ((@escaping () -> Void, @escaping @Sendable () -> Void, (Int, Bool), Theme, BaseTheme, any Auth, Outer.Inner, Analytics, Instantiator<Session>, (() -> Void)?, Handler?, (any Auth)?, Int, @escaping () -> Void, [String], String?) -> Leaf)?
		}

		extension Leaf {
		    nonisolated static func __safeDI_mockDefault_label() -> String? { "leaf" }
		    static func __safeDI_init(onTap: @escaping () -> Void, sendableTap: @escaping @Sendable () -> Void, pair: (Int, Bool), theme: Theme, baseTheme: BaseTheme, auth: any Auth, inner: Outer.Inner, analytics: Analytics, sessionBuilder: Instantiator<Session>, onDismiss: (() -> Void)?, handler: Handler?, optionalAuth: (any Auth)?, capacity: Int?, onDone: (() -> Void)?, names: [String]?, label: String?, safeDIBuilder: ((@escaping () -> Void, @escaping @Sendable () -> Void, (Int, Bool), Theme, BaseTheme, any Auth, Outer.Inner, Analytics, Instantiator<Session>, (() -> Void)?, Handler?, (any Auth)?, Int, @escaping () -> Void, [String], String?) -> Leaf)?) -> Leaf {
		        let capacity = capacity ?? (10)
		        let onDone = onDone ?? ({})
		        let names = names ?? ([])
		        return if let safeDIBuilder { safeDIBuilder(onTap, sendableTap, pair, theme, baseTheme, auth, inner, analytics, sessionBuilder, onDismiss, handler, optionalAuth, capacity, onDone, names, label) } else { Leaf(onTap: onTap, sendableTap: sendableTap, pair: pair, theme: theme, baseTheme: baseTheme, auth: auth, inner: inner, analytics: analytics, sessionBuilder: sessionBuilder, onDismiss: onDismiss, handler: handler, optionalAuth: optionalAuth, capacity: capacity, onDone: onDone, names: names, label: label) }
		    }
		}
		@usableFromInline nonisolated func __safeDI_Core_Leaf_mockDefault_label() -> String? { Leaf.__safeDI_mockDefault_label() }
		#endif
		""" + "\n"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesOwnDefaultsProvider_whenWiderTierOmitsIsolatedMocksOwnDefaultOfNarrowerType() async throws {
		// M6.3b, found by the public mock corpus (seed 188): `label`, of the internal `Label`, is on the internal tier
		// only, so the public tier omits it and passes the provider's value, the declaration's default, never `nil`.
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Dashboard.swift": """
			import SafeDI

			struct Label {
			    init() {}
			}

			@Instantiable
			public struct Theme: Instantiable {
			    public init() {}
			}

			@MainActor
			@Instantiable(generateMock: .public)
			public struct Dashboard: Instantiable {
			    static var defaultLabel: Label? = Label()

			    init(theme: Theme, label: Label? = defaultLabel) {
			        self.theme = theme
			        self.label = label
			    }

			    @Instantiated let theme: Theme
			    let label: Label?
			}
			"""]),
			// Another package calls the public tier, which `Core`'s own code, seeing both tiers, would not.
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Probe.swift": """
			import Core

			#if DEBUG
			@MainActor func mockDashboard() -> Dashboard {
			    Dashboard.mock()
			}
			#endif
			"""], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Dashboard {
		    @MainActor static func __safeDI_publicMockDefault_label() -> Label? { defaultLabel }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            theme: (() -> Theme)? = nil
		        ) {
		            self.theme = theme
		        }

		        public private(set) var theme: (() -> Theme)?
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Dashboard {
		        Dashboard.mock(label: Dashboard.__safeDI_publicMockDefault_label(), safeDIOverrides: safeDIOverrides)
		    }

		    static func mock(
		        label: Label? = Dashboard.__safeDI_publicMockDefault_label(),
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Dashboard {
		        let theme = if let safeDIBuilder = safeDIOverrides.theme { safeDIBuilder() } else { Theme() }
		        return Dashboard(theme: theme, label: label)
		    }
		}

		extension Dashboard {
		    public enum __safeDI_Dashboard_mock_0D31A45F0EAEE567 {}
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("mockDashboard()")])
	}

	// MARK: Tests – builder closures for holes

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderForHole_whenPublicMockedTreeInstantiatesTypeNoDeclarationFulfills() async throws {
		// M7.1, M2.12: no declaration fulfills `UserService`, so the public mock takes a builder for it, required, handed
		// the values in scope at the site; a public initializer elsewhere proves `UserService` `public`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public final class UserService {
				    public init() {}
				}

				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: UserService) {
				        self.userService = userService
				    }

				    @Received let userService: UserService
				}

				@Instantiable
				public final class Analytics: Instantiable {
				    public init() {}
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    init(analytics: Analytics, userService: UserService) {
				        self.analytics = analytics
				        self.userService = userService
				    }

				    @Received let analytics: Analytics
				    @Instantiated let userService: UserService
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Profile+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @frozen public enum SafeDIMockScope_UserService {
			        case userService(userService_Values)

			        public struct userService_Values {
			            public let analytics: Analytics
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            analytics: (() -> Analytics)? = nil
			        ) {
			            self.analytics = analytics
			        }

			        public private(set) var analytics: (() -> Analytics)?
			    }

			    public static func mock(
			        userServiceBuilder: @escaping (Service.SafeDIMockScope_UserService) -> UserService,
			        analytics: Analytics? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let __safeDI_userServiceBuilder = userServiceBuilder
			        let analytics = if let analytics { analytics } else if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
			        let userService: UserService = __safeDI_userServiceBuilder(.userService(SafeDIMockScope_UserService.userService_Values(analytics: analytics)))
			        return Service(analytics: analytics, userService: userService)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_16DCC0AFD73D3D7A {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenHoleTypeOnlyPackageInitializerMentions() async {
		// M2.12b, M7.1b: `UserService` is `package`, so its builder is `package`, and the public tier cannot take it.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):5:29: error: SafeDI cannot generate the public mock of `Service`: its `public` tier, which `generateMock: .public` requires, cannot take `userServiceBuilder`, whose case `userService` builds `UserService` for the hole `userService`, and cannot pass `nil` for it, since it is required. `UserService` is declared `package`. Declare `UserService` `public`; declare in this module, or a module it depends on, a `mockOnly` `@Instantiable` type that fulfills `UserService` (`@Instantiable(fulfillingAdditionalTypes: [UserService.self], mockOnly: true)`), which the mock builds instead of taking `userServiceBuilder`, leaving production's hole as it is; or use `generateMock: .internal`.
			\(fixtures["Service.swift"]):1:1: note: `UserService` is declared `package` here.
			\(fixtures["Service.swift"]):1:1-1:8: fixit: public
			\(fixtures["Service.swift"]):11:5: note: `Service` instantiates `userService: UserService` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					package final class UserService {
					    package init() {}
					}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    package init(userService: UserService) {
					        self.userService = userService
					    }

					    @Instantiated let userService: UserService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingStagedBuilder_whenPackageHoleTypeIsBuiltInsideSendableWrapper() async {
		// As the previous test, with the hole held in a `Sendable` wrapper: its place is staged, so it has a builder of its
		// own, which no case of an enum names.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):5:29: error: SafeDI cannot generate the public mock of `Service`: its `public` tier, which `generateMock: .public` requires, cannot take `userServiceBuilder_userService`, which builds `UserService` for the hole `userService`, and cannot pass `nil` for it, since it is required. `UserService` is declared `package`. Declare `UserService` `public`; declare in this module, or a module it depends on, a `mockOnly` `@Instantiable` type that fulfills `UserService` (`@Instantiable(fulfillingAdditionalTypes: [UserService.self], mockOnly: true)`), which the mock builds instead of taking `userServiceBuilder_userService`, leaving production's hole as it is; or use `generateMock: .internal`.
			\(fixtures["Service.swift"]):1:1: note: `UserService` is declared `package` here.
			\(fixtures["Service.swift"]):1:1-1:8: fixit: public
			\(fixtures["Service.swift"]):11:5: note: `Service` instantiates `userService: SendableLazilyInstantiated<UserService>` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					package final class UserService: Sendable {
					    package init() {}
					}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    package init(userService: SendableLazilyInstantiated<UserService>) {
					        self.userService = userService
					    }

					    @Instantiated let userService: SendableLazilyInstantiated<UserService>
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsMockOnlyStubInPlaceOfTakingBuilder_whenDeclaringModuleDeclaresStubThatFulfillsHole() async throws {
		// BZ-6: the remedy the error above names. A `mockOnly` stub in `Core` fulfills the hole's type, so `Service`'s
		// mock builds the stub and takes no builder, while production still has the hole; another package calls it.
		// `UserService` is `package`, as the error above declares it: a `public` one would let the public tier take the
		// builder with no stub. The override for the stub is therefore `package`, beside a `public init()`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
					"""
					package protocol UserService {}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    package init(userService: any UserService) {
					        self.userService = userService
					    }

					    @Instantiated let userService: any UserService
					}
					""",
					"""
					#if DEBUG
					@Instantiable(fulfillingAdditionalTypes: [UserService.self], mockOnly: true)
					public final class PreviewUserService: UserService {
					    public static func mock() -> PreviewUserService {
					        PreviewUserService()
					    }
					}
					#endif
					""",
				]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
					"""
					import Core

					#if DEBUG
					func preview() {
					    _ = Service.mock()
					}
					#endif
					""",
				], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if DEBUG
		extension Service {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init() {
		            self.userService = nil
		        }

		        package init(
		            userService: (() -> UserService)? = nil
		        ) {
		            self.userService = userService
		        }

		        package private(set) var userService: (() -> UserService)?
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        let userService: UserService = if let safeDIBuilder = safeDIOverrides.userService { safeDIBuilder() } else { PreviewUserService.mock() }
		        return Service(userService: userService)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_mock_51799E6AA5E7B634 {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresEachScopeFieldWithItsOwnAccess_whenHoleScopeHoldsNarrowerTypes() async throws {
		// M2.13, M7.8: the builder is public, as `UserService`'s proof allows, and its scope struct stays public with a
		// `package` field for `Session` and an internal one for `Token`; another package passes a builder that reads the
		// one field it can see.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
					"""
					public final class UserService {
					    public init(analytics: Analytics) {}
					}

					@Instantiable
					public struct Profile: Instantiable {
					    public init(userService: UserService) {
					        self.userService = userService
					    }

					    @Received let userService: UserService
					}

					@Instantiable
					public final class Analytics: Instantiable {
					    public init() {}
					}

					@Instantiable
					package final class Session: Instantiable {
					    package init() {}
					}

					@Instantiable
					final class Token: Instantiable {
					    init() {}
					}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    init(analytics: Analytics, session: Session, token: Token, userService: UserService) {
					        self.analytics = analytics
					        self.session = session
					        self.token = token
					        self.userService = userService
					    }

					    @Received let analytics: Analytics
					    @Instantiated let session: Session
					    @Instantiated let token: Token
					    @Instantiated let userService: UserService
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Caller.swift": "import Core\n\n#if DEBUG\nfunc call() {\n    _ = Service.mock(userServiceBuilder: { scope in\n        switch scope {\n        case let .userService(values): UserService(analytics: values.analytics)\n        }\n    })\n}\n#endif\n"], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles["Core.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Service {
		    @frozen public enum SafeDIMockScope_UserService {
		        case userService(userService_Values)

		        public struct userService_Values {
		            package let session: Session
		            internal let token: Token
		            public let analytics: Analytics
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil
		        ) {
		            self.session = nil
		            self.token = nil
		            self.analytics = analytics
		        }

		        package init(
		            session: (() -> Session)? = nil,
		            analytics: (() -> Analytics)? = nil
		        ) {
		            self.session = session
		            self.token = nil
		            self.analytics = analytics
		        }

		        init(
		            session: (() -> Session)? = nil,
		            token: (() -> Token)? = nil,
		            analytics: (() -> Analytics)? = nil
		        ) {
		            self.session = session
		            self.token = token
		            self.analytics = analytics
		        }

		        package private(set) var session: (() -> Session)?
		        private(set) var token: (() -> Token)?
		        public private(set) var analytics: (() -> Analytics)?
		    }

		    public static func mock(
		        userServiceBuilder: @escaping (Service.SafeDIMockScope_UserService) -> UserService,
		        analytics: Analytics? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        let __safeDI_userServiceBuilder = userServiceBuilder
		        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        let analytics = if let analytics { analytics } else if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        let userService: UserService = __safeDI_userServiceBuilder(.userService(SafeDIMockScope_UserService.userService_Values(session: session, token: token, analytics: analytics)))
		        return Service(analytics: analytics, session: session, token: token, userService: userService)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_mock_FAC6AE1D89FB0EB5 {}
		}
		#endif
		""")
	}

	@Test(arguments: ["any Gadget", "Gadget"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_hashesStagedBuilderWithoutAny_whenHolesTypeIsSpelledWithOrWithoutAny(gadget: String) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol Gadget: Sendable {}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable, @unchecked Sendable {
				    public init(held: SendableLazilyInstantiated<\(gadget)>) {
				        self.held = held
				    }

				    @Instantiated let held: SendableLazilyInstantiated<\(gadget)>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    public enum SafeDIStagedMockScope_Gadget_held {
			        public struct Stage1 {}

			        public struct Stage2 {}
			    }

			    public static func mock(
			        gadgetBuilder_held: @escaping (Service.SafeDIStagedMockScope_Gadget_held.Stage1) -> @Sendable (Service.SafeDIStagedMockScope_Gadget_held.Stage2) -> \(gadget)
			    ) -> Service {
			        let __safeDI_gadgetBuilder_held = gadgetBuilder_held
			        let __safeDI_gadgetBuilder_held_Stage2 = __safeDI_gadgetBuilder_held(SafeDIStagedMockScope_Gadget_held.Stage1())
			        @Sendable func __safeDI_held() -> \(gadget) {
			            __safeDI_gadgetBuilder_held_Stage2(SafeDIStagedMockScope_Gadget_held.Stage2())
			        }
			        let held = SendableLazilyInstantiated<\(gadget)>(__safeDI_held)
			        return Service(held: held)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_617043EAB90EFCB2 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderReturningPlainValue_whenHoleIsDeclaredAsInstantiator() async throws {
		// M7.7, M15.13: the builder returns `UserService`, the mock building the `Instantiator`, on the public tier, since the
		// wrapper is allow-listed and a public initializer proves `UserService` `public`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public final class UserService: Instantiable {
				    public init() {}
				}

				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: UserService) {
				        self.userService = userService
				    }

				    @Received let userService: UserService
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    init(userServiceBuilder: Instantiator<UserService>) {
				        self.userServiceBuilder = userServiceBuilder
				    }

				    @Instantiated let userServiceBuilder: Instantiator<UserService>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Profile+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @frozen public enum SafeDIMockScope_UserService {
			        case userServiceBuilder(userServiceBuilder_Values, UserService.ForwardedProperties)

			        public struct userServiceBuilder_Values {}
			    }

			    public static func mock(
			        userServiceBuilder: @escaping (Service.SafeDIMockScope_UserService) -> UserService
			    ) -> Service {
			        let __safeDI_userServiceBuilder = userServiceBuilder
			        let userServiceBuilder = Instantiator<UserService> {
			            __safeDI_userServiceBuilder(.userServiceBuilder(SafeDIMockScope_UserService.userServiceBuilder_Values(), $0))
			        }
			        return Service(userServiceBuilder: userServiceBuilder)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_F20FD01548BEFA27 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsEscapingBuilderFromWrappersBuilderFunction_whenHoleIsBeneathInstantiatorOrLazilyInstantiated() async throws {
		// M7.9: each site sits in the builder function of an `Instantiator` or a `LazilyInstantiated`, which captures the
		// builder, so the builder is `@escaping`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public final class UserService {
				    public init() {}
				}

				public final class Clock {
				    public init() {}
				}

				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: UserService) {
				        self.userService = userService
				    }

				    @Instantiated let userService: UserService
				}

				@Instantiable
				public struct Settings: Instantiable {
				    public init(clock: Clock) {
				        self.clock = clock
				    }

				    @Instantiated let clock: Clock
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    init(profileBuilder: Instantiator<Profile>, settings: LazilyInstantiated<Settings>) {
				        self.profileBuilder = profileBuilder
				        self.settings = settings
				    }

				    @Instantiated let profileBuilder: Instantiator<Profile>
				    @Instantiated let settings: LazilyInstantiated<Settings>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Profile+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @frozen public enum SafeDIMockScope_Clock {
			        case settings_clock(settings_clock_Values)

			        public struct settings_clock_Values {
			            public let profileBuilder: Instantiator<Profile>
			        }
			    }

			    @frozen public enum SafeDIMockScope_UserService {
			        case profileBuilder_userService(profileBuilder_userService_Values)

			        public struct profileBuilder_userService_Values {}
			    }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            profileBuilder: ((UserService) -> Profile)? = nil,
			            settings: ((Clock) -> Settings)? = nil
			        ) {
			            self.profileBuilder = profileBuilder
			            self.settings = settings
			        }

			        public private(set) var profileBuilder: ((UserService) -> Profile)?
			        public private(set) var settings: ((Clock) -> Settings)?
			    }

			    public static func mock(
			        clockBuilder: @escaping (Service.SafeDIMockScope_Clock) -> Clock,
			        userServiceBuilder: @escaping (Service.SafeDIMockScope_UserService) -> UserService,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let __safeDI_clockBuilder = clockBuilder
			        let __safeDI_userServiceBuilder = userServiceBuilder
			        func __safeDI_profileBuilder() -> Profile {
			            let userService: UserService = __safeDI_userServiceBuilder(.profileBuilder_userService(SafeDIMockScope_UserService.profileBuilder_userService_Values()))
			            return if let safeDIBuilder = safeDIOverrides.profileBuilder { safeDIBuilder(userService) } else { Profile(userService: userService) }
			        }
			        let profileBuilder = Instantiator<Profile>(__safeDI_profileBuilder)
			        func __safeDI_settings() -> Settings {
			            let clock: Clock = __safeDI_clockBuilder(.settings_clock(SafeDIMockScope_Clock.settings_clock_Values(profileBuilder: profileBuilder)))
			            return if let safeDIBuilder = safeDIOverrides.settings { safeDIBuilder(clock) } else { Settings(clock: clock) }
			        }
			        let settings = LazilyInstantiated<Settings>(__safeDI_settings)
			        return Service(profileBuilder: profileBuilder, settings: settings)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_5EE08C11C7F928F1 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderReturningDeclaredSpelling_whenHoleIsExistentialOrClosureTypealias() async throws {
		// M15.13: a builder returns the hole's declared type as spelled, `any UserService` and the typealias `Scores`, each
		// proven `public` by a public initializer that mentions it. (A closure typealias cannot be a dependency: Swift stores
		// only an `@escaping` parameter, and the macro matches `@escaping Handler` to no property.)
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol UserService {}

				public typealias Scores = [String: Int]

				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: any UserService, scores: Scores) {
				        self.userService = userService
				        self.scores = scores
				    }

				    @Received let userService: any UserService
				    @Received let scores: Scores
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    init(userService: any UserService, scores: Scores) {
				        self.userService = userService
				        self.scores = scores
				    }

				    @Instantiated let userService: any UserService
				    @Instantiated let scores: Scores
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Profile+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @frozen public enum SafeDIMockScope_Scores {
			        case scores(scores_Values)

			        public struct scores_Values {
			            public let userService: any UserService
			        }
			    }

			    @frozen public enum SafeDIMockScope_UserService {
			        case userService(userService_Values)

			        public struct userService_Values {}
			    }

			    public static func mock(
			        scoresBuilder: @escaping (Service.SafeDIMockScope_Scores) -> Scores,
			        userServiceBuilder: @escaping (Service.SafeDIMockScope_UserService) -> any UserService
			    ) -> Service {
			        let __safeDI_scoresBuilder = scoresBuilder
			        let __safeDI_userServiceBuilder = userServiceBuilder
			        let userService: any UserService = __safeDI_userServiceBuilder(.userService(SafeDIMockScope_UserService.userService_Values()))
			        let scores: Scores = __safeDI_scoresBuilder(.scores(SafeDIMockScope_Scores.scores_Values(userService: userService)))
			        return Service(userService: userService, scores: scores)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_7F21AF0014D1F8D9 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderOfCalledPublicMock_whenConsumerSeesNoTypeThatFulfillsHole() async throws {
		// R7: `App` sees no declaration that fulfills `Service`'s hole, so `Screen`'s mock takes the builder the public mock
		// takes and passes it on.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.holeModules(app: Self.holeScreen),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        defaultUserServiceBuilder: @escaping (Service.SafeDIMockScope_DefaultUserService) -> AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(defaultUserServiceBuilder: defaultUserServiceBuilder, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        return Screen(analytics: analytics, service: service)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsBuilderOfCalledPublicMock_whenConsumerSeesTypeThatFulfillsHole() async throws {
		// M7.3: `App` sees `DefaultUserService`, so `Screen`'s mock fills `Service`'s builder with a function that builds it
		// from the values the scope struct carries.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.holeModules(app: Self.holeScreen + "\n\n" + Self.defaultUserService),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    let userService = AnyUserService(DefaultUserService(analytics: analytics))
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        return Screen(analytics: analytics, service: service)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillsInsideEachCallsBuilderFunction_whenConsumerCallsPublicMockTwice() async throws {
		// D530-1: `Screen` builds two `Service`s, each by calling its public mock with a fill of its own, declared inside
		// the function that makes the call, as a seam call's fills are, so the two fills do not redeclare one another.
		let modules = Self.holeModules(app: """
		import Core

		@Instantiable(generateMock: true)
		public final class Screen: Instantiable {
		    public init(analytics: Analytics, service: Service, backupService: Service) {
		        self.analytics = analytics
		        self.service = service
		        self.backupService = backupService
		    }

		    @Instantiated let analytics: Analytics
		    @Instantiated let service: Service
		    @Instantiated let backupService: Service
		}

		""" + Self.defaultUserService)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            backupService: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.backupService = backupService
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		        private(set) var backupService: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    let userService = AnyUserService(DefaultUserService(analytics: analytics))
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        func __safeDI_backupService() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    let userService = AnyUserService(DefaultUserService(analytics: analytics))
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.backupService)
		        }
		        let backupService: Service = __safeDI_backupService()
		        return Screen(analytics: analytics, service: service, backupService: backupService)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillInsideCallsBuilderFunction_whenPublicConsumerTakesABuilderForAHoleOfItsOwn() async throws {
		// D530-1: `Screen`'s own hole `userService` takes a builder, `missingWidgetBuilder`, beside the place of `Service`'s it
		// fills. The fill and its dispatcher are declared inside the function that calls `Service`'s mock, named by
		// `Service`'s builder and case, so they never share a scope or a name with `Screen`'s own builder.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.holeModules(app: """
			import Core

			public protocol Widget {}

			public struct AnyWidget {
			    public init(_ base: any Widget) {
			        self.base = base
			    }

			    public let base: any Widget
			}

			@Instantiable
			public struct WidgetHolder: Instantiable {
			    public init(userService: AnyWidget) {
			        self.userService = userService
			    }

			    @Received let userService: AnyWidget
			}

			@Instantiable(generateMock: .public)
			public final class Screen: Instantiable {
			    public init(analytics: Analytics, service: Service, userService: AnyWidget) {
			        self.analytics = analytics
			        self.service = service
			        self.userService = userService
			    }

			    @Instantiated let analytics: Analytics
			    @Instantiated let service: Service
			    @Instantiated(fulfilledByType: "MissingWidget", erasedToConcreteExistential: true) let userService: AnyWidget
			}

			""" + Self.defaultUserService),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    @frozen public enum SafeDIMockScope_MissingWidget {
		        case userService(userService_Values)

		        public struct userService_Values {
		            public let analytics: Analytics
		            public let service: Service
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        public private(set) var analytics: (() -> Analytics)?
		        public private(set) var service: Service.SafeDIOverrides
		    }

		    public static func mock(
		        missingWidgetBuilder: @escaping (Screen.SafeDIMockScope_MissingWidget) -> AnyWidget,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_missingWidgetBuilder = missingWidgetBuilder
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    let userService = AnyUserService(DefaultUserService(analytics: analytics))
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        let userService: AnyWidget = __safeDI_missingWidgetBuilder(.userService(SafeDIMockScope_MissingWidget.userService_Values(analytics: analytics, service: service)))
		        return Screen(analytics: analytics, service: service, userService: userService)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_30B48F3F91F71AF8 {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsBuilderWithHandWrittenMock_whenFulfillingTypeHasMockOnlyMock() async throws {
		// D530-2, O6: `App` declares `DefaultUserService` and, in a `mockOnly` extension, its hand-written mock, which the
		// inline mock builds it with. The fill builds it with that mock too, so `Screen.mock()` holds the fake.
		let modules = Self.holeModules(app: Self.holeScreen + "\n\n" + """
		@Instantiable
		public final class DefaultUserService: UserService, Instantiable {
		    public init(analytics: Analytics) {
		        self.analytics = analytics
		        isFake = false
		    }

		    fileprivate init(fakeAnalytics: Analytics) {
		        analytics = fakeAnalytics
		        isFake = true
		    }

		    @Received let analytics: Analytics
		    let isFake: Bool
		}

		@Instantiable(mockOnly: true)
		extension DefaultUserService {
		    public static func mock(analytics: Analytics = Analytics()) -> DefaultUserService {
		        DefaultUserService(fakeAnalytics: analytics)
		    }
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    let userService = AnyUserService(DefaultUserService.mock(analytics: analytics))
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        return Screen(analytics: analytics, service: service)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesCycleParameterToHandWrittenMock_whenLazyCycleInsideFillClosesOnTypeBuiltWithIt() async throws {
		// The fill of `Service`'s builder builds `DefaultUserService`, whose `t3Builder` builds `T3` with its hand-written
		// mock, and `T0`, inside it, instantiates `T3` again through a lazy cycle. `T0` declares `logger` again, which
		// `T3` receives only if available, so the function the cycle closes on takes `logger`, and the hand-written mock
		// is passed that parameter, as an initializer is, rather than `nil`: `Screen.mock()` holds what the inline mock
		// holds.
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
				"""
				@Instantiable
				public final class Analytics: Instantiable, Sendable {
				    public init() {}
				}

				@Instantiable
				package final class Session: Instantiable {
				    package init() {}
				}

				public protocol UserService {}

				public struct AnyUserService: UserService {
				    public init(_ userService: any UserService) {
				        self.userService = userService
				    }

				    public let userService: any UserService
				}

				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: AnyUserService) {
				        self.userService = userService
				    }

				    @Received let userService: AnyUserService
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    package init(analytics: Analytics, session: Session, userService: AnyUserService) {
				        self.analytics = analytics
				        self.session = session
				        self.userService = userService
				    }

				    @Received let analytics: Analytics
				    @Instantiated let session: Session
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
				"""
				import Core

				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(analytics: Analytics, service: Service) {
				        self.analytics = analytics
				        self.service = service
				    }

				    @Instantiated let analytics: Analytics
				    @Instantiated let service: Service
				}

				@Instantiable
				public final class DefaultUserService: UserService, Instantiable {
				    public init(analytics: Analytics, logger: Logger, t3Builder: Instantiator<T3>) {
				        self.analytics = analytics
				        self.logger = logger
				        self.t3Builder = t3Builder
				    }

				    @Received let analytics: Analytics
				    @Instantiated let logger: Logger
				    @Instantiated let t3Builder: Instantiator<T3>
				}

				@Instantiable
				public final class Logger: Instantiable {
				    public init(t3Builder: Instantiator<T3>?) {
				        self.t3Builder = t3Builder
				    }

				    @Received(onlyIfAvailable: true) let t3Builder: Instantiator<T3>?
				}

				@Instantiable
				public final class T3: Instantiable {
				    public init(logger: Logger?, t0Builder: Instantiator<T0>) {
				        self.logger = logger
				        self.t0Builder = t0Builder
				    }

				    public static func mock(logger: Logger?, t0Builder: Instantiator<T0>) -> T3 {
				        T3(logger: logger, t0Builder: t0Builder)
				    }

				    @Received(onlyIfAvailable: true) let logger: Logger?
				    @Instantiated let t0Builder: Instantiator<T0>
				}

				@Instantiable
				public final class T0: Instantiable {
				    public init(t3Builder: Instantiator<T3>, logger: Logger) {
				        self.t3Builder = t3Builder
				        self.logger = logger
				    }

				    @Instantiated let t3Builder: Instantiator<T3>
				    @Instantiated let logger: Logger
				}
				""",
			], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        func __safeDI_t3Builder(logger: Logger?) -> T3 {
		                            func __safeDI_t0Builder() -> T0 {
		                                let logger = Logger(t3Builder: nil)
		                                let t3Builder = Instantiator<T3> {
		                                    __safeDI_t3Builder(logger: logger)
		                                }
		                                return T0(t3Builder: t3Builder, logger: logger)
		                            }
		                            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
		                            return T3.mock(logger: logger, t0Builder: t0Builder)
		                        }
		                        let t3Builder = Instantiator<T3> {
		                            __safeDI_t3Builder(logger: nil)
		                        }
		                        let logger = Logger(t3Builder: t3Builder)
		                        return DefaultUserService(analytics: analytics, logger: logger, t3Builder: t3Builder)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        return Screen(analytics: analytics, service: service)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_closesLazyCycleOnHolePropertyInsideFill_whenMockFillsPublicMocksBuilder() async throws {
		// The fill of `Service`'s builder `routerBuilder` builds `Router`, whose `tBuilder` builds `T`, which instantiates
		// `routerBuilder` again: a lazy cycle that closes on the hole's property inside the fill. `T` declares `analytics`
		// again, so the function the cycle closes on, declared inside the fill, takes `analytics`, which the fill passes
		// from the field it binds and `T` passes its own, as any scope's function does. Generation ends, and
		// `Screen.mock()` holds what the inline mock holds.
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
				"""
				@Instantiable
				package final class Session: Instantiable {
				    package init() {}
				}

				public protocol Routing {}

				public struct AnyRouting {
				    public init(_ routing: any Routing) {}
				}

				@Instantiable
				public struct Profile: Instantiable {
				    public init(routing: AnyRouting) {
				        self.routing = routing
				    }

				    @Received let routing: AnyRouting
				}

				@Instantiable
				public final class Analytics: Instantiable {
				    public init() {}
				}

				@Instantiable(generateMock: .public)
				public final class Service: Instantiable {
				    package init(analytics: Analytics, session: Session, routerBuilder: ErasedInstantiator<(), AnyRouting>) {
				        self.analytics = analytics
				        self.session = session
				        self.routerBuilder = routerBuilder
				    }

				    @Received let analytics: Analytics
				    @Instantiated let session: Session
				    @Instantiated(fulfilledByType: "Router", erasedToConcreteExistential: true) let routerBuilder: ErasedInstantiator<(), AnyRouting>
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
				"""
				import Core

				@Instantiable
				public final class Router: Instantiable, Routing {
				    public init(analytics: Analytics, tBuilder: Instantiator<T>) {
				        self.analytics = analytics
				        self.tBuilder = tBuilder
				    }

				    @Received let analytics: Analytics
				    @Instantiated let tBuilder: Instantiator<T>
				}

				@Instantiable
				public final class T: Instantiable {
				    public init(analytics: Analytics, routerBuilder: ErasedInstantiator<(), AnyRouting>) {
				        self.analytics = analytics
				        self.routerBuilder = routerBuilder
				    }

				    @Instantiated let analytics: Analytics
				    @Instantiated(fulfilledByType: "Router", erasedToConcreteExistential: true) let routerBuilder: ErasedInstantiator<(), AnyRouting>
				}

				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
			], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_routerBuilder_Service(_ scope: Service.SafeDIMockScope_Router) -> AnyRouting {
		                switch scope {
		                case let .routerBuilder(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_routerBuilder(analytics: Analytics) -> Router {
		                        func __safeDI_tBuilder() -> T {
		                            let analytics = Analytics()
		                            let routerBuilder = ErasedInstantiator<(), AnyRouting> {
		                                AnyRouting(__safeDI_routerBuilder(analytics: analytics))
		                            }
		                            return T(analytics: analytics, routerBuilder: routerBuilder)
		                        }
		                        let tBuilder = Instantiator<T>(__safeDI_tBuilder)
		                        return Router(analytics: analytics, tBuilder: tBuilder)
		                    }
		                    return AnyRouting(__safeDI_routerBuilder(analytics: analytics))
		                }
		            }
		            _ = Service.__safeDI_Service_mock_E1790A899C2482D2.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(routerBuilder: __safeDI_routerBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        return Screen(service: service)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesParameterToPublicMockCallInsideFill_whenOnlyThatCallReceivesLabel() async throws {
		// The fill of `Service`'s builder builds `DefaultUserService`, whose `cache` is built by `Cache`'s public mock, which
		// takes `filter`, received only if available in its tree. Nothing else in `Screen`'s tree receives `filter`, so
		// `Screen`'s public mock takes it as a parameter, and the call inside the fill passes that parameter: `Screen.mock(filter:)`
		// holds what the inline mock holds when its override is set.
		let modules = Self.fillReceivingLabelModules(app: Self.fillReceivingLabelScreen(generateMock: ".public") + "\n\n" + """
		@Instantiable
		public final class DefaultUserService: UserService, Instantiable {
		    public init(analytics: Analytics, cache: Cache) {
		        self.analytics = analytics
		        self.cache = cache
		    }

		    @Received let analytics: Analytics
		    @Instantiated let cache: Cache
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        public private(set) var analytics: (() -> Analytics)?
		        public private(set) var service: Service.SafeDIOverrides
		    }

		    public static func mock(
		        filter: (any FilterProtocol)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        let cache = Cache.mock(filter: filter)
		                        return DefaultUserService(analytics: analytics, cache: cache)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        return Screen(analytics: analytics, service: service)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_215B449271BCAB93 {}
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()"), Self.screenMockPassingFilter])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToPublicMockCallInsideFill_whenInternalMockTakesNothingForLabelOnlyThatCallReceives() async throws {
		// The internal mock of the cell above: a mock that is not public takes no parameter or override for what only calls
		// of other modules' public mocks receive, so the call inside the fill passes `nil`, as one outside a fill does.
		let modules = Self.fillReceivingLabelModules(app: Self.fillReceivingLabelScreen(generateMock: "true") + "\n\n" + """
		@Instantiable
		public final class DefaultUserService: UserService, Instantiable {
		    public init(analytics: Analytics, cache: Cache) {
		        self.analytics = analytics
		        self.cache = cache
		    }

		    @Received let analytics: Analytics
		    @Instantiated let cache: Cache
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        let cache = Cache.mock(filter: nil)
		                        return DefaultUserService(analytics: analytics, cache: cache)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        return Screen(analytics: analytics, service: service)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesParameterToFunctionLazyCycleClosesOnInsideFill_whenOnlyPublicMockCallInCycleReceivesLabel() async throws {
		// The fill of `Service`'s builder `routerBuilder` builds `Router`, and `T`, in `Router`'s tree, builds `routerBuilder`
		// again: a lazy cycle that closes on the hole's property inside the fill. `Router`'s call of `Cache`'s public mock
		// receives `filter`, which `T` declares again, so the function the cycle closes on takes `filter`. `Screen`'s public
		// mock takes `filter`, which nothing else in its tree receives, and the fill passes that parameter to the function,
		// where `T` passes its own.
		let modules = Self.lazyCycleThroughFillModules(router: """
		@Instantiable
		public final class Router: Instantiable, Routing {
		    public init(analytics: Analytics, cache: Cache, tBuilder: Instantiator<T>) {
		        self.analytics = analytics
		        self.cache = cache
		        self.tBuilder = tBuilder
		    }

		    @Received let analytics: Analytics
		    @Instantiated let cache: Cache
		    @Instantiated let tBuilder: Instantiator<T>
		}

		@Instantiable
		public final class T: Instantiable {
		    public init(filter: any FilterProtocol, routerBuilder: ErasedInstantiator<(), AnyRouting>) {
		        self.filter = filter
		        self.routerBuilder = routerBuilder
		    }

		    @Instantiated(fulfilledByType: "AppFilter") let filter: any FilterProtocol
		    @Instantiated(fulfilledByType: "Router", erasedToConcreteExistential: true) let routerBuilder: ErasedInstantiator<(), AnyRouting>
		}

		@Instantiable(fulfillingAdditionalTypes: [FilterProtocol.self])
		public final class AppFilter: Instantiable, FilterProtocol {
		    public init() {}
		}


		\(Self.fillReceivingLabelProbeFilter)
		""", screenMockGeneration: ".public", coreAddition: Self.fillReceivingLabelCache(receivingFilter: .onlyIfAvailable))
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        public private(set) var analytics: (() -> Analytics)?
		        public private(set) var service: Service.SafeDIOverrides
		    }

		    public static func mock(
		        analytics: Analytics? = nil,
		        filter: (any FilterProtocol)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let analytics { analytics } else if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_routerBuilder_Service(_ scope: Service.SafeDIMockScope_Router) -> AnyRouting {
		                switch scope {
		                case let .routerBuilder(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_routerBuilder(filter: (any FilterProtocol)?) -> Router {
		                        let cache = Cache.mock(filter: filter)
		                        func __safeDI_tBuilder() -> T {
		                            let filter: any FilterProtocol = AppFilter()
		                            let routerBuilder = ErasedInstantiator<(), AnyRouting> {
		                                AnyRouting(__safeDI_routerBuilder(filter: filter))
		                            }
		                            return T(filter: filter, routerBuilder: routerBuilder)
		                        }
		                        let tBuilder = Instantiator<T>(__safeDI_tBuilder)
		                        return Router(analytics: analytics, cache: cache, tBuilder: tBuilder)
		                    }
		                    return AnyRouting(__safeDI_routerBuilder(filter: filter))
		                }
		            }
		            _ = Service.__safeDI_Service_mock_E1790A899C2482D2.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(routerBuilder: __safeDI_routerBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        return Screen(service: service)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_2A5202218C323ACA {}
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()"), Self.screenMockPassingFilter])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesParameterToFunctionLazyCycleClosesOnInsideFill_whenCycleThroughInstantiatorsHoldsOnlyPublicMockCallThatReceivesLabel() async throws {
		// The fill of `Service`'s builder builds `DefaultUserService`, whose `routerBuilder` builds `Router`, and `T`, in
		// `Router`'s tree, builds `routerBuilder` again: a lazy cycle inside the fill, through `Instantiator`s, which the
		// value comparison follows. `Router`'s call of `Cache`'s public mock receives `filter`, which `T` declares again, so
		// the function the cycle closes on takes `filter`, which the fill passes from `Screen`'s parameter.
		let modules = Self.fillReceivingLabelModules(app: Self.fillReceivingLabelScreen(generateMock: ".public") + "\n\n" + """
		@Instantiable
		public final class DefaultUserService: UserService, Instantiable {
		    public init(analytics: Analytics, routerBuilder: Instantiator<Router>) {
		        self.analytics = analytics
		        self.routerBuilder = routerBuilder
		    }

		    @Received let analytics: Analytics
		    @Instantiated let routerBuilder: Instantiator<Router>
		}

		@Instantiable
		public final class Router: Instantiable {
		    public init(cache: Cache, tBuilder: Instantiator<T>) {
		        self.cache = cache
		        self.tBuilder = tBuilder
		    }

		    @Instantiated let cache: Cache
		    @Instantiated let tBuilder: Instantiator<T>
		}

		@Instantiable
		public final class T: Instantiable {
		    public init(filter: any FilterProtocol, routerBuilder: Instantiator<Router>) {
		        self.filter = filter
		        self.routerBuilder = routerBuilder
		    }

		    @Instantiated(fulfilledByType: "AppFilter") let filter: any FilterProtocol
		    @Instantiated let routerBuilder: Instantiator<Router>
		}

		@Instantiable(fulfillingAdditionalTypes: [FilterProtocol.self])
		public final class AppFilter: Instantiable, FilterProtocol {
		    public init() {}
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        public private(set) var analytics: (() -> Analytics)?
		        public private(set) var service: Service.SafeDIOverrides
		    }

		    public static func mock(
		        filter: (any FilterProtocol)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        func __safeDI_routerBuilder(filter: (any FilterProtocol)?) -> Router {
		                            let cache = Cache.mock(filter: filter)
		                            func __safeDI_tBuilder() -> T {
		                                let filter: any FilterProtocol = AppFilter()
		                                let routerBuilder = Instantiator<Router> {
		                                    __safeDI_routerBuilder(filter: filter)
		                                }
		                                return T(filter: filter, routerBuilder: routerBuilder)
		                            }
		                            let tBuilder = Instantiator<T>(__safeDI_tBuilder)
		                            return Router(cache: cache, tBuilder: tBuilder)
		                        }
		                        let routerBuilder = Instantiator<Router> {
		                            __safeDI_routerBuilder(filter: filter)
		                        }
		                        return DefaultUserService(analytics: analytics, routerBuilder: routerBuilder)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        return Screen(analytics: analytics, service: service)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_215B449271BCAB93 {}
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()"), Self.screenMockPassingFilter])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesParameterToPublicMockCallInsideNestedFill_whenOnlyThatCallReceivesLabel() async throws {
		// The fill of `Service`'s builder builds `DefaultUserService`, which builds `Board` with its public mock, whose
		// builder `App` fills with `DefaultWidget`, which builds `cache` with `Cache`'s public mock: a fill inside a fill.
		// Only that call receives `filter`, which `Screen`'s public mock takes, and the call two fills deep passes it.
		let modules = Self.fillReceivingLabelModules(app: Self.fillReceivingLabelScreen(generateMock: ".public") + "\n\n" + """
		@Instantiable
		public final class DefaultUserService: UserService, Instantiable {
		    public init(analytics: Analytics, board: Board) {
		        self.analytics = analytics
		        self.board = board
		    }

		    @Received let analytics: Analytics
		    @Instantiated let board: Board
		}

		@Instantiable
		public final class DefaultWidget: Widget, Instantiable {
		    public init(cache: Cache) {
		        self.cache = cache
		    }

		    @Instantiated let cache: Cache
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        public private(set) var analytics: (() -> Analytics)?
		        public private(set) var service: Service.SafeDIOverrides
		    }

		    public static func mock(
		        filter: (any FilterProtocol)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        func __safeDI_board() -> Board {
		                            func __safeDI_defaultWidgetBuilder_Board(_ scope: Board.SafeDIMockScope_DefaultWidget) -> AnyWidget {
		                                switch scope {
		                                case .widget:
		                                    func __safeDI_widget() -> DefaultWidget {
		                                        let cache = Cache.mock(filter: filter)
		                                        return DefaultWidget(cache: cache)
		                                    }
		                                    let widget = AnyWidget(__safeDI_widget())
		                                    return widget
		                                }
		                            }
		                            return Board.mock(defaultWidgetBuilder: __safeDI_defaultWidgetBuilder_Board)
		                        }
		                        let board: Board = __safeDI_board()
		                        return DefaultUserService(analytics: analytics, board: board)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        return Screen(analytics: analytics, service: service)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_215B449271BCAB93 {}
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()"), Self.screenMockPassingFilter])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesOneParameterToPublicMockCallsInsideTwoFills_whenOnlyThoseCallsReceiveLabel() async throws {
		// `Screen` builds `Service` and `Board` with their public mocks, whose builders `App` fills with `DefaultUserService`
		// and `DefaultWidget`, each of which builds `cache` with `Cache`'s public mock. Only those two calls receive `filter`,
		// which `Screen`'s public mock takes once, and each call passes it: both caches hold the one value.
		let modules = Self.fillReceivingLabelModules(app: Self.fillReceivingLabelScreen(generateMock: ".public", instantiatesBoard: true) + "\n\n" + """
		@Instantiable
		public final class DefaultUserService: UserService, Instantiable {
		    public init(analytics: Analytics, cache: Cache) {
		        self.analytics = analytics
		        self.cache = cache
		    }

		    @Received let analytics: Analytics
		    @Instantiated let cache: Cache
		}

		@Instantiable
		public final class DefaultWidget: Widget, Instantiable {
		    public init(cache: Cache) {
		        self.cache = cache
		    }

		    @Instantiated let cache: Cache
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            board: Board.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.board = board
		        }

		        public private(set) var analytics: (() -> Analytics)?
		        public private(set) var service: Service.SafeDIOverrides
		        public private(set) var board: Board.SafeDIOverrides
		    }

		    public static func mock(
		        filter: (any FilterProtocol)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        let cache = Cache.mock(filter: filter)
		                        return DefaultUserService(analytics: analytics, cache: cache)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        func __safeDI_board() -> Board {
		            func __safeDI_defaultWidgetBuilder_Board(_ scope: Board.SafeDIMockScope_DefaultWidget) -> AnyWidget {
		                switch scope {
		                case .widget:
		                    func __safeDI_widget() -> DefaultWidget {
		                        let cache = Cache.mock(filter: filter)
		                        return DefaultWidget(cache: cache)
		                    }
		                    let widget = AnyWidget(__safeDI_widget())
		                    return widget
		                }
		            }
		            _ = Board.__safeDI_Board_mock_C0535866CC28FFB0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Board.mock(defaultWidgetBuilder: __safeDI_defaultWidgetBuilder_Board, safeDIOverrides: safeDIOverrides.board)
		        }
		        let board: Board = __safeDI_board()
		        return Screen(analytics: analytics, service: service, board: board)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_215B449271BCAB93 {}
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()"), Self.screenMockPassingFilter])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsDependencyOnceForPublicMockCallInsideFill_whenCalledMockBuildsItWhenPassedNil() async throws {
		// `TokenCache` requires `filter`, which `Cache`'s public mock takes as `filter: (any FilterProtocol)? = nil` and builds
		// as `CoreFilter` when passed `nil`. `Screen`'s tree calls it inside the fills of `Service`'s builder and of `Board`'s.
		// `Screen`'s public mock builds `filter` once, as the inline mock does, from its parameter, its override or
		// `CoreFilter`, and passes it to both calls: both caches hold the one value.
		let modules = Self.fillReceivingLabelModules(receivingFilter: .required, app: Self.fillReceivingLabelScreen(generateMock: ".public", instantiatesBoard: true) + "\n\n" + """
		@Instantiable
		public final class DefaultUserService: UserService, Instantiable {
		    public init(analytics: Analytics, cache: Cache) {
		        self.analytics = analytics
		        self.cache = cache
		    }

		    @Received let analytics: Analytics
		    @Instantiated let cache: Cache
		}

		@Instantiable
		public final class DefaultWidget: Widget, Instantiable {
		    public init(cache: Cache) {
		        self.cache = cache
		    }

		    @Instantiated let cache: Cache
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            filter: (() -> FilterProtocol)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            board: Board.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.filter = filter
		            self.service = service
		            self.board = board
		        }

		        public private(set) var analytics: (() -> Analytics)?
		        public private(set) var filter: (() -> FilterProtocol)?
		        public private(set) var service: Service.SafeDIOverrides
		        public private(set) var board: Board.SafeDIOverrides
		    }

		    public static func mock(
		        filter: (any FilterProtocol)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        let filter: FilterProtocol = if let filter { filter } else if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder() } else { CoreFilter() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        let cache = Cache.mock(filter: filter)
		                        return DefaultUserService(analytics: analytics, cache: cache)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        func __safeDI_board() -> Board {
		            func __safeDI_defaultWidgetBuilder_Board(_ scope: Board.SafeDIMockScope_DefaultWidget) -> AnyWidget {
		                switch scope {
		                case .widget:
		                    func __safeDI_widget() -> DefaultWidget {
		                        let cache = Cache.mock(filter: filter)
		                        return DefaultWidget(cache: cache)
		                    }
		                    let widget = AnyWidget(__safeDI_widget())
		                    return widget
		                }
		            }
		            _ = Board.__safeDI_Board_mock_C0535866CC28FFB0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Board.mock(defaultWidgetBuilder: __safeDI_defaultWidgetBuilder_Board, safeDIOverrides: safeDIOverrides.board)
		        }
		        let board: Board = __safeDI_board()
		        return Screen(analytics: analytics, service: service, board: board)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_215B449271BCAB93 {}
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()"), Self.screenMockPassingFilterToBuildInstead])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsDependencyOnceForPublicMockCallInsideFill_whenInternalMockAndCalledMockBuildsItWhenPassedNil() async throws {
		// The internal mock of the cell above builds `filter` once too, from its override or `CoreFilter`, as the inline mock
		// does, and passes it to the calls inside both fills.
		let modules = Self.fillReceivingLabelModules(receivingFilter: .required, app: Self.fillReceivingLabelScreen(generateMock: "true", instantiatesBoard: true) + "\n\n" + """
		@Instantiable
		public final class DefaultUserService: UserService, Instantiable {
		    public init(analytics: Analytics, cache: Cache) {
		        self.analytics = analytics
		        self.cache = cache
		    }

		    @Received let analytics: Analytics
		    @Instantiated let cache: Cache
		}

		@Instantiable
		public final class DefaultWidget: Widget, Instantiable {
		    public init(cache: Cache) {
		        self.cache = cache
		    }

		    @Instantiated let cache: Cache
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            filter: (() -> FilterProtocol)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            board: Board.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.filter = filter
		            self.service = service
		            self.board = board
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var filter: (() -> FilterProtocol)?
		        private(set) var service: Service.SafeDIOverrides
		        private(set) var board: Board.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        let filter: FilterProtocol = if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder() } else { CoreFilter() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        let cache = Cache.mock(filter: filter)
		                        return DefaultUserService(analytics: analytics, cache: cache)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        func __safeDI_board() -> Board {
		            func __safeDI_defaultWidgetBuilder_Board(_ scope: Board.SafeDIMockScope_DefaultWidget) -> AnyWidget {
		                switch scope {
		                case .widget:
		                    func __safeDI_widget() -> DefaultWidget {
		                        let cache = Cache.mock(filter: filter)
		                        return DefaultWidget(cache: cache)
		                    }
		                    let widget = AnyWidget(__safeDI_widget())
		                    return widget
		                }
		            }
		            _ = Board.__safeDI_Board_mock_C0535866CC28FFB0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Board.mock(defaultWidgetBuilder: __safeDI_defaultWidgetBuilder_Board, safeDIOverrides: safeDIOverrides.board)
		        }
		        let board: Board = __safeDI_board()
		        return Screen(analytics: analytics, service: service, board: board)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Screen.mock()"),
			DifferentialValueProbe("Screen.mock(safeDIOverrides: .init(filter: { ProbeFilter() }))"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesInstanceOfOneWrapperToPublicMockCallsInsideFills_whenCalledMockBuildsLazilyInstantiatedDependencyWhenPassedNil() async throws {
		// `TokenCache` requires `filter` as `LazilyInstantiated<any FilterProtocol>`, which `Cache`'s public mock builds from
		// `CoreFilter` when passed `nil`. `Screen`'s public mock builds that wrapper once, as the inline mock does, and passes
		// its instance to the calls inside the fills of `Service`'s builder and of `Board`'s.
		let modules = Self.fillReceivingLabelModules(receivingFilter: .requiredLazilyInstantiated, app: Self.fillReceivingLabelScreen(generateMock: ".public", instantiatesBoard: true) + "\n\n" + """
		@Instantiable
		public final class DefaultUserService: UserService, Instantiable {
		    public init(analytics: Analytics, cache: Cache) {
		        self.analytics = analytics
		        self.cache = cache
		    }

		    @Received let analytics: Analytics
		    @Instantiated let cache: Cache
		}

		@Instantiable
		public final class DefaultWidget: Widget, Instantiable {
		    public init(cache: Cache) {
		        self.cache = cache
		    }

		    @Instantiated let cache: Cache
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            filter: (() -> FilterProtocol)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            board: Board.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.filter = filter
		            self.service = service
		            self.board = board
		        }

		        public private(set) var analytics: (() -> Analytics)?
		        public private(set) var filter: (() -> FilterProtocol)?
		        public private(set) var service: Service.SafeDIOverrides
		        public private(set) var board: Board.SafeDIOverrides
		    }

		    public static func mock(
		        filter: (any FilterProtocol)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_filter() -> FilterProtocol {
		            if let filter { filter } else if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder() } else { CoreFilter() }
		        }
		        let filter = LazilyInstantiated<any FilterProtocol>(__safeDI_filter)
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        let cache = Cache.mock(filter: filter.instance)
		                        return DefaultUserService(analytics: analytics, cache: cache)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        func __safeDI_board() -> Board {
		            func __safeDI_defaultWidgetBuilder_Board(_ scope: Board.SafeDIMockScope_DefaultWidget) -> AnyWidget {
		                switch scope {
		                case .widget:
		                    func __safeDI_widget() -> DefaultWidget {
		                        let cache = Cache.mock(filter: filter.instance)
		                        return DefaultWidget(cache: cache)
		                    }
		                    let widget = AnyWidget(__safeDI_widget())
		                    return widget
		                }
		            }
		            _ = Board.__safeDI_Board_mock_C0535866CC28FFB0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Board.mock(defaultWidgetBuilder: __safeDI_defaultWidgetBuilder_Board, safeDIOverrides: safeDIOverrides.board)
		        }
		        let board: Board = __safeDI_board()
		        return Screen(analytics: analytics, service: service, board: board)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_215B449271BCAB93 {}
		}
		#endif
		"""])
		// M8.32's stated divergence: each call hands `Cache`'s mock the instance of the one wrapper, which the mock wraps
		// again; the instance is the one the inline mock shares.
		let probes = [DifferentialValueProbe("Screen.mock()"), Self.screenMockPassingFilterToBuildInstead]
		try await expectValuesAgreeWithInlineMocks(
			of: modules,
			output: output,
			probes: probes,
			exempting: probes.map { probe in
				DifferentialValueDifference(
					probe: probe.name,
					path: ["<1> Screen", "board", "widget", "widget", "cache", "tokenCache", "filter"],
					feature: "filter: <8> LazilyInstantiated<FilterProtocol> (instance read last)",
					knownRight: "filter: <5> LazilyInstantiated<FilterProtocol> (seen, first at <1> Screen > service > userService > userService > cache > tokenCache > filter)",
				)
			},
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesFieldToPublicMockCallInsideFill_whenScopeStructCarriesDependencyCalledMockBuildsWhenPassedNil() async throws {
		// `Service` instantiates `filter` before its hole, so the hole's scope struct carries it, and the call of `Cache`'s
		// public mock inside the fill is passed that field: `Screen`'s mock builds no `filter` and takes no parameter for it.
		let modules = Self.fillReceivingLabelModules(receivingFilter: .required, serviceInstantiatesFilter: true, app: Self.fillReceivingLabelScreen(generateMock: ".public") + "\n\n" + """
		@Instantiable
		public final class DefaultUserService: UserService, Instantiable {
		    public init(analytics: Analytics, cache: Cache) {
		        self.analytics = analytics
		        self.cache = cache
		    }

		    @Received let analytics: Analytics
		    @Instantiated let cache: Cache
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        public private(set) var analytics: (() -> Analytics)?
		        public private(set) var service: Service.SafeDIOverrides
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let filter = scope.filter
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        let cache = Cache.mock(filter: filter)
		                        return DefaultUserService(analytics: analytics, cache: cache)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_AB9786C80E02522B.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        return Screen(analytics: analytics, service: service)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_51799E6AA5E7B634 {}
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesTreesDeclarationToPublicMockCallInsideFill_whenPublicMockTreeDeclaresLabel() async throws {
		// `Screen` instantiates `filter` before `Service`, so the call of `Cache`'s public mock inside the fill is passed that
		// declaration, as the inline mock's `TokenCache` is: `Screen`'s public mock takes no parameter for it.
		let modules = Self.fillReceivingLabelModules(app: Self.fillReceivingLabelScreen(generateMock: ".public", filterType: "any FilterProtocol") + "\n\n" + """
		@Instantiable
		public final class DefaultUserService: UserService, Instantiable {
		    public init(analytics: Analytics, cache: Cache) {
		        self.analytics = analytics
		        self.cache = cache
		    }

		    @Received let analytics: Analytics
		    @Instantiated let cache: Cache
		}

		@Instantiable(fulfillingAdditionalTypes: [FilterProtocol.self])
		public final class AppFilter: Instantiable, FilterProtocol {
		    public init() {}
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            filter: (() -> FilterProtocol)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.filter = filter
		            self.service = service
		        }

		        public private(set) var analytics: (() -> Analytics)?
		        public private(set) var filter: (() -> FilterProtocol)?
		        public private(set) var service: Service.SafeDIOverrides
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        let filter: FilterProtocol = if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder() } else { AppFilter() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        let cache = Cache.mock(filter: filter)
		                        return DefaultUserService(analytics: analytics, cache: cache)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        return Screen(analytics: analytics, filter: filter, service: service)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_51799E6AA5E7B634 {}
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToPublicMockCallInsideFill_whenInternalMockBuildsLabelAfterFillsCaller() async throws {
		// `Screen` declares `filter` after `service`, and `AppFilter`, which builds `filter`, requires `service`, so `service`
		// is built first. The call of `Cache`'s public mock inside `service`'s fill receives `filter` only if available, so it
		// is passed `nil`, as the inline mock's `TokenCache` is, never the `filter` declared after it.
		let modules = Self.fillReceivingLabelModules(app: Self.screenBuildingServiceBeforeFilter(generateMock: "true") + "\n\n" + Self.userServiceBuildingCache)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            filter: ((Service) -> FilterProtocol)? = nil
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.filter = filter
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		        private(set) var filter: ((Service) -> FilterProtocol)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        let cache = Cache.mock(filter: nil)
		                        return DefaultUserService(analytics: analytics, cache: cache)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        let filter: FilterProtocol = if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder(service) } else { AppFilter(service: service) }
		        return Screen(analytics: analytics, service: service, filter: filter)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToPublicMockCallInsideFill_whenPublicMockBuildsLabelAfterFillsCaller() async throws {
		// The public mock of the cell above passes the call inside `service`'s fill `nil` too.
		let modules = Self.fillReceivingLabelModules(app: Self.screenBuildingServiceBeforeFilter(generateMock: ".public") + "\n\n" + Self.userServiceBuildingCache)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            filter: ((Service) -> FilterProtocol)? = nil
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.filter = filter
		        }

		        public private(set) var analytics: (() -> Analytics)?
		        public private(set) var service: Service.SafeDIOverrides
		        public private(set) var filter: ((Service) -> FilterProtocol)?
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        let cache = Cache.mock(filter: nil)
		                        return DefaultUserService(analytics: analytics, cache: cache)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        let filter: FilterProtocol = if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder(service) } else { AppFilter(service: service) }
		        return Screen(analytics: analytics, service: service, filter: filter)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_51799E6AA5E7B634 {}
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesLabelToPublicMockCallInsideFill_whenBuilderOfLabelReceivesFillsCallerOnlyIfAvailable() async throws {
		// `AppFilter` receives `service` only if available, so `filter` is built first, passed `nil` for `service`, and the
		// call inside `service`'s fill is passed `filter`, as the inline mock's `TokenCache` is.
		let modules = Self.fillReceivingLabelModules(app: Self.screenBuildingServiceBeforeFilter(generateMock: "true", appFilterReceivesServiceOnlyIfAvailable: true) + "\n\n" + Self.userServiceBuildingCache)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            filter: ((Service?) -> FilterProtocol)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.filter = filter
		            self.service = service
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var filter: ((Service?) -> FilterProtocol)?
		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        let filter: FilterProtocol = if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder(nil) } else { AppFilter(service: nil) }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        let cache = Cache.mock(filter: filter)
		                        return DefaultUserService(analytics: analytics, cache: cache)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        return Screen(analytics: analytics, service: service, filter: filter)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesEachPublicMockCallInsideFillsWhatItsCallerHolds_whenOneCallerIsBuiltBeforeLabelAndAnotherAfter() async throws {
		// `Screen` builds `service` before `filter` and `laterService` after it, each with `Service`'s public mock, whose
		// builder it fills with `DefaultUserService`. The call of `Cache`'s public mock in `service`'s fill is passed `nil`,
		// and the one in `laterService`'s fill `filter`, as the inline mock's two `TokenCache`s are.
		let modules = Self.fillReceivingLabelModules(app: Self.screenBuildingServiceBeforeFilter(generateMock: ".public", instantiatesLaterService: true) + "\n\n" + Self.userServiceBuildingCache)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            filter: ((Service) -> FilterProtocol)? = nil,
		            laterService: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.filter = filter
		            self.laterService = laterService
		        }

		        public private(set) var analytics: (() -> Analytics)?
		        public private(set) var service: Service.SafeDIOverrides
		        public private(set) var filter: ((Service) -> FilterProtocol)?
		        public private(set) var laterService: Service.SafeDIOverrides
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        let cache = Cache.mock(filter: nil)
		                        return DefaultUserService(analytics: analytics, cache: cache)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        let filter: FilterProtocol = if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder(service) } else { AppFilter(service: service) }
		        func __safeDI_laterService() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        let cache = Cache.mock(filter: filter)
		                        return DefaultUserService(analytics: analytics, cache: cache)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.laterService)
		        }
		        let laterService: Service = __safeDI_laterService()
		        return Screen(analytics: analytics, service: service, filter: filter, laterService: laterService)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_51799E6AA5E7B634 {}
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToPublicMockCallInsideNestedFill_whenMockBuildsLabelAfterOuterFillsCaller() async throws {
		// `service`'s fill builds `DefaultUserService`, which builds `Board` with its public mock, whose builder `App` fills
		// with `DefaultWidget`, which builds `cache` with `Cache`'s public mock: a fill inside a fill. `service` is built
		// before `filter`, so the call two fills deep is passed `nil`, as the inline mock's `TokenCache` is.
		let modules = Self.fillReceivingLabelModules(app: Self.screenBuildingServiceBeforeFilter(generateMock: "true") + "\n\n" + """
		@Instantiable
		public final class DefaultUserService: UserService, Instantiable {
		    public init(analytics: Analytics, board: Board) {
		        self.analytics = analytics
		        self.board = board
		    }

		    @Received let analytics: Analytics
		    @Instantiated let board: Board
		}

		@Instantiable
		public final class DefaultWidget: Widget, Instantiable {
		    public init(cache: Cache) {
		        self.cache = cache
		    }

		    @Instantiated let cache: Cache
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            filter: ((Service) -> FilterProtocol)? = nil
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.filter = filter
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		        private(set) var filter: ((Service) -> FilterProtocol)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        func __safeDI_board() -> Board {
		                            func __safeDI_defaultWidgetBuilder_Board(_ scope: Board.SafeDIMockScope_DefaultWidget) -> AnyWidget {
		                                switch scope {
		                                case .widget:
		                                    func __safeDI_widget() -> DefaultWidget {
		                                        let cache = Cache.mock(filter: nil)
		                                        return DefaultWidget(cache: cache)
		                                    }
		                                    let widget = AnyWidget(__safeDI_widget())
		                                    return widget
		                                }
		                            }
		                            return Board.mock(defaultWidgetBuilder: __safeDI_defaultWidgetBuilder_Board)
		                        }
		                        let board: Board = __safeDI_board()
		                        return DefaultUserService(analytics: analytics, board: board)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        let filter: FilterProtocol = if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder(service) } else { AppFilter(service: service) }
		        return Screen(analytics: analytics, service: service, filter: filter)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesInstanceToPublicMockCallInsideFill_whenMockTreeDeclaresLabelAsLazilyInstantiated() async throws {
		// `Screen` instantiates `filter` as `LazilyInstantiated<any FilterProtocol>`, so the call of `Cache`'s public mock
		// inside the fill, which takes `filter` by value, is passed its instance, as a call outside a fill is and as the
		// inline mock's `TokenCache` is.
		let modules = Self.fillReceivingLabelModules(app: Self.fillReceivingLabelScreen(generateMock: "true", filterType: "LazilyInstantiated<any FilterProtocol>") + "\n\n" + """
		@Instantiable
		public final class DefaultUserService: UserService, Instantiable {
		    public init(analytics: Analytics, cache: Cache) {
		        self.analytics = analytics
		        self.cache = cache
		    }

		    @Received let analytics: Analytics
		    @Instantiated let cache: Cache
		}

		@Instantiable(fulfillingAdditionalTypes: [FilterProtocol.self])
		public final class AppFilter: Instantiable, FilterProtocol {
		    public init() {}
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            filter: (() -> FilterProtocol)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.filter = filter
		            self.service = service
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var filter: (() -> FilterProtocol)?
		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_filter() -> FilterProtocol {
		            if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder() } else { AppFilter() }
		        }
		        let filter = LazilyInstantiated<any FilterProtocol>(__safeDI_filter)
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        let cache = Cache.mock(filter: filter.instance)
		                        return DefaultUserService(analytics: analytics, cache: cache)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        return Screen(analytics: analytics, filter: filter, service: service)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesParameterToPublicMockCallInsideFill_whenFillBuildsTypeWithHandWrittenMock() async throws {
		// The fill builds `DefaultUserService` with its hand-written mock, as the inline mock does, and that mock takes the
		// `cache` that `Cache`'s public mock builds, passed the `filter` that `Screen`'s public mock takes.
		let modules = Self.fillReceivingLabelModules(app: Self.fillReceivingLabelScreen(generateMock: ".public") + "\n\n" + """
		@Instantiable
		public final class DefaultUserService: UserService, Instantiable {
		    public init(analytics: Analytics, cache: Cache) {
		        self.analytics = analytics
		        self.cache = cache
		    }

		    public static func mock(analytics: Analytics, cache: Cache) -> DefaultUserService {
		        DefaultUserService(analytics: analytics, cache: cache)
		    }

		    @Received let analytics: Analytics
		    @Instantiated let cache: Cache
		}
		""")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        public private(set) var analytics: (() -> Analytics)?
		        public private(set) var service: Service.SafeDIOverrides
		    }

		    public static func mock(
		        filter: (any FilterProtocol)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_userService() -> DefaultUserService {
		                        let cache = Cache.mock(filter: filter)
		                        return DefaultUserService.mock(analytics: analytics, cache: cache)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        return Screen(analytics: analytics, service: service)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_215B449271BCAB93 {}
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()"), Self.screenMockPassingFilter])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsBuilderWithMockOnlyFake_whenOnlyFakeFulfillsHole() async throws {
		// D530-2, O6: only `App`'s `mockOnly` `FakeUserService` fulfills `Service`'s hole `userService`, which the inline
		// mock builds with its mock, so `Screen`'s mock fills the builder with it rather than take the builder.
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
				"""
				@Instantiable
				public final class Analytics: Instantiable {
				    public init() {}
				}

				@Instantiable
				package final class Session: Instantiable {
				    package init() {}
				}

				public protocol UserService {}

				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: any UserService) {
				        self.userService = userService
				    }

				    @Received let userService: any UserService
				}

				@Instantiable(generateMock: .public)
				public final class Service: Instantiable {
				    package init(analytics: Analytics, session: Session, userService: any UserService) {
				        self.analytics = analytics
				        self.session = session
				        self.userService = userService
				    }

				    @Received let analytics: Analytics
				    @Instantiated let session: Session
				    @Instantiated let userService: any UserService
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
				Self.holeScreen,
				"""
				import Core

				@Instantiable(fulfillingAdditionalTypes: [UserService.self], mockOnly: true)
				public final class FakeUserService: UserService {
				    public static func mock() -> FakeUserService {
				        FakeUserService()
				    }
				}
				""",
			], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIMockScope_UserService) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = FakeUserService.mock()
		                    return userService
		                }
		            }
		            _ = Service.__safeDI_Service_mock_886D678225DFE124.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(userServiceBuilder: __safeDI_userServiceBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        return Screen(analytics: analytics, service: service)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_refersToEnclosingFill_whenFillBuildsTypeWhoseInstantiatorCallsSamePublicMock() async throws {
		// M8.27: `Router` fills `Service`'s hole and builds `Service` again through an `Instantiator`, a fully lazy cycle.
		// The call inside the fill passes the fill around it, which it refers to by name.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.lazyCycleThroughFillModules(router: """
			@Instantiable
			public final class Router: Instantiable, Routing {
			    public init(serviceBuilder: Instantiator<Service>) {
			        self.serviceBuilder = serviceBuilder
			    }

			    @Instantiated let serviceBuilder: Instantiator<Service>
			}
			"""),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            func __safeDI_routerBuilder_Service(_ scope: Service.SafeDIMockScope_Router) -> AnyRouting {
		                switch scope {
		                case let .routerBuilder(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_routerBuilder() -> Router {
		                        func __safeDI_serviceBuilder() -> Service {
		                            Service.mock(routerBuilder: __safeDI_routerBuilder_Service, analytics: analytics)
		                        }
		                        let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
		                        return Router(serviceBuilder: serviceBuilder)
		                    }
		                    return AnyRouting(__safeDI_routerBuilder())
		                }
		            }
		            _ = Service.__safeDI_Service_mock_E1790A899C2482D2.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service.mock(routerBuilder: __safeDI_routerBuilder_Service, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        }
		        let service: Service = __safeDI_service()
		        return Screen(service: service)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderUp_whenFillWouldReceiveInstantiatorOfTypeItBuildsWithin() async throws {
		// M8.27b: `Router` receives the `Instantiator<Service>` whose tree it is built in, which no value of the scope
		// struct gives it, so `Screen`'s mock does not fill `Service`'s builder: it takes it, as a caller that sees no
		// fulfilling type does.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.lazyCycleThroughFillModules(router: """
			@Instantiable
			public final class Router: Instantiable, Routing {
			    public init(serviceBuilder: Instantiator<Service>) {
			        self.serviceBuilder = serviceBuilder
			    }

			    @Received let serviceBuilder: Instantiator<Service>
			}
			"""),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        routerBuilder: @escaping (Service.SafeDIMockScope_Router) -> AnyRouting,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        _ = Service.__safeDI_Service_mock_E1790A899C2482D2.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(routerBuilder: routerBuilder, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        return Screen(service: service)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderUpOnPublicTier_whenPublicConsumerSeesNoTypeThatFulfillsHole() async throws {
		// R7: `Screen`'s own public mock takes the builder it passes up on its public tier, as `Service`'s takes it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.holeModules(app: Self.holeScreen.replacingOccurrences(of: "generateMock: true", with: "generateMock: .public")),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    @frozen public enum SafeDIMockScope_DefaultUserService {
		        case service(Service.SafeDIMockScope_DefaultUserService)
		    }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        public private(set) var analytics: (() -> Analytics)?
		        public private(set) var service: Service.SafeDIOverrides
		    }

		    public static func mock(
		        defaultUserServiceBuilder: @escaping (Screen.SafeDIMockScope_DefaultUserService) -> AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_defaultUserServiceBuilder = defaultUserServiceBuilder
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(defaultUserServiceBuilder: { __safeDI_defaultUserServiceBuilder(.service($0)) }, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        return Screen(analytics: analytics, service: service)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_1B3FE368B3DD4F84 {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_ordersRouteCasesAsItsTreeCallsTheMocks_whenPublicConsumerPassesUpPlacesOfSixPublicMocks() async throws {
		// D530-4: `Screen` passes up each `ServiceN`'s place `userService`, all of one hole type, so its one builder's enum
		// holds a case per call, in the order its tree makes the calls, never a dictionary's. Each place's struct holds a
		// field of its own type, so the guard, which hashes every enum the builder reaches, differs in every order but one.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.sameLabelHoleModules(
				serviceNames: (0..<6).map { "Service\($0)" },
				screenMockGeneration: ".public",
				distinctValueInScopeAtEachHole: true,
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    @frozen public enum SafeDIMockScope_DefaultUserService {
		        case service0(Service0.SafeDIMockScope_DefaultUserService)
		        case service1(Service1.SafeDIMockScope_DefaultUserService)
		        case service2(Service2.SafeDIMockScope_DefaultUserService)
		        case service3(Service3.SafeDIMockScope_DefaultUserService)
		        case service4(Service4.SafeDIMockScope_DefaultUserService)
		        case service5(Service5.SafeDIMockScope_DefaultUserService)
		    }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            service0: Service0.SafeDIOverrides = .init(),
		            service1: Service1.SafeDIOverrides = .init(),
		            service2: Service2.SafeDIOverrides = .init(),
		            service3: Service3.SafeDIOverrides = .init(),
		            service4: Service4.SafeDIOverrides = .init(),
		            service5: Service5.SafeDIOverrides = .init()
		        ) {
		            self.service0 = service0
		            self.service1 = service1
		            self.service2 = service2
		            self.service3 = service3
		            self.service4 = service4
		            self.service5 = service5
		        }

		        public private(set) var service0: Service0.SafeDIOverrides
		        public private(set) var service1: Service1.SafeDIOverrides
		        public private(set) var service2: Service2.SafeDIOverrides
		        public private(set) var service3: Service3.SafeDIOverrides
		        public private(set) var service4: Service4.SafeDIOverrides
		        public private(set) var service5: Service5.SafeDIOverrides
		    }

		    public static func mock(
		        defaultUserServiceBuilder: @escaping (Screen.SafeDIMockScope_DefaultUserService) -> AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_defaultUserServiceBuilder = defaultUserServiceBuilder
		        _ = Service0.__safeDI_Service0_mock_F9084F4AFFA1E63F.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service0 = Service0.mock(defaultUserServiceBuilder: { __safeDI_defaultUserServiceBuilder(.service0($0)) }, safeDIOverrides: safeDIOverrides.service0)
		        _ = Service1.__safeDI_Service1_mock_7A595550A7B5843A.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service1 = Service1.mock(defaultUserServiceBuilder: { __safeDI_defaultUserServiceBuilder(.service1($0)) }, safeDIOverrides: safeDIOverrides.service1)
		        _ = Service2.__safeDI_Service2_mock_B1F48B664D432DA1.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service2 = Service2.mock(defaultUserServiceBuilder: { __safeDI_defaultUserServiceBuilder(.service2($0)) }, safeDIOverrides: safeDIOverrides.service2)
		        _ = Service3.__safeDI_Service3_mock_CA9914BC1A48BB84.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service3 = Service3.mock(defaultUserServiceBuilder: { __safeDI_defaultUserServiceBuilder(.service3($0)) }, safeDIOverrides: safeDIOverrides.service3)
		        _ = Service4.__safeDI_Service4_mock_667A316E56DD0B9B.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service4 = Service4.mock(defaultUserServiceBuilder: { __safeDI_defaultUserServiceBuilder(.service4($0)) }, safeDIOverrides: safeDIOverrides.service4)
		        _ = Service5.__safeDI_Service5_mock_1AE9829867C9AD7E.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service5 = Service5.mock(defaultUserServiceBuilder: { __safeDI_defaultUserServiceBuilder(.service5($0)) }, safeDIOverrides: safeDIOverrides.service5)
		        return Screen(service0: service0, service1: service1, service2: service2, service3: service3, service4: service4, service5: service5)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_8474E1B9534A0D86 {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesThePublicCallersOneBuilder_whenItPassesUpPlacesOfTwoMocksOfOneHoleType() async throws {
		// D530-4: `Screen`'s public mock passes up the places `userService` of `Service` and `Settings`, of one hole type, in
		// one builder whose enum holds a case per call, so `Root`'s mock, which sees no type that fulfills them, takes that
		// builder and passes it on.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.sameLabelHoleModules(serviceNames: ["Service", "Settings"], screenMockGeneration: ".public") + [
				ModuleFixture(name: "Other", packageName: "other", swiftFileContent: [Self.sameLabelHoleRoot], dependencies: ["Core", "App"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Other"]?.generatedFiles == ["Other.swift": generatedFileHeader + """
		#if canImport(App)
		import App
		#endif
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screen: Screen.SafeDIOverrides = .init()
		        ) {
		            self.screen = screen
		        }

		        private(set) var screen: Screen.SafeDIOverrides
		    }

		    static func mock(
		        defaultUserServiceBuilder: @escaping (Screen.SafeDIMockScope_DefaultUserService) -> AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        _ = Screen.__safeDI_Screen_mock_4A643395AAD25696.self // If this line does not compile, compile the code SafeDI generates for module App into App: under Bazel, add App's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let screen = Screen.mock(defaultUserServiceBuilder: defaultUserServiceBuilder, safeDIOverrides: safeDIOverrides.screen)
		        return Root(screen: screen)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsEachPlaceThroughADispatcherPerEnum_whenCallerSeesTypeThatFulfillsPlacesOfTwoCalledMocks() async throws {
		// D530-4: `Root`'s module sees `DefaultUserService`, which fulfills both places `Screen`'s public mock passes up, so it
		// fills both, each fill named after its mock and case, and dispatches `Screen`'s enum and each mock's to them.
		let modules = Self.sameLabelHoleModules(serviceNames: ["Service", "Settings"], screenMockGeneration: ".public") + [
			ModuleFixture(name: "Other", packageName: "other", swiftFileContent: [
				Self.sameLabelHoleRoot,
				"""
				import Core

				@Instantiable
				public final class DefaultUserService: UserService, Instantiable {
				    public init() {}
				}
				""",
			], dependencies: ["Core", "App"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Other"]?.generatedFiles == ["Other.swift": generatedFileHeader + """
		#if canImport(App)
		import App
		#endif
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screen: Screen.SafeDIOverrides = .init()
		        ) {
		            self.screen = screen
		        }

		        private(set) var screen: Screen.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_defaultUserServiceBuilder_Screen(_ scope: Screen.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case let .service(scope): return __safeDI_defaultUserServiceBuilder_Service(scope)
		                case let .settings(scope): return __safeDI_defaultUserServiceBuilder_Settings(scope)
		                }
		            }
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case .userService:
		                    let userService = AnyUserService(DefaultUserService())
		                    return userService
		                }
		            }
		            func __safeDI_defaultUserServiceBuilder_Settings(_ scope: Settings.SafeDIMockScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case .userService:
		                    let userService = AnyUserService(DefaultUserService())
		                    return userService
		                }
		            }
		            _ = Screen.__safeDI_Screen_mock_4A643395AAD25696.self // If this line does not compile, compile the code SafeDI generates for module App into App: under Bazel, add App's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.mock(defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Screen, safeDIOverrides: safeDIOverrides.screen)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Root(screen: screen)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Root.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicMocksTreeReachesAdditionalDirectoryDeclarationUnderTargetGraph() async {
		// M8.26: the callers compute `Service`'s public mock from the files the plugin's target graph lists, which leave
		// out the directory the configuration adds and its `Detail`, so for them `detail` is a hole.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:29: error: SafeDI cannot generate the public mock of `Service`: its signature depends on `Detail`, which is declared in a directory this module's `#SafeDIConfiguration` adds, and the modules that call the mock cannot see that declaration, so their calls would not match the mock. Declare `Detail` in a file of this module, or of a module it depends on.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					#SafeDIConfiguration(
					    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
					)
					""",
					"""
					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    public init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
				],
				additionalDirectorySwiftFileContent: [
					"""
					@Instantiable
					public struct Detail: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				pluginTargetGraph: { inputSwiftFilePaths in
					PluginTargetGraph(
						target: PluginTargetGraph.Target(moduleName: "App", packageID: "application", sourceFilePaths: inputSwiftFilePaths, dependencyModuleNames: []),
						dependencyTargets: [],
					)
				},
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingTheFulfiller_whenPublicMocksHoleIsFulfilledInAdditionalDirectoryUnderTargetGraph() async {
		// The callers see no type that fulfills `Gizmo`, so for them `gizmo` is a hole, while this run builds `DefaultGizmo`.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:29: error: SafeDI cannot generate the public mock of `Service`: its signature depends on `DefaultGizmo`, which is declared in a directory this module's `#SafeDIConfiguration` adds, and the modules that call the mock cannot see that declaration, so their calls would not match the mock. Declare `DefaultGizmo` in a file of this module, or of a module it depends on.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					#SafeDIConfiguration(
					    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
					)
					""",
					"""
					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    public init(gizmo: any Gizmo) {
					        self.gizmo = gizmo
					    }

					    @Instantiated let gizmo: any Gizmo
					}

					public protocol Gizmo {}
					""",
				],
				additionalDirectorySwiftFileContent: [
					"""
					@Instantiable(fulfillingAdditionalTypes: [Gizmo.self])
					public struct DefaultGizmo: Gizmo, Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				pluginTargetGraph: { inputSwiftFilePaths in
					PluginTargetGraph(
						target: PluginTargetGraph.Target(moduleName: "App", packageID: "application", sourceFilePaths: inputSwiftFilePaths, dependencyModuleNames: []),
						dependencyTargets: [],
					)
				},
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicMock_whenConsumerListsOnlyTheDeclaringModule() async throws {
		// M8.26b, cell 5: `App` cannot build `Service`'s tree, so it calls the public mock, whose signature is computed from
		// what `Core` sees, which includes `Base`: `Core`'s `.safedi` carries it, so `App`, which lists only `Core`, computes it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Base", packageName: "pkg", swiftFileContent: [
					"""
					@Instantiable
					public final class Analytics: Instantiable {
					    public init() {}
					}
					""",
				]),
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
					"""
					import Base

					@Instantiable
					package final class Session: Instantiable {
					    package init() {}
					}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    package init(analytics: Analytics, session: Session) {
					        self.analytics = analytics
					        self.session = session
					    }

					    @Instantiated let analytics: Analytics
					    @Instantiated let session: Session
					}
					""",
				], dependencies: ["Base"]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
				import Core

				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				"""], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Base)
		import Base
		#endif
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.service = service
		        }

		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Service.__safeDI_Service_mock_51799E6AA5E7B634.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Service", declaringModule: "Core"))
		        let service = Service.mock(safeDIOverrides: safeDIOverrides.service)
		        return Screen(service: service)
		    }
		}
		#endif
		"""])
	}

	@Test(arguments: [
		#"@Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let hole: AnyUserService"#,
		"@Instantiated let hole: Instantiator<Panel>",
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_movesPublicMockGuard_whenBuilderPassedUpBecomesSendable(holeDeclaration: String) async throws {
		let guardWhenHeldByValue = try await publicMockGuardName(ofScreenHolding: "Service", holeDeclaration: holeDeclaration)
		let guardWhenBuiltInSendableFunction = try await publicMockGuardName(ofScreenHolding: "SendableInstantiator<Service>", holeDeclaration: holeDeclaration)
		#expect(guardWhenHeldByValue != guardWhenBuiltInSendableFunction)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableBuilder_whenBuilderPassedUpIsCalledInSendableBuilderFunction() async throws {
		// Found by the public mock corpus (seed 56): `Screen` builds `Service` in a `@Sendable` builder function, which
		// captures the builder `Screen`'s mock passes up, so the mock takes it `@Sendable`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.holeModules(app: """
			import Core

			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(serviceBuilder: SendableInstantiator<Service>) {
			        self.serviceBuilder = serviceBuilder
			    }

			    @Instantiated let serviceBuilder: SendableInstantiator<Service>
			}
			"""),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            serviceBuilder: (@Sendable () -> Service.SafeDIOverrides)? = nil
		        ) {
		            self.analytics = analytics
		            self.serviceBuilder = serviceBuilder
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var serviceBuilder: (@Sendable () -> Service.SafeDIOverrides)?
		    }

		    static func mock(
		        defaultUserServiceBuilder: @escaping @Sendable (Service.SafeDIMockScope_DefaultUserService) -> AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        _ = Service.__safeDI_Service_mock_D6EB7379965966B0.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let __safeDI_serviceBuilder__safeDIBuilder = safeDIOverrides.serviceBuilder
		        @Sendable func __safeDI_serviceBuilder() -> Service {
		            Service.mock(defaultUserServiceBuilder: defaultUserServiceBuilder, analytics: analytics, safeDIOverrides: __safeDI_serviceBuilder__safeDIBuilder?() ?? .init())
		        }
		        let serviceBuilder = SendableInstantiator<Service>(__safeDI_serviceBuilder)
		        return Screen(serviceBuilder: serviceBuilder)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesRequiredParameter_whenTreeInstantiatesTypeThatCannotBeHole() async throws {
		// R7: only a type a nominal type could be is a hole. An array nothing fulfills, as a seam's tree reports it, is a
		// required parameter of the public mock, as an internal mock takes it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    public init(names: [String]) {
				        self.names = names
				    }

				    @Instantiated let names: [String]
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    public static func mock(
			        names: [String]
			    ) -> Service {
			        return Service(names: names)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_1E19B78A930879F1 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenTreeInstantiatesNarrowerTypeThatCannotBeHole() async {
		// R7: an array of an internal type nothing fulfills is a required parameter no public tier can take.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):3:29: error: SafeDI cannot generate the public mock of `Service`: its `public` tier, which `generateMock: .public` requires, cannot take `secrets: [Secret]`, which `Service` instantiates and no `@Instantiable` declaration this module sees fulfills, and cannot pass `nil` for it, since it is required. `Secret` is declared `internal`. Declare `Secret` `public`; or use `generateMock: .internal`.
			\(fixtures["Service.swift"]):1:1: note: `Secret` is declared `internal` here.
			\(fixtures["Service.swift"]):1:1-1:1: fixit: public\(" ")
			\(fixtures["Service.swift"]):9:5: note: `Service` instantiates `secrets: [Secret]` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					struct Secret {}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    init(secrets: [Secret]) {
					        self.secrets = secrets
					    }

					    @Instantiated let secrets: [Secret]
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – calling a public mock from another module

	@Test(arguments: [MultiModuleIntegration.moduleInfo, .swiftPackagePlugin])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicTierOfPublicMock_whenAnotherPackageCannotBuildItsTree(integration: MultiModuleIntegration) async throws {
		// M8.4: `App` cannot build `Service`'s tree (`TokenCache` and `FakeLogger` are `package`), so its mock calls
		// the public tier, passing what its tree provides, and `nil` for `session`, which the tier omits.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.canonicalModules(appCaller: Self.canonicalScreen),
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
		let pluginComment = integration.seamCallComment(type: "Service", declaringModule: "Core")
		let screenMock = """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            theme: (() -> Theme)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.theme = theme
		            self.service = service
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var theme: (() -> Theme)?
		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        let theme = if let safeDIBuilder = safeDIOverrides.theme { safeDIBuilder() } else { Theme() }
		        _ = Service.__safeDI_Service_mock_209346FEA041FD20.self\(pluginComment)
		        let service = Service.mock(analytics: analytics.instance, theme: theme, safeDIOverrides: safeDIOverrides.service)
		        return Screen(analytics: analytics, theme: theme, service: service)
		    }
		}
		#endif
		"""
		switch integration {
		case .moduleInfo:
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + imports + "\n\n" + screenMock])
		case .swiftPackagePlugin:
			#expect(output.modules["App"]?.generatedFiles == [
				"SafeDIMockConfiguration.swift": generatedFileHeader + imports + "\n\n",
				"Caller+SafeDIMock.swift": generatedFileHeader + imports + "\n\n" + screenMock,
			])
		}
		guard integration == .moduleInfo else { return }
		// M8.32, a stated divergence: the call hands `Service`'s mock the instance of `Screen`'s `analytics`, which the
		// mock wraps again, reading it as it does; the instance is the one the inline mock shares.
		try await expectValuesAgreeWithInlineMocks(
			of: Self.canonicalModules(appCaller: Self.canonicalScreen),
			output: output,
			probes: [DifferentialValueProbe("Screen.mock()")],
			exempting: [DifferentialValueDifference(
				probe: "Screen.mock()",
				path: ["Screen", "service", "analytics"],
				feature: "analytics: <2> LazilyInstantiated<Analytics> (already instantiated, instance read last)",
				knownRight: "analytics: <1> LazilyInstantiated<Analytics> (seen, first at Screen > analytics)",
			)],
		)
	}

	@Test(arguments: [MultiModuleIntegration.moduleInfo, .swiftPackagePlugin])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesInstanceOfPromotedWrapper_whenConsumerAndPublicMockBothReceiveItLazily(integration: MultiModuleIntegration) async throws {
		// EOU-1: `Screen` and `Service` both receive `analytics` lazily. `Screen`'s mock builds the wrapper at its root and
		// hands `Service`'s mock its instance, as it would hand the instance to `Service` inline, rather than `nil`, which
		// would build a second `Analytics`.
		let modules = [
			ModuleFixture(name: "Core", packageName: "corepkg", swiftFileContentByFilePath: ["Service.swift": """
			import SafeDI

			@Instantiable
			public final class Analytics: Instantiable {
			    public init() {}
			}

			@Instantiable
			final class TokenCache: Instantiable {
			    init() {}
			}

			@Instantiable(generateMock: .public)
			public struct Service: Instantiable {
			    init(analytics: LazilyInstantiated<Analytics>, tokenCache: TokenCache) {
			        self.analytics = analytics
			        self.tokenCache = tokenCache
			    }

			    @Received public let analytics: LazilyInstantiated<Analytics>
			    @Instantiated let tokenCache: TokenCache
			}
			"""]),
			ModuleFixture(name: "App", packageName: "apppkg", swiftFileContentByFilePath: ["Screen.swift": """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(analytics: LazilyInstantiated<Analytics>, service: Service) {
			        self.analytics = analytics
			        self.service = service
			    }

			    @Received let analytics: LazilyInstantiated<Analytics>
			    @Instantiated let service: Service
			}
			"""], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: integration, filesToDelete: &filesToDelete)
		let pluginComment = integration.seamCallComment(type: "Service", declaringModule: "Core")
		let screenMock = """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self\(pluginComment)
		        let service = Service.mock(analytics: analytics.instance, safeDIOverrides: safeDIOverrides.service)
		        return Screen(analytics: analytics, service: service)
		    }
		}
		#endif
		"""
		switch integration {
		case .moduleInfo:
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + screenMock])
		case .swiftPackagePlugin:
			#expect(output.modules["App"]?.generatedFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + screenMock)
		}
		guard integration == .moduleInfo else { return }
		// M8.32's stated divergence: the call reads the instance of `Screen`'s `analytics` when `Service`'s mock is built,
		// and the mock wraps it again; the instance is the one the inline mock shares.
		try await expectValuesAgreeWithInlineMocks(
			of: modules,
			output: output,
			probes: [DifferentialValueProbe("Screen.mock()")],
			exempting: [
				DifferentialValueDifference(
					probe: "Screen.mock()",
					path: ["Screen", "analytics"],
					feature: "analytics: <1> LazilyInstantiated<Analytics> (already instantiated, instance read last)",
					knownRight: "analytics: <1> LazilyInstantiated<Analytics> (instance read last)",
				),
				DifferentialValueDifference(
					probe: "Screen.mock()",
					path: ["Screen", "service", "analytics"],
					feature: "analytics: <2> LazilyInstantiated<Analytics> (instance read last)",
					knownRight: "analytics: <1> LazilyInstantiated<Analytics> (seen, first at Screen > analytics)",
				),
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsLazilyInstantiatedDependencyAsWrapperAtCallersRoot_whenCalledPublicMockBuildsItLazily() async throws {
		// O3 (corpus seed 36's shape): `Service`'s mock builds the `analytics` it receives lazily when passed `nil`.
		// `Screen`'s mock, which can build it, builds the wrapper once at its root, as the inline mock promotes it, and
		// passes its instance – M8.32's early read, the stated divergence – rather than an `Analytics` built eagerly.
		let modules = [
			ModuleFixture(name: "Core", packageName: "corepkg", swiftFileContentByFilePath: ["Service.swift": """
			import SafeDI

			@Instantiable
			public final class Analytics: Instantiable {
			    public init() {}
			}

			@Instantiable
			final class TokenCache: Instantiable {
			    init() {}
			}

			@Instantiable(generateMock: .public)
			public struct Service: Instantiable {
			    init(analytics: LazilyInstantiated<Analytics>, tokenCache: TokenCache) {
			        self.analytics = analytics
			        self.tokenCache = tokenCache
			    }

			    @Received public let analytics: LazilyInstantiated<Analytics>
			    @Instantiated let tokenCache: TokenCache
			}
			"""]),
			ModuleFixture(name: "App", packageName: "apppkg", swiftFileContentByFilePath: ["Screen.swift": """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(service: Service) {
			        self.service = service
			    }

			    @Instantiated let service: Service
			}
			"""], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(analytics: analytics.instance, safeDIOverrides: safeDIOverrides.service)
		        return Screen(service: service)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesOneInstance_whenConsumerReceivesOptionalWrapperOnlyIfAvailableThatPublicMockReceives() async throws {
		// EOU-1, the optional wrapper: `Screen` receives `analytics: LazilyInstantiated<Analytics>?` only if available and
		// `Service` requires the wrapper. `Screen`'s mock builds one `Analytics` and hands `Service`'s mock that instance.
		let modules = [
			ModuleFixture(name: "Core", packageName: "corepkg", swiftFileContentByFilePath: ["Service.swift": """
			import SafeDI

			@Instantiable
			public final class Analytics: Instantiable {
			    public init() {}
			}

			@Instantiable
			final class TokenCache: Instantiable {
			    init() {}
			}

			@Instantiable(generateMock: .public)
			public struct Service: Instantiable {
			    init(analytics: LazilyInstantiated<Analytics>, tokenCache: TokenCache) {
			        self.analytics = analytics
			        self.tokenCache = tokenCache
			    }

			    @Received public let analytics: LazilyInstantiated<Analytics>
			    @Instantiated let tokenCache: TokenCache
			}
			"""]),
			ModuleFixture(name: "App", packageName: "apppkg", swiftFileContentByFilePath: ["Screen.swift": """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(analytics: LazilyInstantiated<Analytics>?, service: Service) {
			        self.analytics = analytics
			        self.service = service
			    }

			    @Received(onlyIfAvailable: true) let analytics: LazilyInstantiated<Analytics>?
			    @Instantiated let service: Service
			}
			"""], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(analytics: analytics.instance, safeDIOverrides: safeDIOverrides.service)
		        return Screen(analytics: analytics, service: service)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsDependencyOnceAtCallersRoot_whenOneInstantiatorCallsPublicMockThatBuildsIt() async throws {
		// O3: `Service`'s mock builds the `analytics` it receives when passed `nil`. `Panel`'s mock can build it, so it builds
		// it once at its root and passes it to every `Service` its `Instantiator` makes, as the inline mock promotes it,
		// rather than letting each call build one of its own.
		let modules = [
			ModuleFixture(name: "Core", packageName: "core", swiftFileContentByFilePath: ["Service.swift": """
			import SafeDI

			@Instantiable
			public final class Analytics: Instantiable {
			    public init() {}
			}

			@Instantiable
			final class TokenCache: Instantiable {
			    init() {}
			}

			@Instantiable(generateMock: .public)
			public final class Service: Instantiable {
			    init(analytics: Analytics, tokenCache: TokenCache) {
			        self.analytics = analytics
			        self.tokenCache = tokenCache
			    }

			    @Received public let analytics: Analytics
			    @Instantiated let tokenCache: TokenCache
			}
			"""]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Panel.swift": """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public final class Panel: Instantiable {
			    public init(serviceBuilder: Instantiator<Service>) {
			        self.serviceBuilder = serviceBuilder
			    }

			    @Instantiated public let serviceBuilder: Instantiator<Service>
			}
			"""], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Panel {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            serviceBuilder: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.serviceBuilder = serviceBuilder
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var serviceBuilder: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Panel {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_serviceBuilder() -> Service {
		            Service.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.serviceBuilder)
		        }
		        let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
		        return Panel(serviceBuilder: serviceBuilder)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Panel.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenConsumerProvidesValueThatReachedTierOmits() async {
		// M2.23a: `App` reaches `Service`'s public tier, which omits `filter`, a type only `TokenCache`'s package
		// initializer mentions; `Screen` forwards `filter`, which the inline mock would hand `TokenCache`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):11:5: error: `Screen` provides `filter: [3 of Int]`, but the `public` mock SafeDI generated for `Service` in module `Core`, the narrowest one module `App` can call, does not take it: `Service.mock` takes `filter` only on its `package` tier, so this call would pass `nil` to `TokenCache`, which the inline mock would hand `filter`. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Core` or on a type that receives it is `package` (`TokenCache.init(filter:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `TokenCache.init(filter:)` to `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `filter` on this path.
			\(fixtures["Core"]!["Service.swift"]):9:5: note: `TokenCache` receives `filter: [3 of Int]?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
					import SafeDI

					@Instantiable
					package struct TokenCache: Instantiable {
					    package init(filter: [3 of Int]?) {
					        self.filter = filter
					    }

					    @Received(onlyIfAvailable: true) let filter: [3 of Int]?
					}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    package init(tokenCache: TokenCache) {
					        self.tokenCache = tokenCache
					    }

					    @Instantiated let tokenCache: TokenCache
					}
					"""]),
					ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
					import Core
					import SafeDI

					@Instantiable(generateMock: true)
					public struct Screen: Instantiable {
					    public init(filter: [3 of Int], service: Service) {
					        self.filter = filter
					        self.service = service
					    }

					    @Forwarded let filter: [3 of Int]
					    @Received let service: Service
					}
					"""], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWithoutOfferingToPassPackages_whenNeitherModuleIsToldItsPackageAndOmittedValueIsInternal() async {
		// M8.35: neither module is told a package, so neither has one, nothing is `package`, and `App` reaches the public
		// tier, which omits `filter`. Its tier is `internal`, which a `package` caller could not call either, so the error
		// does not offer to pass the packages.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):11:5: error: `Screen` provides `filter: [3 of Int]`, but the `public` mock SafeDI generated for `Service` in module `Core`, the narrowest one module `App` can call, does not take it: `Service.mock` takes `filter` only on its `internal` tier, so this call would pass `nil` to `TokenCache`, which the inline mock would hand `filter`. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Core` or on a type that receives it is `internal` (`TokenCache.init(filter:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `TokenCache.init(filter:)` to `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `filter` on this path.
			\(fixtures["Core"]!["Service.swift"]):9:5: note: `TokenCache` receives `filter: [3 of Int]?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
					import SafeDI

					@Instantiable
					struct TokenCache: Instantiable {
					    init(filter: [3 of Int]?) {
					        self.filter = filter
					    }

					    @Received(onlyIfAvailable: true) let filter: [3 of Int]?
					}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    init(tokenCache: TokenCache) {
					        self.tokenCache = tokenCache
					    }

					    @Instantiated let tokenCache: TokenCache
					}
					"""], omitsPackageName: true),
					ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
					import Core
					import SafeDI

					@Instantiable(generateMock: true)
					public struct Screen: Instantiable {
					    public init(filter: [3 of Int], service: Service) {
					        self.filter = filter
					        self.service = service
					    }

					    @Forwarded let filter: [3 of Int]
					    @Received let service: Service
					}
					"""], dependencies: ["Core"], omitsPackageName: true),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingToPassPackage_whenConsumerToldNoPackageProvidesValueThatPackageTierTakes() async {
		// `App` is compiled in `Core`'s package `Shop` but runs without its package, so it has none and reaches only the
		// public tier, which omits `filter`. The `package` tier takes it, so telling SafeDI `App`'s package would do.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):11:5: error: `Screen` provides `filter: [3 of Int]`, but the `public` mock SafeDI generated for `Service` in module `Core`, the narrowest one module `App` can call, does not take it: `Service.mock` takes `filter` only on its `package` tier, so this call would pass `nil` to `TokenCache`, which the inline mock would hand `filter`. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Core` or on a type that receives it is `package` (`TokenCache.init(filter:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `TokenCache.init(filter:)` to `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; pass module `App`'s package to SafeDI (`package_name` on `safedi_swift_library`, `--package-name`) if it is compiled with `-package-name`; or stop providing `filter` on this path.
			\(fixtures["Core"]!["Service.swift"]):9:5: note: `TokenCache` receives `filter: [3 of Int]?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Service.swift": """
					import SafeDI

					@Instantiable
					package struct TokenCache: Instantiable {
					    package init(filter: [3 of Int]?) {
					        self.filter = filter
					    }

					    @Received(onlyIfAvailable: true) let filter: [3 of Int]?
					}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    package init(tokenCache: TokenCache) {
					        self.tokenCache = tokenCache
					    }

					    @Instantiated let tokenCache: TokenCache
					}
					"""]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Screen.swift": """
					import Core
					import SafeDI

					@Instantiable(generateMock: true)
					public struct Screen: Instantiable {
					    public init(filter: [3 of Int], service: Service) {
					        self.filter = filter
					        self.service = service
					    }

					    @Forwarded let filter: [3 of Int]
					    @Received let service: Service
					}
					"""], dependencies: ["Core"], omitsPackageName: true),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsPublicMockFirst_whenProviderOfOmittedValueIsDeclaredFirstAndReceivesItOnlyIfAvailable() async throws {
		// M2.23c, `filter` declared first: `Hub.Filter`'s receive of `service` orders `service` first, so the leaf's soft
		// edge on `filter` would close a cycle and is dropped; `filter` is not yet built where `service` is, and no
		// value is omitted, as the inline mock passes `TokenCache` `nil`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.softEdgeModules(screenDeclaresFilterFirst: true),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Hubs)
		import Hubs
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            service: Service.SafeDIOverrides = .init(),
		            filter: ((Service?) -> Hub.Filter)? = nil
		        ) {
		            self.service = service
		            self.filter = filter
		        }

		        private(set) var service: Service.SafeDIOverrides
		        private(set) var filter: ((Service?) -> Hub.Filter)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Service.__safeDI_Service_mock_4DBCFD53033F6143.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(safeDIOverrides: safeDIOverrides.service)
		        let filter = if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder(service) } else { Hub.Filter(service: service) }
		        return Screen(filter: filter, service: service)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicMockIsDeclaredBeforeProviderOfValueItsTierOmits() async {
		// M2.23c, `service` declared first: the leaf's soft edge on `filter` is kept, so `filter` is built first, and
		// the call would pass `nil` for the value the inline mock hands `TokenCache`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):13:5: error: `Screen` provides `filter: Hub.Filter`, but the `public` mock SafeDI generated for `Service` in module `Core`, the narrowest one module `App` can call, does not take it: `Service.mock` takes `filter` only on its `package` tier, so this call would pass `nil` to `TokenCache`, which the inline mock would hand `filter`. `Hub.Filter` is `package` as far as SafeDI can tell: it is declared inside an extension of `Hub`, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `package` (`TokenCache.init(filter:)`). If `Hub` can be `public`, spell the extension's access level (`public extension Hub { … }`, dropping the modifier on `Filter` that Swift then reports as redundant; the compiler rejects a level wider than `Hub`'s), or declare `Filter` in `Hub`'s body or at top level; mention `Hub.Filter` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `filter` on this path.
			\(fixtures["Core"]!["Service.swift"]):10:5: note: `TokenCache` receives `filter: Hub.Filter?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.softEdgeModules(screenDeclaresFilterFirst: false),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesValueDownChainOfPublicMocks_whenOuterPublicMockTakesWhatInnerCallPasses() async throws {
		// M8.33: `Dashboard`'s mock calls `Service`'s and does not provide `analytics`, so it takes `analytics: Analytics? =
		// nil` on its public tier, builds one once when passed `nil` (O3), and passes it on; `AppRoot` passes the instance
		// it holds, so one instance is shared.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
				import SafeDI

				@Instantiable
				public final class Analytics: Instantiable {
				    public init() {}
				}

				@Instantiable
				package struct TokenCache: Instantiable {
				    package init(analytics: Analytics) {
				        self.analytics = analytics
				    }

				    @Received let analytics: Analytics
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    package init(analytics: Analytics, tokenCache: TokenCache) {
				        self.analytics = analytics
				        self.tokenCache = tokenCache
				    }

				    @Received let analytics: Analytics
				    @Instantiated let tokenCache: TokenCache
				}
				"""]),
				ModuleFixture(name: "Feature", packageName: "feature", swiftFileContentByFilePath: ["Dashboard.swift": """
				import Core
				import SafeDI

				@Instantiable(generateMock: .public)
				public struct Dashboard: Instantiable {
				    package init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				"""], dependencies: ["Core"]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["AppRoot.swift": """
				import Core
				import Feature
				import SafeDI

				@Instantiable(generateMock: true)
				public struct AppRoot: Instantiable {
				    public init(analytics: LazilyInstantiated<Analytics>, dashboard: Dashboard) {
				        self.analytics = analytics
				        self.dashboard = dashboard
				    }

				    @Instantiated let analytics: LazilyInstantiated<Analytics>
				    @Instantiated let dashboard: Dashboard
				}
				"""], dependencies: ["Core", "Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Dashboard {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        public private(set) var analytics: (() -> Analytics)?
		        public private(set) var service: Service.SafeDIOverrides
		    }

		    public static func mock(
		        analytics: Analytics? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Dashboard {
		        let analytics = if let analytics { analytics } else if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        return Dashboard(service: service)
		    }
		}

		extension Dashboard {
		    public enum __safeDI_Dashboard_mock_81027395670D1D21 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension AppRoot {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            dashboard: Dashboard.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.dashboard = dashboard
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var dashboard: Dashboard.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> AppRoot {
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        _ = Dashboard.__safeDI_Dashboard_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let dashboard = Dashboard.mock(analytics: analytics.instance, safeDIOverrides: safeDIOverrides.dashboard)
		        return AppRoot(analytics: analytics, dashboard: dashboard)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_letsEachPublicMockBuildDependencyItsCallerCannotName_whenTwoPublicMocksReceiveIt() async throws {
		// M8.9b: each public tier omits the package `session`, which `App` cannot name, so each call passes nothing for it
		// and each public mock builds its own `Session`, where an inline mock would share one (a stated divergence).
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
				import SafeDI

				@Instantiable
				package struct Session: Instantiable {
				    package init() {}
				}

				@Instantiable
				package struct TokenCache: Instantiable {
				    package init(session: Session) {
				        self.session = session
				    }

				    @Received let session: Session
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    package init(tokenCache: TokenCache) {
				        self.tokenCache = tokenCache
				    }

				    @Instantiated let tokenCache: TokenCache
				}

				@Instantiable(generateMock: .public)
				public struct Vault: Instantiable {
				    package init(tokenCache: TokenCache) {
				        self.tokenCache = tokenCache
				    }

				    @Instantiated let tokenCache: TokenCache
				}
				"""]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
				import Core
				import SafeDI

				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(service: Service, vault: Vault) {
				        self.service = service
				        self.vault = vault
				    }

				    @Received let service: Service
				    @Received let vault: Vault
				}
				"""], dependencies: ["Core"]),
			],
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
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            service: Service.SafeDIOverrides = .init(),
		            vault: Vault.SafeDIOverrides = .init()
		        ) {
		            self.service = service
		            self.vault = vault
		        }

		        private(set) var service: Service.SafeDIOverrides
		        private(set) var vault: Vault.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Service.__safeDI_Service_mock_B3677AD76727096E.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(safeDIOverrides: safeDIOverrides.service)
		        _ = Vault.__safeDI_Vault_mock_B3677AD76727096E.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let vault = Vault.mock(safeDIOverrides: safeDIOverrides.vault)
		        return Screen(service: service, vault: vault)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesParameterOnNoTier_whenPublicMockTreeCallsTierThatOmitsIt() async throws {
		// M8.33d, `AppRoot` holding nothing for `filter`: `Outer` reaches `Service`'s public tier, which omits `filter`,
		// so no tier of `Outer`'s mock takes it, and `App` calls `Outer.mock()`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.chainModules(appRootForwardsFilter: false),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Outer {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.service = service
		        }

		        public private(set) var service: Service.SafeDIOverrides
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        _ = Service.__safeDI_Service_mock_5BD7973A2F881650.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(safeDIOverrides: safeDIOverrides.service)
		        return Outer(service: service)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_mock_51799E6AA5E7B634 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Mid)
		import Mid
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension AppRoot {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            outer: Outer.SafeDIOverrides = .init()
		        ) {
		            self.outer = outer
		        }

		        private(set) var outer: Outer.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> AppRoot {
		        _ = Outer.__safeDI_Outer_mock_51799E6AA5E7B634.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let outer = Outer.mock(safeDIOverrides: safeDIOverrides.outer)
		        return AppRoot(outer: outer)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenConsumerProvidesValueNoTierOfCalledPublicMockTakes() async {
		// M8.33d, `AppRoot` forwarding `filter`: the inline mock would hand it to `TokenCache`, deep in `Outer`'s tree,
		// but no tier of `Outer`'s mock takes it, since the tier of `Service`'s mock that `Outer`'s tree calls omits it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["AppRoot.swift"]):12:5: error: `AppRoot` provides `filter: [3 of Int]`, but no mock SafeDI generated for `Outer` takes it: `Outer`'s mock tree calls the `public` mock SafeDI generated for `Service` in module `Core`, the narrowest one module `Mid` can call, which takes `filter` only on its `package` tier, so calling it would pass `nil` to `TokenCache`, which the inline mock would hand `filter`. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Core` or on a type that receives it is `package` (`TokenCache.init(filter:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `TokenCache.init(filter:)` to `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `filter` on this path.
			\(fixtures["Core"]!["Service.swift"]):9:5: note: `TokenCache` receives `filter: [3 of Int]?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.chainModules(appRootForwardsFilter: true),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenConsumerCallsPublicMockGeneratedUnderAnotherMockCondition() async {
		// M11.2: `Core` generates its mocks under `TESTING`, which this run reads from its module info; `App`'s mocks
		// compile under `DEBUG`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):10:5: error: `Service.mock()` is generated under `#if TESTING` in `Core`, but this module's mocks compile under `#if DEBUG`. Give both modules one `mockConditionalCompilation`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.mockConditionModules(appMockCondition: nil),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicMock_whenPluginReadsDeclaringModulesConfigurationThatNamesTheSameMockCondition() async throws {
		// M11.5b: under the plugin, the condition is read from the configuration in a file of `Core`, which names
		// `TESTING`, as `App`'s does, so the call is generated under `TESTING`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.mockConditionModules(appMockCondition: "TESTING"),
			integration: .swiftPackagePlugin,
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
		#expect(output.modules["App"]?.generatedFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + imports + """


			#if TESTING
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: Service.SafeDIOverrides = .init()
			        ) {
			            self.service = service
			        }

			        private(set) var service: Service.SafeDIOverrides
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        _ = Service.__safeDI_Service_mock_51799E6AA5E7B634.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
			        let service = Service.mock(safeDIOverrides: safeDIOverrides.service)
			        return Screen(service: service)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + imports + "\n\n",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenConsumerHoldsHandWrittenMockNamedMockForTypeWithPublicMock() async {
		// M9.2: `App` reaches `Service`, whose public `mock()` `Core` generates, while holding a hand-written `mock` for it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):15:5: error: `Service` has a public `mock()` generated by `Core`; a hand-written `mock` here makes every call ambiguous. Give it another name and pass it as `customMockName`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
					import SafeDI

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    public init() {}
					}
					"""]),
					ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
					import Core
					import SafeDI

					@Instantiable(generateMock: true)
					public struct Screen: Instantiable {
					    public init(service: Service) {
					        self.service = service
					    }

					    @Received let service: Service
					}

					@Instantiable(mockOnly: true)
					extension Service {
					    public static func mock(name: String = "") -> Service { Service() }
					}
					"""], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSuggestingPublicMock_whenConsumerCannotBuildTreeOfTypeWithoutOne() async {
		// M8.6: `Service` has no public mock, and `App` cannot construct `TokenCache` in its tree.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Service.swift"]):5:5: error: `TokenCache`’s initializer is `package`, so the mock of `Screen`, generated in module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix, or give `Service` a public mock: `generateMock: .public`, or a hand-written public `mock`.
			\(fixtures["Core"]!["Service.swift"]):5:5-5:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
					import SafeDI

					@Instantiable
					public struct TokenCache: Instantiable {
					    package init() {}
					}

					@Instantiable
					public struct Service: Instantiable {
					    public init(tokenCache: TokenCache) {
					        self.tokenCache = tokenCache
					    }

					    @Instantiated let tokenCache: TokenCache
					}
					"""]),
					ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
					import Core
					import SafeDI

					@Instantiable(generateMock: true)
					public struct Screen: Instantiable {
					    public init(service: Service) {
					        self.service = service
					    }

					    @Received let service: Service
					}
					"""], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsPublicMockOverridesThroughSendableClosure_whenCallIsInSendableBuilder() async throws {
		// M8.20: `Wrapper` is built inside a `@Sendable` builder function, which cannot capture `Service.SafeDIOverrides`,
		// so `Wrapper`'s configuration holds a `@Sendable` closure that returns it, read into a local before the function.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.canonicalModules(appCaller: Self.canonicalBoard),
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
		extension Board {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            wrapperBuilder: Wrapper.SafeDIMockConfiguration = .init()
		        ) {
		            self.wrapperBuilder = wrapperBuilder
		        }

		        private(set) var wrapperBuilder: Wrapper.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        let __safeDI_wrapperBuilder__wrapperBuilder_analytics_safeDIBuilder = safeDIOverrides.wrapperBuilder.analytics
		        let __safeDI_wrapperBuilder__wrapperBuilder_service_safeDIBuilder = safeDIOverrides.wrapperBuilder.service
		        let __safeDI_wrapperBuilder__safeDIBuilder = safeDIOverrides.wrapperBuilder.safeDIBuilder
		        @Sendable func __safeDI_wrapperBuilder() -> Wrapper {
		            func __safeDI_analytics() -> Analytics {
		                if let safeDIBuilder = __safeDI_wrapperBuilder__wrapperBuilder_analytics_safeDIBuilder { safeDIBuilder() } else { Analytics() }
		            }
		            let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		            _ = Service.__safeDI_Service_mock_209346FEA041FD20.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let service = Service.mock(analytics: analytics.instance, theme: nil, safeDIOverrides: __safeDI_wrapperBuilder__wrapperBuilder_service_safeDIBuilder?() ?? .init())
		            return if let safeDIBuilder = __safeDI_wrapperBuilder__safeDIBuilder { safeDIBuilder(analytics, service) } else { Wrapper(analytics: analytics, service: service) }
		        }
		        let wrapperBuilder = SendableInstantiator<Wrapper>(__safeDI_wrapperBuilder)
		        return Board(wrapperBuilder: wrapperBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Wrapper {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            analytics: (@Sendable () -> Analytics)? = nil,
		            service: (@Sendable () -> Service.SafeDIOverrides)? = nil,
		            _ safeDIBuilder: (@Sendable (LazilyInstantiated<Analytics>, Service) -> Wrapper)? = nil
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.safeDIBuilder = safeDIBuilder
		        }

		        private(set) var analytics: (@Sendable () -> Analytics)?
		        private(set) var service: (@Sendable () -> Service.SafeDIOverrides)?
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        private(set) var safeDIBuilder: (@Sendable (LazilyInstantiated<Analytics>, Service) -> Wrapper)?
		    }
		}
		#endif
		""" + "\n"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicMockInsideInstantiator_whenConsumerInstantiatesInstantiatorOfType() async throws {
		// M8.15: the builder function an `Instantiator<Service>` calls is the public mock's call.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.canonicalModules(appCaller: """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(analytics: LazilyInstantiated<Analytics>, serviceBuilder: Instantiator<Service>) {
			        self.analytics = analytics
			        self.serviceBuilder = serviceBuilder
			    }

			    @Instantiated let analytics: LazilyInstantiated<Analytics>
			    @Instantiated let serviceBuilder: Instantiator<Service>
			}
			"""),
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
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            serviceBuilder: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.serviceBuilder = serviceBuilder
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var serviceBuilder: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        _ = Service.__safeDI_Service_mock_209346FEA041FD20.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_serviceBuilder() -> Service {
		            Service.mock(analytics: analytics.instance, theme: nil, safeDIOverrides: safeDIOverrides.serviceBuilder)
		        }
		        let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
		        return Screen(analytics: analytics, serviceBuilder: serviceBuilder)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_wrapsPublicMockCallInErasedType_whenConsumerReachesItThroughErasure() async throws {
		// M8.19, M8.20b: `Screen` reaches `Service`, whose tree `App` cannot build, as a constant erased to `AnyServicing`,
		// through an `ErasedInstantiator` and through a `SendableErasedInstantiator`: each call of the public mock is
		// wrapped in the erased type, as an inline construction is.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
					"""
					@Instantiable
					public final class Analytics: Instantiable, Sendable {
					    public init() {}
					}

					@Instantiable
					package final class Session: Instantiable, Sendable {
					    package init(analytics: Analytics) {
					        self.analytics = analytics
					    }

					    @Received let analytics: Analytics
					}

					@Instantiable(generateMock: .public)
					public final class Service: Instantiable, Sendable {
					    package init(analytics: Analytics, session: Session) {
					        self.analytics = analytics
					        self.session = session
					    }

					    @Received let analytics: Analytics
					    @Instantiated let session: Session
					}

					public protocol Servicing: Sendable {}

					extension Service: Servicing {}

					public struct AnyServicing: Servicing {
					    public init(_ servicing: any Servicing) {}
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
					"""
					import Core

					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(analytics: Analytics, constant: AnyServicing, erased: ErasedInstantiator<(), AnyServicing>, sendableErased: SendableErasedInstantiator<(), AnyServicing>) {
					        self.analytics = analytics
					        self.constant = constant
					        self.erased = erased
					        self.sendableErased = sendableErased
					    }

					    @Instantiated let analytics: Analytics
					    @Instantiated(fulfilledByType: "Service", erasedToConcreteExistential: true) let constant: AnyServicing
					    @Instantiated(fulfilledByType: "Service", erasedToConcreteExistential: true) let erased: ErasedInstantiator<(), AnyServicing>
					    @Instantiated(fulfilledByType: "Service", erasedToConcreteExistential: true) let sendableErased: SendableErasedInstantiator<(), AnyServicing>
					}
					""",
				], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            constant: Service.SafeDIOverrides = .init(),
		            erased: Service.SafeDIOverrides = .init(),
		            sendableErased: (@Sendable () -> Service.SafeDIOverrides)? = nil
		        ) {
		            self.analytics = analytics
		            self.constant = constant
		            self.erased = erased
		            self.sendableErased = sendableErased
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var constant: Service.SafeDIOverrides
		        private(set) var erased: Service.SafeDIOverrides
		        private(set) var sendableErased: (@Sendable () -> Service.SafeDIOverrides)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let constant = AnyServicing(Service.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.constant))
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_erased() -> AnyServicing {
		            AnyServicing(Service.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.erased))
		        }
		        let erased = ErasedInstantiator<(), AnyServicing>(__safeDI_erased)
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let __safeDI_sendableErased__safeDIBuilder = safeDIOverrides.sendableErased
		        @Sendable func __safeDI_sendableErased() -> AnyServicing {
		            AnyServicing(Service.mock(analytics: analytics, safeDIOverrides: __safeDI_sendableErased__safeDIBuilder?() ?? .init()))
		        }
		        let sendableErased = SendableErasedInstantiator<(), AnyServicing>(__safeDI_sendableErased)
		        return Screen(analytics: analytics, constant: constant, erased: erased, sendableErased: sendableErased)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesConsumersOwnReceive_whenConsumerAndPublicMockBothReceiveLabelOnlyIfAvailable() async throws {
		// M8.13: `Screen` receives `theme` only if available itself, so its mock takes `theme` as an override, which the
		// call hands `Service`'s mock, as the inline mock hands it `TokenCache`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.canonicalModules(appCaller: """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(theme: Theme?, service: Service) {
			        self.theme = theme
			        self.service = service
			    }

			    @Received(onlyIfAvailable: true) let theme: Theme?
			    @Received let service: Service
			}
			"""),
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
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            theme: Theme? = nil
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.theme = theme
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		        private(set) var theme: Theme?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let theme: Theme? = safeDIOverrides.theme
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        _ = Service.__safeDI_Service_mock_209346FEA041FD20.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(analytics: analytics.instance, theme: theme, safeDIOverrides: safeDIOverrides.service)
		        return Screen(theme: theme, service: service)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingDeclaringModuleIsUnknown_whenRunThatNamesNoModuleCannotBuildTreeOfTypeWithPublicMock() async {
		// M8.24: without a target graph or a module name – as the Xcode project plugin runs the tool – `App` reads
		// `Core`'s files without knowing which module declares `Service`, so `Service`'s public mock cannot be called, and
		// its tree is built inline, where `TokenCache` is `internal`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = NormalizedFilePath(fixtures["Core"]!.compilerPath(of: "Service.swift")).path
			return """
			\(servicePath):4:1: error: `Service` has a public `mock()`, but SafeDI does not know which module declares `Service`, so this run cannot call it, and `TokenCache` is `internal`. Build these mocks in a Swift package target, or give this run the module info of the module that declares `Service`, written with `--module-name`.
			\(servicePath):5:5: error: `Service` has a public `mock()`, but SafeDI does not know which module declares `Service`, so this run cannot call it, and `TokenCache`’s initializer is `internal`. Build these mocks in a Swift package target, or give this run the module info of the module that declares `Service`, written with `--module-name`.
			\(servicePath):10:5: error: `Service` has a public `mock()`, but SafeDI does not know which module declares `Service`, so this run cannot call it, and `Service`’s initializer is `internal`. Build these mocks in a Swift package target, or give this run the module info of the module that declares `Service`, written with `--module-name`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.unknownModuleModules(omitsCoreModuleName: false),
				integration: .swiftPackagePlugin,
				writesTargetGraph: false,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingDeclaringModuleIsUnknown_whenRunThatNamesNoModuleReadsTypeWithPublicMockFromAdditionalDirectory() async {
		// M8.24 as the Xcode project plugin runs it: the target reads `Service` through `additionalDirectoriesToInclude`,
		// which no module name covers, so `Service`'s public mock cannot be called, and its tree is built inline, where
		// `TokenCache` is `internal`.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["AdditionalDirectory/TokenCache.swift"]):2:1: error: `Service` has a public `mock()`, but SafeDI does not know which module declares `Service`, so this run cannot call it, and `TokenCache` is `internal`. Build these mocks in a Swift package target, or give this run the module info of the module that declares `Service`, written with `--module-name`.
			\(fixtures["AdditionalDirectory/TokenCache.swift"]):3:5: error: `Service` has a public `mock()`, but SafeDI does not know which module declares `Service`, so this run cannot call it, and `TokenCache`’s initializer is `internal`. Build these mocks in a Swift package target, or give this run the module info of the module that declares `Service`, written with `--module-name`.
			\(fixtures["AdditionalDirectory/TokenCache.swift"]):8:5: error: `Service` has a public `mock()`, but SafeDI does not know which module declares `Service`, so this run cannot call it, and `Service`’s initializer is `internal`. Build these mocks in a Swift package target, or give this run the module info of the module that declares `Service`, written with `--module-name`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					#SafeDIConfiguration(
					    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
					)
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Screen: Instantiable {
					    public init(service: Service) {
					        self.service = service
					    }

					    @Received let service: Service
					}
					""",
				],
				additionalDirectorySwiftFileContent: [
					"""
					@Instantiable
					struct TokenCache: Instantiable {
					    init() {}
					}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    init(tokenCache: TokenCache) {
					        self.tokenCache = tokenCache
					    }

					    @Instantiated let tokenCache: TokenCache
					}
					""",
				],
				pluginInvocation: .scanWhilePlanning(reportsFixtureDirectoryThroughSymbolicLink: false),
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicMock_whenRunThatNamesNoModuleReadsModuleInfoNamingDeclaringModule() async throws {
		// M8.24's modules, with `App`'s run given no module name: `Core`'s module info names `Core`, so SafeDI knows which
		// module declares `Service`, and `Screen`'s mock calls its public mock rather than building its tree.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.unknownModuleModules(omitsCoreModuleName: false, omitsAppModuleName: true),
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
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.service = service
		        }

		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Service.__safeDI_Service_mock_51799E6AA5E7B634.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(safeDIOverrides: safeDIOverrides.service)
		        return Screen(service: service)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicMock_whenTargetGraphNamesModuleOfTypeWithPublicMock() async throws {
		// M8.24's modules built with the target graph the SwiftPM plugin writes: `Core` is known, so `Screen`'s mock calls
		// `Service`'s public mock rather than building its tree, where `TokenCache` is `internal`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.unknownModuleModules(omitsCoreModuleName: false),
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)

		let header = generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""
		#expect(output.modules["App"]?.generatedFiles == [
			"Screen+SafeDIMock.swift": header + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: Service.SafeDIOverrides = .init()
			        ) {
			            self.service = service
			        }

			        private(set) var service: Service.SafeDIOverrides
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        _ = Service.__safeDI_Service_mock_51799E6AA5E7B634.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
			        let service = Service.mock(safeDIOverrides: safeDIOverrides.service)
			        return Screen(service: service)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": header,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicMock_whenConsumerCannotCallTypesCustomMock() async throws {
		// A type whose public mock calls its `customMockName` method is built inline with that method where the consumer
		// can call it; `App` cannot call the `internal` `customMock`, so it calls the public `mock()`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
				import SafeDI

				@Instantiable(generateMock: .public, customMockName: "customMock")
				public final class Service: Instantiable {
				    public init() {}

				    static func customMock() -> Service {
				        Service()
				    }
				}
				"""]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
				import Core
				import SafeDI

				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Received let service: Service
				}
				"""], dependencies: ["Core"]),
			],
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
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            service: (() -> Service)? = nil
		        ) {
		            self.service = service
		        }

		        private(set) var service: (() -> Service)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Service.__safeDI_Service_mock_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service.mock() }
		        return Screen(service: service)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicMock_whenConsumerCannotBuildDependencyTypesTreeReceives() async throws {
		// `App` can construct `Service` itself, but not `Space.Shelf`, which `Service`'s tree receives and an inline mock
		// would build beside it, so it calls the public `mock()`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
				import SafeDI

				public enum Space {}

				public extension Space {
				    @Instantiable
				    final class Shelf: Instantiable {
				        init() {}
				    }
				}

				@Instantiable(generateMock: .public)
				public final class Service: Instantiable {
				    package init(shelf: Space.Shelf) {
				        self.shelf = shelf
				    }

				    @Received let shelf: Space.Shelf
				}
				"""]),
				ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Screen.swift": """
				import Core
				import SafeDI

				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				"""], dependencies: ["Core"]),
			],
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
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.service = service
		        }

		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Service.__safeDI_Service_mock_CBCD36FF0797CB15.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(shelf: nil, safeDIOverrides: safeDIOverrides.service)
		        return Screen(service: service)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsSharedDependencyOnceForEveryCall_whenTwoPublicMocksBuildIt() async throws {
		// M8.8b: both public mocks build `analytics` when passed `nil`, and the inline mock would share the one it promotes,
		// so `App`'s mock builds it once and passes it to both calls.
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
			import SafeDI

			@Instantiable
			public final class Analytics: Instantiable {
			    public init() {}
			}

			@Instantiable
			package struct TokenCache: Instantiable {
			    package init() {}
			}

			@Instantiable(generateMock: .public)
			public struct Service: Instantiable {
			    package init(analytics: Analytics, tokenCache: TokenCache) {
			        self.analytics = analytics
			        self.tokenCache = tokenCache
			    }

			    @Received let analytics: Analytics
			    @Instantiated let tokenCache: TokenCache
			}

			@Instantiable(generateMock: .public)
			public struct Vault: Instantiable {
			    package init(analytics: Analytics, tokenCache: TokenCache) {
			        self.analytics = analytics
			        self.tokenCache = tokenCache
			    }

			    @Received let analytics: Analytics
			    @Instantiated let tokenCache: TokenCache
			}
			"""]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(service: Service, vault: Vault) {
			        self.service = service
			        self.vault = vault
			    }

			    @Received let service: Service
			    @Received let vault: Vault
			}
			"""], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules,
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
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            vault: Vault.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.vault = vault
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		        private(set) var vault: Vault.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        _ = Vault.__safeDI_Vault_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let vault = Vault.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.vault)
		        return Screen(service: service, vault: vault)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsSharedDependencyOnceThroughItsPublicMock_whenCallingModuleCannotConstructIt() async throws {
		// The Manual's remedy for a dependency the calling module cannot construct, which each public mock call would
		// otherwise build: give it a public mock of its own, so the calling mock builds it once and passes it to every call.
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
			import SafeDI

			@Instantiable(generateMock: .public)
			public final class Analytics: Instantiable {
			    package init() {}
			}

			@Instantiable(generateMock: .public)
			public struct Service: Instantiable {
			    package init(analytics: Analytics) {
			        self.analytics = analytics
			    }

			    @Received let analytics: Analytics
			}

			@Instantiable(generateMock: .public)
			public struct Vault: Instantiable {
			    package init(analytics: Analytics) {
			        self.analytics = analytics
			    }

			    @Received let analytics: Analytics
			}
			"""]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(service: Service, vault: Vault) {
			        self.service = service
			        self.vault = vault
			    }

			    @Received let service: Service
			    @Received let vault: Vault
			}
			"""], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules,
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
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            vault: Vault.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.vault = vault
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		        private(set) var vault: Vault.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Analytics.__safeDI_Analytics_mock_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics.mock() }
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        _ = Vault.__safeDI_Vault_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let vault = Vault.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.vault)
		        return Screen(service: service, vault: vault)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	/// `Screen`'s mock builds the received `filter` beside `Screen`, and `AppFilter` receives `service`, which `Screen` creates: the call of `Service`'s public mock is passed `Screen`'s `analytics`, as it is without the `filter`.
	@Test
	mutating func generate_passesPublicMockValueItsTreeCreates_whenMockBuildsReceivedDependencyBesideMockedType() async throws {
		let modules = Self.receivedFilterModules(serviceReceivesAnalytics: .required)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            filter: ((Service) -> FilterProtocol)? = nil
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.filter = filter
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		        private(set) var filter: ((Service) -> FilterProtocol)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        let filter: FilterProtocol = if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder(service) } else { AppFilter(service: service) }
		        return Screen(analytics: analytics, service: service, filter: filter)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	/// As `generate_passesPublicMockValueItsTreeCreates_whenMockBuildsReceivedDependencyBesideMockedType`, with `Service` receiving `analytics` only if available.
	@Test
	mutating func generate_passesPublicMockValueItsTreeCreates_whenMockBuildsReceivedDependencyBesideMockedTypeAndPublicMockReceivesItOnlyIfAvailable() async throws {
		let modules = Self.receivedFilterModules(serviceReceivesAnalytics: .onlyIfAvailable)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            filter: ((Service) -> FilterProtocol)? = nil
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.filter = filter
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		        private(set) var filter: ((Service) -> FilterProtocol)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        let filter: FilterProtocol = if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder(service) } else { AppFilter(service: service) }
		        return Screen(analytics: analytics, service: service, filter: filter)
		    }
		}
		#endif
		"""])
	}

	/// As `generate_passesPublicMockValueItsTreeCreates_whenMockBuildsReceivedDependencyBesideMockedType`, with `Service` receiving `analytics` as a `LazilyInstantiated`.
	@Test
	mutating func generate_passesPublicMockValueItsTreeCreates_whenMockBuildsReceivedDependencyBesideMockedTypeAndPublicMockReceivesItLazily() async throws {
		let modules = Self.receivedFilterModules(serviceReceivesAnalytics: .lazilyInstantiated)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            filter: ((Service) -> FilterProtocol)? = nil
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.filter = filter
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		        private(set) var filter: ((Service) -> FilterProtocol)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(analytics: analytics.instance, safeDIOverrides: safeDIOverrides.service)
		        let filter: FilterProtocol = if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder(service) } else { AppFilter(service: service) }
		        return Screen(analytics: analytics, service: service, filter: filter)
		    }
		}
		#endif
		"""])
	}

	/// As `generate_passesPublicMockValueItsTreeCreates_whenMockBuildsReceivedDependencyBesideMockedType`, with `Service` receiving an `Instantiator<Analytics>`.
	@Test
	mutating func generate_passesPublicMockValueItsTreeCreates_whenMockBuildsReceivedDependencyBesideMockedTypeAndPublicMockReceivesInstantiator() async throws {
		let modules = Self.receivedFilterModules(serviceReceivesAnalytics: .instantiator)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analyticsBuilder: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            filter: ((Service) -> FilterProtocol)? = nil
		        ) {
		            self.analyticsBuilder = analyticsBuilder
		            self.service = service
		            self.filter = filter
		        }

		        private(set) var analyticsBuilder: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		        private(set) var filter: ((Service) -> FilterProtocol)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_analyticsBuilder() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analyticsBuilder { safeDIBuilder() } else { Analytics() }
		        }
		        let analyticsBuilder = Instantiator<Analytics>(__safeDI_analyticsBuilder)
		        _ = Service.__safeDI_Service_mock_0B1B0F45EEE6C284.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(analyticsBuilder: analyticsBuilder, safeDIOverrides: safeDIOverrides.service)
		        let filter: FilterProtocol = if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder(service) } else { AppFilter(service: service) }
		        return Screen(analyticsBuilder: analyticsBuilder, service: service, filter: filter)
		    }
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	/// As `generate_passesPublicMockValueItsTreeCreates_whenMockBuildsReceivedDependencyBesideMockedType`, with `AppFilter` receiving `analytics` too.
	@Test
	mutating func generate_passesPublicMockValueItsTreeCreates_whenMockBuildsReceivedDependencyBesideMockedTypeThatReceivesItToo() async throws {
		let modules = Self.receivedFilterModules(serviceReceivesAnalytics: .required, filterReceivesAnalytics: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            filter: ((Analytics, Service) -> FilterProtocol)? = nil
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.filter = filter
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIOverrides
		        private(set) var filter: ((Analytics, Service) -> FilterProtocol)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        let filter: FilterProtocol = if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder(analytics, service) } else { AppFilter(analytics: analytics, service: service) }
		        return Screen(analytics: analytics, service: service, filter: filter)
		    }
		}
		#endif
		"""])
	}

	/// As `generate_passesPublicMockValueItsTreeCreates_whenMockBuildsReceivedDependencyBesideMockedType`, with `Screen`'s mock public: it takes no parameter for the `analytics` it creates.
	@Test
	mutating func generate_passesPublicMockValueItsTreeCreates_whenMockedTypeWithPublicMockBuildsReceivedDependencyBesideIt() async throws {
		let modules = Self.receivedFilterModules(serviceReceivesAnalytics: .required, screenMockGeneration: ".public")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            filter: ((Service) -> FilterProtocol)? = nil
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.filter = filter
		        }

		        public private(set) var analytics: (() -> Analytics)?
		        public private(set) var service: Service.SafeDIOverrides
		        public private(set) var filter: ((Service) -> FilterProtocol)?
		    }

		    // SafeDI counts `FilterProtocol` as `public`: no module it reads declares it narrower. If `FilterProtocol` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
		    public static func mock(
		        filter: (any FilterProtocol)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let service = Service.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        let filter: FilterProtocol = if let filter { filter } else if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder(service) } else { AppFilter(service: service) }
		        return Screen(analytics: analytics, service: service, filter: filter)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_215B449271BCAB93 {}
		}
		#endif
		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	/// `Screen`'s mock builds the received `filter` beside `Screen`, and the call of `Service`'s public mock in `AppFilter`'s tree is passed `Screen`'s `analytics`, as `Screen`'s own tree would be.
	@Test
	mutating func generate_passesPublicMockValueItsTreeCreates_whenMockBuildsReceivedDependencyWhoseTreeCallsPublicMock() async throws {
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": Self.receivedFilterCore(serviceReceivesAnalytics: .required)]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(analytics: Analytics, filter: any FilterProtocol) {
			        self.analytics = analytics
			        self.filter = filter
			    }

			    @Instantiated let analytics: Analytics
			    @Received let filter: any FilterProtocol
			}

			@Instantiable(fulfillingAdditionalTypes: [FilterProtocol.self])
			public final class AppFilter: Instantiable, FilterProtocol {
			    public init(service: Service) {
			        self.service = service
			    }

			    @Instantiated let service: Service
			}
			"""], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            filter: AppFilter.SafeDIMockConfiguration = .init()
		        ) {
		            self.analytics = analytics
		            self.filter = filter
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var filter: AppFilter.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_filter() -> FilterProtocol {
		            _ = Service.__safeDI_Service_mock_81027395670D1D21.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let service = Service.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.filter.service)
		            return if let safeDIBuilder = safeDIOverrides.filter.safeDIBuilder { safeDIBuilder(service) } else { AppFilter(service: service) }
		        }
		        let filter: FilterProtocol = __safeDI_filter()
		        return Screen(analytics: analytics, filter: filter)
		    }
		}
		#endif

		#if DEBUG
		extension AppFilter {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            service: Service.SafeDIOverrides = .init(),
		            _ safeDIBuilder: ((Service) -> AppFilter)? = nil
		        ) {
		            self.service = service
		            self.safeDIBuilder = safeDIBuilder
		        }

		        private(set) var service: Service.SafeDIOverrides
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        private(set) var safeDIBuilder: ((Service) -> AppFilter)?
		    }
		}
		#endif

		"""])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	/// The single-module twin of `generate_passesPublicMockValueItsTreeCreates_whenMockBuildsReceivedDependencyBesideMockedType`: `Screen`'s mock builds `Service` inline, which receives `Screen`'s `analytics`.
	@Test
	mutating func generate_buildsDependencyOnce_whenMockBuildsReceivedDependencyBesideMockedTypeWhoseInlineTreeReceivesIt() async throws {
		let modules = [ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: [
			"Service.swift": Self.receivedFilterCore(serviceReceivesAnalytics: .required, serviceMockGeneration: "true"),
			"Screen.swift": Self.receivedFilterApp(serviceReceivesAnalytics: .required, importsCore: false),
		])]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIMockConfiguration = .init(),
		            filter: ((Service) -> FilterProtocol)? = nil
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.filter = filter
		        }

		        private(set) var analytics: (() -> Analytics)?
		        private(set) var service: Service.SafeDIMockConfiguration
		        private(set) var filter: ((Service) -> FilterProtocol)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_service() -> Service {
		            let session = if let safeDIBuilder = safeDIOverrides.service.session { safeDIBuilder() } else { Session() }
		            return if let safeDIBuilder = safeDIOverrides.service.safeDIBuilder { safeDIBuilder(analytics, session) } else { Service(analytics: analytics, session: session) }
		        }
		        let service: Service = __safeDI_service()
		        let filter: FilterProtocol = if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder(service) } else { AppFilter(service: service) }
		        return Screen(analytics: analytics, service: service, filter: filter)
		    }
		}
		#endif

		#if DEBUG
		extension Service {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            session: (() -> Session)? = nil,
		            analytics: (() -> Analytics)? = nil
		        ) {
		            self.session = session
		            self.analytics = analytics
		        }

		        private(set) var session: (() -> Session)?
		        private(set) var analytics: (() -> Analytics)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        return Service(analytics: analytics, session: session)
		    }
		}
		#endif

		#if DEBUG
		extension Service {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            session: (() -> Session)? = nil,
		            _ safeDIBuilder: ((Analytics, Session) -> Service)? = nil
		        ) {
		            self.session = session
		            self.safeDIBuilder = safeDIBuilder
		        }

		        private(set) var session: (() -> Session)?
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        private(set) var safeDIBuilder: ((Analytics, Session) -> Service)?
		    }
		}
		#endif
		"""])
	}

	// MARK: Tests – plain declarations prove a parameter's type

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesHoleBuilderOfPublicProtocolOnPublicTier_whenMockedTypesOwnInitializerAndTheTypesItBuildsAreInternal(integration: MultiModuleIntegration) async throws {
		// F6: `FeedService`'s own `public` declaration proves it, so the public mock takes the hole's builder while the
		// seam's own initializer and `FeedStore` stay `internal`, and a module of another package calls the mock.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "SharedModule", packageName: "App", swiftFileContent: ["@Instantiable\npublic final class SharedThing: Instantiable {\n    public init() {}\n}"]),
				ModuleFixture(
					name: "FeedModule",
					packageName: "App",
					swiftFileContentByFilePath: [
						"FeedService.swift": "public protocol FeedService {\n    func headlines() -> [String]\n}",
						"FeedScreen.swift": """
						import SharedModule

						@Instantiable(generateDependencyTree: true, generateMock: .public)
						public final class FeedScreen: Instantiable {
						    init(shared: SharedThing, store: FeedStore, service: FeedService) {
						        self.shared = shared
						        self.store = store
						        self.service = service
						    }

						    public func headlines() -> [String] { service.headlines() }

						    @Received let shared: SharedThing
						    @Instantiated let store: FeedStore
						    @Instantiated let service: FeedService
						}

						@Instantiable
						final class FeedStore: Instantiable {
						    init(shared: SharedThing) {
						        self.shared = shared
						    }

						    @Received let shared: SharedThing
						}
						""",
					],
					dependencies: ["SharedModule"],
				),
				ModuleFixture(name: "Previews", packageName: "Previews", swiftFileContentByFilePath: [
					"FeedPreviews.swift": """
					import FeedModule

					#if DEBUG
					struct StubFeedService: FeedService {
					    func headlines() -> [String] { ["Previewing without the app"] }
					}

					func makeScreen() -> FeedScreen {
					    FeedScreen.mock(feedServiceBuilder: { _ in StubFeedService() })
					}
					#endif
					""",
				], dependencies: ["SharedModule", "FeedModule"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let imports = "#if canImport(SharedModule)\nimport SharedModule\n#endif\n\n"
		let seamCode = """
		extension FeedScreen {
		    @frozen public enum SafeDIScope_FeedService {
		        case service(service_Values)

		        public struct service_Values {
		            public let shared: SharedThing
		            internal let store: FeedStore
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public convenience init(__safeDI_shared shared: SharedThing, __safeDI_feedServiceBuilder: @escaping (SafeDIScope_FeedService) -> FeedService) {
		        let store = FeedStore(shared: shared)
		        let service: FeedService = __safeDI_feedServiceBuilder(.service(SafeDIScope_FeedService.service_Values(shared: shared, store: store)))
		        self.init(shared: shared, store: store, service: service)
		    }
		}

		extension FeedScreen {
		    public enum __safeDI_FeedScreen_91C4FAF0D0AEF562 {}
		}
		"""
		let mockCode = """
		#if DEBUG
		extension FeedScreen {
		    @frozen public enum SafeDIMockScope_FeedService {
		        case service(service_Values)

		        public struct service_Values {
		            public let shared: SharedThing
		            internal let store: FeedStore
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            shared: (() -> SharedThing)? = nil
		        ) {
		            self.shared = shared
		            self.store = nil
		        }

		        init(
		            shared: (() -> SharedThing)? = nil,
		            store: ((SharedThing) -> FeedStore)? = nil
		        ) {
		            self.shared = shared
		            self.store = store
		        }

		        public private(set) var shared: (() -> SharedThing)?
		        private(set) var store: ((SharedThing) -> FeedStore)?
		    }

		    public static func mock(
		        feedServiceBuilder: @escaping (FeedScreen.SafeDIMockScope_FeedService) -> FeedService,
		        shared: SharedThing? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> FeedScreen {
		        let __safeDI_feedServiceBuilder = feedServiceBuilder
		        let shared = if let shared { shared } else if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { SharedThing() }
		        let store = if let safeDIBuilder = safeDIOverrides.store { safeDIBuilder(shared) } else { FeedStore(shared: shared) }
		        let service: FeedService = __safeDI_feedServiceBuilder(.service(SafeDIMockScope_FeedService.service_Values(shared: shared, store: store)))
		        return FeedScreen(shared: shared, store: store, service: service)
		    }
		}

		extension FeedScreen {
		    public enum __safeDI_FeedScreen_mock_E1889A7E6295E4E6 {}
		}
		#endif
		"""
		switch integration {
		case .moduleInfo:
			#expect(output.modules["FeedModule"]?.generatedFiles == ["FeedModule.swift": generatedFileHeader + imports + seamCode + "\n\n" + mockCode])
		case .swiftPackagePlugin:
			#expect(output.modules["FeedModule"]?.generatedFiles == [
				"FeedScreen+SafeDI.swift": generatedFileHeader + imports + seamCode,
				"FeedScreen+SafeDIMock.swift": generatedFileHeader + imports + mockCode,
				"SafeDIMockConfiguration.swift": generatedFileHeader + imports,
			])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOptionalReceivedParameter_whenPublicMockOnlyExtensionMocksTypeDeclaredInsideConditionalBlock() async throws {
		// EOU-3's twin: the `public` `mockOnly` extension proves `Session` `public`, and the mock builds it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.serviceReceivingSession(alongside: ["@Instantiable(mockOnly: true)\npublic extension Session {\n    static func mock() -> Session {\n        Session()\n    }\n}"]),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == ["Service+SafeDIMock.swift": generatedFileHeader + """
		#if DEBUG
		extension Service {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            session: (() -> Session)? = nil
		        ) {
		            self.tokenCache = nil
		            self.session = session
		        }

		        init(
		            tokenCache: (() -> TokenCache)? = nil,
		            session: (() -> Session)? = nil
		        ) {
		            self.tokenCache = tokenCache
		            self.session = session
		        }

		        private(set) var tokenCache: (() -> TokenCache)?
		        public private(set) var session: (() -> Session)?
		    }

		    public static func mock(
		        userService: any UserService,
		        session: Session? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        let tokenCache = if let safeDIBuilder = safeDIOverrides.tokenCache { safeDIBuilder() } else { TokenCache() }
		        let session = if let session { session } else if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.mock() }
		        return Service(userService: userService, session: session, tokenCache: tokenCache)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_mock_8A6472169C457EAC {}
		}
		#endif
		"""])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesForwardedTypeOnPublicTier_whenUnspelledMockOnlyExtensionMocksPublicClass(integration: MultiModuleIntegration) async throws {
		// EOU-4: the README's unspelled `@Instantiable(mockOnly: true) extension User` is bounded by `User`'s own `public`
		// declaration, so the public mock takes `user`, and the README's call compiles in another package.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"User.swift": "public final class User: Sendable {\n    public init(name: String) {\n        self.name = name\n    }\n\n    public let name: String\n}",
					"UserMock.swift": "@Instantiable(mockOnly: true)\nextension User {\n    public static func mock() -> User {\n        User(name: \"Mock\")\n    }\n}",
					"ProfileView.swift": """
					@Instantiable(generateMock: .public)
					public final class ProfileView: Instantiable {
					    init(user: User, store: ProfileStore) {
					        self.user = user
					        self.store = store
					    }

					    @Forwarded let user: User
					    @Instantiated let store: ProfileStore
					}

					@Instantiable
					final class ProfileStore: Instantiable {
					    init() {}
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "Notes", swiftFileContentByFilePath: [
					"Preview.swift": "import Feature\n\n#if DEBUG\nfunc preview() -> ProfileView {\n    ProfileView.mock(user: User(name: \"dfed\"))\n}\n#endif",
				], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let mockCode = """
		#if DEBUG
		extension ProfileView {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init() {
		            self.store = nil
		        }

		        init(
		            store: (() -> ProfileStore)? = nil
		        ) {
		            self.store = store
		        }

		        private(set) var store: (() -> ProfileStore)?
		    }

		    public static func mock(
		        user: User? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> ProfileView {
		        let user = user ?? (User.mock())
		        let store = if let safeDIBuilder = safeDIOverrides.store { safeDIBuilder() } else { ProfileStore() }
		        return ProfileView(user: user, store: store)
		    }
		}

		extension ProfileView {
		    public enum __safeDI_ProfileView_mock_77E7840731A6C4C1 {}
		}
		#endif
		"""
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + mockCode])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles["ProfileView+SafeDIMock.swift"] == generatedFileHeader + mockCode)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Feature`, in package `Shop`, whose `Space.swift` holds `namespaceDeclaration` alone, without a SafeDI marker, and
	/// whose `Shelf.swift` declares the `public` `Space.Shelf`, with a public mock, in an unspelled extension of `Space`.
	private static func featureExtendingNamespace(declaredAs namespaceDeclaration: String) -> ModuleFixture {
		ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
			"Space.swift": namespaceDeclaration,
			"Shelf.swift": """
			import SafeDI

			public protocol Shelving {}

			extension Space {
			    @Instantiable(generateMock: .public)
			    public final class Shelf: Instantiable, Shelving {
			        public init() {}
			    }
			}
			""",
		])
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

	/// A public `Service` whose public mock receives the `public` protocol `UserService` and `Session`, which is declared
	/// `public` inside a platform-conditioned block, beside `otherFiles`.
	private static func serviceReceivingSession(alongside otherFiles: [String]) -> [String] {
		[
			"public protocol UserService: AnyObject {\n    var name: String { get }\n}",
			platformConditionedDeclaration("public final class Session {\n    public init() {}\n}"),
			"""
			@Instantiable(generateMock: .public)
			public struct Service: Instantiable {
			    init(userService: any UserService, session: Session, tokenCache: TokenCache) {
			        self.userService = userService
			        self.session = session
			        self.tokenCache = tokenCache
			    }

			    @Received let userService: any UserService
			    @Received let session: Session
			    @Instantiated let tokenCache: TokenCache
			}

			@Instantiable
			struct TokenCache: Instantiable {
			    init() {}
			}
			""",
		] + otherFiles
	}

	/// How `Service` in `receivedFilterCore(serviceReceivesAnalytics:serviceMockGeneration:)` receives the `Analytics`
	/// that `Screen` in `receivedFilterApp(serviceReceivesAnalytics:filterReceivesAnalytics:screenMockGeneration:importsCore:)`
	/// instantiates in the form `Service` receives it.
	private enum ServiceReceivesAnalytics {
		/// `@Received let analytics: Analytics`.
		case required
		/// `@Received(onlyIfAvailable: true) let analytics: Analytics?`.
		case onlyIfAvailable
		/// `@Received let analytics: LazilyInstantiated<Analytics>`.
		case lazilyInstantiated
		/// `@Received let analyticsBuilder: Instantiator<Analytics>`.
		case instantiator

		/// The property `Service` receives.
		var serviceProperty: String {
			switch self {
			case .required: "analytics: Analytics"
			case .onlyIfAvailable: "analytics: Analytics?"
			case .lazilyInstantiated: "analytics: LazilyInstantiated<Analytics>"
			case .instantiator: "analyticsBuilder: Instantiator<Analytics>"
			}
		}

		/// The property `Screen` instantiates.
		var screenProperty: String {
			switch self {
			case .required, .onlyIfAvailable: "analytics: Analytics"
			case .lazilyInstantiated: "analytics: LazilyInstantiated<Analytics>"
			case .instantiator: "analyticsBuilder: Instantiator<Analytics>"
			}
		}

		/// The label of both properties.
		var label: String {
			switch self {
			case .required, .onlyIfAvailable, .lazilyInstantiated: "analytics"
			case .instantiator: "analyticsBuilder"
			}
		}

		/// The attribute that declares `serviceProperty`.
		var serviceAttribute: String {
			switch self {
			case .required, .lazilyInstantiated, .instantiator: "@Received"
			case .onlyIfAvailable: "@Received(onlyIfAvailable: true)"
			}
		}
	}

	/// `Core`'s declarations for the shape in which `Screen` instantiates `analytics` and `service` and receives a
	/// `filter` whose type receives `service`: `Service` receives `analytics` and instantiates the `package` `Session`, so
	/// a module of another package builds it through its public mock.
	private static func receivedFilterCore(serviceReceivesAnalytics: ServiceReceivesAnalytics, serviceMockGeneration: String = ".public") -> String {
		"""
		import SafeDI

		@Instantiable
		public final class Analytics: Instantiable {
		    public init() {}
		}

		@Instantiable
		package final class Session: Instantiable {
		    package init() {}
		}

		public protocol FilterProtocol {}

		@Instantiable(generateMock: \(serviceMockGeneration))
		public final class Service: Instantiable {
		    package init(\(serviceReceivesAnalytics.serviceProperty), session: Session) {
		        self.\(serviceReceivesAnalytics.label) = \(serviceReceivesAnalytics.label)
		        self.session = session
		    }

		    \(serviceReceivesAnalytics.serviceAttribute) let \(serviceReceivesAnalytics.serviceProperty)
		    @Instantiated let session: Session
		}
		"""
	}

	/// `App`'s declarations for the shape `receivedFilterCore(serviceReceivesAnalytics:serviceMockGeneration:)` describes,
	/// in which `AppFilter` receives `analytics` too when `filterReceivesAnalytics` is set.
	private static func receivedFilterApp(
		serviceReceivesAnalytics: ServiceReceivesAnalytics,
		filterReceivesAnalytics: Bool = false,
		screenMockGeneration: String = "true",
		importsCore: Bool = true,
	) -> String {
		let filterParameters = filterReceivesAnalytics ? "analytics: Analytics, service: Service" : "service: Service"
		let filterAssignments = filterReceivesAnalytics ? "        self.analytics = analytics\n        self.service = service" : "        self.service = service"
		let filterProperties = filterReceivesAnalytics ? "    @Received let analytics: Analytics\n    @Received let service: Service" : "    @Received let service: Service"
		return (importsCore ? "import Core\n" : "") + """
		import SafeDI

		@Instantiable(generateMock: \(screenMockGeneration))
		public final class Screen: Instantiable {
		    public init(\(serviceReceivesAnalytics.screenProperty), service: Service, filter: any FilterProtocol) {
		        self.\(serviceReceivesAnalytics.label) = \(serviceReceivesAnalytics.label)
		        self.service = service
		        self.filter = filter
		    }

		    @Instantiated let \(serviceReceivesAnalytics.screenProperty)
		    @Instantiated let service: Service
		    @Received let filter: any FilterProtocol
		}

		@Instantiable(fulfillingAdditionalTypes: [FilterProtocol.self])
		public final class AppFilter: Instantiable, FilterProtocol {
		    public init(\(filterParameters)) {
		\(filterAssignments)
		    }

		\(filterProperties)
		}
		"""
	}

	/// `Core` and `App`, in two packages, for the shape `receivedFilterCore(serviceReceivesAnalytics:serviceMockGeneration:)`
	/// describes.
	private static func receivedFilterModules(
		serviceReceivesAnalytics: ServiceReceivesAnalytics,
		filterReceivesAnalytics: Bool = false,
		screenMockGeneration: String = "true",
	) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": receivedFilterCore(serviceReceivesAnalytics: serviceReceivesAnalytics)]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": receivedFilterApp(
				serviceReceivesAnalytics: serviceReceivesAnalytics,
				filterReceivesAnalytics: filterReceivesAnalytics,
				screenMockGeneration: screenMockGeneration,
			)], dependencies: ["Core"]),
		]
	}

	/// The canonical fixture's `Core` module (the shape matrix's section 0), with `appCaller` in `App`, another package.
	/// M7.1's modules: `Service`'s tree holds a hole, `userService`, which `DefaultUserService` fulfills only where `App`
	/// declares it, and the package `Session`, which keeps `App` from building the tree; `Profile`'s public initializer
	/// proves `AnyUserService` `public`.
	private static func holeModules(app: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
				"""
				@Instantiable
				public final class Analytics: Instantiable, Sendable {
				    public init() {}
				}

				@Instantiable
				package final class Session: Instantiable {
				    package init() {}
				}

				public protocol UserService {}

				public struct AnyUserService: UserService {
				    public init(_ userService: any UserService) {
				        self.userService = userService
				    }

				    public let userService: any UserService
				}

				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: AnyUserService) {
				        self.userService = userService
				    }

				    @Received let userService: AnyUserService
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    package init(analytics: Analytics, session: Session, userService: AnyUserService) {
				        self.analytics = analytics
				        self.session = session
				        self.userService = userService
				    }

				    @Received let analytics: Analytics
				    @Instantiated let session: Session
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [app], dependencies: ["Core"]),
		]
	}

	/// How `fillReceivingLabelCache(receivingFilter:)`'s `TokenCache` receives `filter`.
	private enum FilterReceive {
		/// Only if available: `Cache`'s mock passes `filter` on and builds nothing for it.
		case onlyIfAvailable
		/// Required, as `any FilterProtocol`: `Cache`'s mock builds `CoreFilter` when passed `nil`.
		case required
		/// Required, as `LazilyInstantiated<any FilterProtocol>`: `Cache`'s mock builds that wrapper of `CoreFilter` when
		/// passed `nil`.
		case requiredLazilyInstantiated
	}

	/// The modules of the cells whose mock fills a builder with a tree that calls `Cache`'s public mock, which takes
	/// `filter`: `Core` declares `fillReceivingLabelCache(receivingFilter:)`; `Service`, whose hole `userService`
	/// `DefaultUserService` fulfills where `App` declares it, and which instantiates `filter` before it when
	/// `serviceInstantiatesFilter`, so that the hole's scope struct carries it; `Board`, whose hole `widget`
	/// `DefaultWidget` fulfills likewise; and the package `Session`, which keeps `App` from building either tree. `App`
	/// declares `app` and `ProbeFilter`, which the value comparison passes as `filter`.
	private static func fillReceivingLabelModules(
		receivingFilter filterReceive: FilterReceive = .onlyIfAvailable,
		serviceInstantiatesFilter: Bool = false,
		app: String,
	) -> [ModuleFixture] {
		let serviceFilterParameter = serviceInstantiatesFilter ? "filter: any FilterProtocol, " : ""
		let serviceFilterAssignment = serviceInstantiatesFilter ? "\n        self.filter = filter" : ""
		let serviceFilterProperty = serviceInstantiatesFilter ? "\n    @Instantiated let filter: any FilterProtocol" : ""
		return [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
				fillReceivingLabelCache(receivingFilter: filterReceive) + "\n\n" + """
				@Instantiable
				public final class Analytics: Instantiable {
				    public init() {}
				}

				@Instantiable
				package final class Session: Instantiable {
				    package init() {}
				}

				public protocol UserService {}

				public struct AnyUserService: UserService {
				    public init(_ userService: any UserService) {
				        self.userService = userService
				    }

				    public let userService: any UserService
				}

				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: AnyUserService) {
				        self.userService = userService
				    }

				    @Received let userService: AnyUserService
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    package init(analytics: Analytics, session: Session, \(serviceFilterParameter)userService: AnyUserService) {
				        self.analytics = analytics
				        self.session = session\(serviceFilterAssignment)
				        self.userService = userService
				    }

				    @Received let analytics: Analytics
				    @Instantiated let session: Session\(serviceFilterProperty)
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}

				public protocol Widget {}

				public struct AnyWidget: Widget {
				    public init(_ widget: any Widget) {
				        self.widget = widget
				    }

				    public let widget: any Widget
				}

				@Instantiable
				public struct Panel: Instantiable {
				    public init(widget: AnyWidget) {
				        self.widget = widget
				    }

				    @Received let widget: AnyWidget
				}

				@Instantiable(generateMock: .public)
				public struct Board: Instantiable {
				    package init(session: Session, widget: AnyWidget) {
				        self.session = session
				        self.widget = widget
				    }

				    @Instantiated let session: Session
				    @Instantiated(fulfilledByType: "DefaultWidget", erasedToConcreteExistential: true) let widget: AnyWidget
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [app + "\n\n" + fillReceivingLabelProbeFilter], dependencies: ["Core"]),
		]
	}

	/// `Core`'s `Cache`, whose public mock's tree holds `TokenCache`, which receives `filter` as `filterReceive` says, so
	/// that `Cache`'s mock takes `filter: (any FilterProtocol)? = nil` and, unless `TokenCache` receives it only if
	/// available, builds it from `CoreFilter` when passed `nil`.
	private static func fillReceivingLabelCache(receivingFilter filterReceive: FilterReceive) -> String {
		let tokenCache = switch filterReceive {
		case .onlyIfAvailable:
			"""
			@Instantiable
			public struct TokenCache: Instantiable {
			    public init(filter: (any FilterProtocol)?) {
			        self.filter = filter
			    }

			    @Received(onlyIfAvailable: true) let filter: (any FilterProtocol)?
			}
			"""
		case .required:
			"""
			@Instantiable
			public struct TokenCache: Instantiable {
			    public init(filter: any FilterProtocol) {
			        self.filter = filter
			    }

			    @Received let filter: any FilterProtocol
			}
			"""
		case .requiredLazilyInstantiated:
			"""
			@Instantiable
			public struct TokenCache: Instantiable {
			    public init(filter: LazilyInstantiated<any FilterProtocol>) {
			        self.filter = filter
			    }

			    @Received let filter: LazilyInstantiated<any FilterProtocol>
			}
			"""
		}
		let coreFilter = switch filterReceive {
		case .onlyIfAvailable:
			""
		case .required, .requiredLazilyInstantiated:
			"""


			@Instantiable(fulfillingAdditionalTypes: [FilterProtocol.self])
			public final class CoreFilter: FilterProtocol, Instantiable {
			    public init() {}
			}
			"""
		}
		return """
		public protocol FilterProtocol {}

		\(tokenCache)\(coreFilter)

		@Instantiable(generateMock: .public)
		public struct Cache: Instantiable {
		    package init(tokenCache: TokenCache) {
		        self.tokenCache = tokenCache
		    }

		    @Instantiated let tokenCache: TokenCache
		}
		"""
	}

	/// `Screen`, with a mock as `generateMock` says, which instantiates `analytics`, which `Service` receives, then
	/// `filter` as `filterType` when it is not `nil`, `Service` and, when `instantiatesBoard`, `Board`.
	private static func fillReceivingLabelScreen(generateMock: String, filterType: String? = nil, instantiatesBoard: Bool = false) -> String {
		var properties = [(label: "analytics", type: "Analytics")]
		if let filterType {
			properties.append((label: "filter", type: filterType))
		}
		properties.append((label: "service", type: "Service"))
		if instantiatesBoard {
			properties.append((label: "board", type: "Board"))
		}
		return """
		import Core

		@Instantiable(generateMock: \(generateMock))
		public final class Screen: Instantiable {
		    public init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {
		\(properties.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n"))
		    }

		\(properties.map { "    @Instantiated let \($0.label): \($0.type)" }.joined(separator: "\n"))
		}
		"""
	}

	/// `Screen`, with a mock as `generateMock` says, which instantiates `analytics`, `service`, then `filter: any
	/// FilterProtocol` and, when `instantiatesLaterService`, `laterService: Service`; and `AppFilter`, which fulfills
	/// `FilterProtocol` and receives `service`, only if available when `appFilterReceivesServiceOnlyIfAvailable` and
	/// otherwise required, so that `service` is built before `filter`.
	private static func screenBuildingServiceBeforeFilter(generateMock: String, appFilterReceivesServiceOnlyIfAvailable: Bool = false, instantiatesLaterService: Bool = false) -> String {
		var properties = [(label: "analytics", type: "Analytics"), (label: "service", type: "Service"), (label: "filter", type: "any FilterProtocol")]
		if instantiatesLaterService {
			properties.append((label: "laterService", type: "Service"))
		}
		let serviceType = appFilterReceivesServiceOnlyIfAvailable ? "Service?" : "Service"
		let serviceDecorator = appFilterReceivesServiceOnlyIfAvailable ? "@Received(onlyIfAvailable: true)" : "@Received"
		return """
		import Core

		@Instantiable(generateMock: \(generateMock))
		public final class Screen: Instantiable {
		    public init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {
		\(properties.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n"))
		    }

		\(properties.map { "    @Instantiated let \($0.label): \($0.type)" }.joined(separator: "\n"))
		}

		@Instantiable(fulfillingAdditionalTypes: [FilterProtocol.self])
		public final class AppFilter: Instantiable, FilterProtocol {
		    public init(service: \(serviceType)) {
		        self.service = service
		    }

		    \(serviceDecorator) let service: \(serviceType)
		}
		"""
	}

	/// `DefaultUserService`, which fulfills `Service`'s hole, receives `analytics` and builds `cache` with `Cache`'s public
	/// mock.
	private static let userServiceBuildingCache = """
	@Instantiable
	public final class DefaultUserService: UserService, Instantiable {
	    public init(analytics: Analytics, cache: Cache) {
	        self.analytics = analytics
	        self.cache = cache
	    }

	    @Received let analytics: Analytics
	    @Instantiated let cache: Cache
	}
	"""

	/// A `FilterProtocol` no `@Instantiable` declares, which the value comparison passes as `filter`.
	private static let fillReceivingLabelProbeFilter = """
	public final class ProbeFilter: FilterProtocol {
	    public init() {}
	}
	"""

	/// The probe of a public mock that takes `filter`, passed `ProbeFilter`, which the inline mock takes as the override of
	/// its tree's receive only if available.
	private static let screenMockPassingFilter = DifferentialValueProbe(
		name: "Screen.mock() passed a filter",
		expression: "Screen.mock(filter: ProbeFilter())",
		knownRightExpression: "Screen.mock(safeDIOverrides: .init(filter: ProbeFilter()))",
	)

	/// The probe of a public mock that takes `filter` and builds it from `CoreFilter` when passed `nil`, passed `ProbeFilter`,
	/// which the inline mock, which builds `filter` too, takes as the override of what it builds.
	private static let screenMockPassingFilterToBuildInstead = DifferentialValueProbe(
		name: "Screen.mock() passed a filter",
		expression: "Screen.mock(filter: ProbeFilter())",
		knownRightExpression: "Screen.mock(safeDIOverrides: .init(filter: { ProbeFilter() }))",
	)

	/// M8.27's modules: `Service`'s hole `routerBuilder`, an `ErasedInstantiator` of `AnyRouting`, which `Profile`'s
	/// public initializer proves `public`, is fulfilled by `App`'s `Router`; the scope struct carries the `analytics`
	/// `Service` receives, which a call inside the fill passes on. `Core` also declares `coreAddition`, and `Screen` has a
	/// mock as `screenMockGeneration` says.
	private static func lazyCycleThroughFillModules(router: String, screenMockGeneration: String = "true", coreAddition: String = "") -> [ModuleFixture] {
		// Appended in a statement of its own rather than joined with `+` around a ternary in the fixtures below: Swift 6.2
		// on Linux can time out type-checking such an expression; later Swift does not.
		var coreFile = """
		@Instantiable
		package final class Session: Instantiable {
		    package init() {}
		}

		public protocol Routing {}

		public struct AnyRouting {
		    public init(_ routing: any Routing) {}
		}

		@Instantiable
		public struct Profile: Instantiable {
		    public init(routing: AnyRouting) {
		        self.routing = routing
		    }

		    @Received let routing: AnyRouting
		}

		@Instantiable
		public final class Analytics: Instantiable {
		    public init() {}
		}

		@Instantiable(generateMock: .public)
		public final class Service: Instantiable {
		    package init(analytics: Analytics, session: Session, routerBuilder: ErasedInstantiator<(), AnyRouting>) {
		        self.analytics = analytics
		        self.session = session
		        self.routerBuilder = routerBuilder
		    }

		    @Received let analytics: Analytics
		    @Instantiated let session: Session
		    @Instantiated(fulfilledByType: "Router", erasedToConcreteExistential: true) let routerBuilder: ErasedInstantiator<(), AnyRouting>
		}
		"""
		if !coreAddition.isEmpty {
			coreFile += "\n\n" + coreAddition
		}
		return [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [coreFile]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
				"""
				import Core

				\(router)
				@Instantiable(generateMock: \(screenMockGeneration))
				public final class Screen: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
			], dependencies: ["Core"]),
		]
	}

	/// The name of the guard of `Screen`'s public mock, where `Screen` holds `Service` as `heldType` and `Service`, whose
	/// tree `App` cannot build, holds a hole declared by `holeDeclaration`, which `Screen`'s mock passes up.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func publicMockGuardName(ofScreenHolding heldType: String, holeDeclaration: String) async throws -> String {
		let holeType = try #require(holeDeclaration.components(separatedBy: "let hole: ").last)
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
					"""
					@Instantiable
					package final class Session: Instantiable {
					    package init() {}
					}

					public protocol UserService {}

					public struct AnyUserService: UserService {
					    public init(_ userService: any UserService) {
					        self.userService = userService
					    }

					    public let userService: any UserService
					}

					open class Panel: Instantiable, @unchecked Sendable {
					    public typealias ForwardedProperties = String

					    public init(title: String) {
					        self.title = title
					    }

					    public let title: String
					}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    package init(session: Session, hole: \(holeType)) {
					        self.session = session
					        self.hole = hole
					    }

					    @Instantiated let session: Session
					    \(holeDeclaration)
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
					"""
					import Core

					@Instantiable(generateMock: .public)
					public final class Screen: Instantiable {
					    public init(service: \(heldType)) {
					        self.service = service
					    }

					    @Instantiated let service: \(heldType)
					}
					""",
				], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		let generatedCode = try #require(output.modules["App"]?.generatedFiles["App.swift"])
		let guardRange = try #require(generatedCode.range(of: "__safeDI_Screen_mock_[0-9A-F]{16}", options: .regularExpression))
		return String(generatedCode[guardRange])
	}

	/// D530-4's modules: `Core` declares a `.public` type for each of `serviceNames`, each with a hole `userService`
	/// that `DefaultUserService` fulfills where a module declares it, and the package `Session`, which keeps another
	/// package from building their trees; `App` declares `Screen`, which instantiates one of each. With
	/// `distinctValueInScopeAtEachHole`, each type also instantiates `extra` of a package type of its own, so the scope
	/// structs of the holes, whose fields a caller's guard hashes, differ.
	private static func sameLabelHoleModules(serviceNames: [String], screenMockGeneration: String, distinctValueInScopeAtEachHole: Bool = false) -> [ModuleFixture] {
		let services = serviceNames.map { name in
			guard distinctValueInScopeAtEachHole else {
				return """
				@Instantiable(generateMock: .public)
				public final class \(name): Instantiable {
				    package init(session: Session, userService: AnyUserService) {
				        self.session = session
				        self.userService = userService
				    }

				    @Instantiated let session: Session
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				"""
			}
			return """
			@Instantiable
			package final class \(name)Extra: Instantiable {
			    package init() {}
			}

			@Instantiable(generateMock: .public)
			public final class \(name): Instantiable {
			    package init(session: Session, extra: \(name)Extra, userService: AnyUserService) {
			        self.session = session
			        self.extra = extra
			        self.userService = userService
			    }

			    @Instantiated let session: Session
			    @Instantiated let extra: \(name)Extra
			    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
			}
			"""
		}
		let labels = serviceNames.map { $0.prefix(1).lowercased() + $0.dropFirst() }
		let screenParameters = zip(labels, serviceNames).map { "\($0): \($1)" }.joined(separator: ", ")
		let screenAssignments = labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n")
		let screenProperties = zip(labels, serviceNames).map { "    @Instantiated let \($0): \($1)" }.joined(separator: "\n")
		return [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
				"""
				@Instantiable
				public final class Analytics: Instantiable {
				    public init() {}
				}

				@Instantiable
				package final class Session: Instantiable {
				    package init() {}
				}

				public protocol UserService {}

				public struct AnyUserService: UserService {
				    public init(_ base: any UserService) {
				        self.base = base
				    }

				    public let base: any UserService
				}

				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: AnyUserService) {
				        self.userService = userService
				    }

				    @Received let userService: AnyUserService
				}

				""" + services.joined(separator: "\n\n"),
			]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
				"""
				import Core

				@Instantiable(generateMock: \(screenMockGeneration))
				public final class Screen: Instantiable {
				    package init(\(screenParameters)) {
				\(screenAssignments)
				    }

				\(screenProperties)
				}
				""",
			], dependencies: ["Core"]),
		]
	}

	/// `Root`, in a third module, which instantiates `sameLabelHoleModules`' `Screen`.
	private static let sameLabelHoleRoot = """
	import App
	import Core

	@Instantiable(generateMock: true)
	public final class Root: Instantiable {
	    public init(screen: Screen) {
	        self.screen = screen
	    }

	    @Instantiated let screen: Screen
	}
	"""

	private static let holeScreen = """
	import Core

	@Instantiable(generateMock: true)
	public final class Screen: Instantiable {
	    public init(analytics: Analytics, service: Service) {
	        self.analytics = analytics
	        self.service = service
	    }

	    @Instantiated let analytics: Analytics
	    @Instantiated let service: Service
	}
	"""

	private static let defaultUserService = """
	@Instantiable
	public final class DefaultUserService: UserService, Instantiable {
	    public init(analytics: Analytics) {
	        self.analytics = analytics
	    }

	    @Received let analytics: Analytics
	}
	"""

	/// Compares the values the mocks of `modules`, as `output` generated them, build for `probes` with what internal
	/// mocks build inline when every declaration of `modules` is in one module and every public mock is internal, which
	/// nothing keeps from building every tree inline: a public mock must build what the inline mock would, apart from
	/// `exemptions`.
	private mutating func expectValuesAgreeWithInlineMocks(
		of modules: [ModuleFixture],
		output: MultiModuleTestOutput,
		probes: [DifferentialValueProbe],
		exempting exemptions: [DifferentialValueDifference] = [],
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
			for (index, content) in module.swiftFileContent.enumerated() {
				inlineFiles["\(module.name)_File\(index).swift"] = inline(content)
			}
		}
		let inlineModules = [ModuleFixture(name: modules[0].name, packageName: modules[0].packageName, swiftFileContentByFilePath: inlineFiles)]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		func path(of modules: [ModuleFixture], output: MultiModuleTestOutput) throws -> DifferentialValuePath {
			try DifferentialValuePath(modules: modules.map { module in
				var fixtureFiles = module.swiftFileContentByFilePath
				for (index, content) in module.swiftFileContent.enumerated() {
					fixtureFiles["File\(index).swift"] = content
				}
				return try DifferentialValueModule(
					name: module.name,
					packageName: module.packageName,
					dependencyModuleNames: module.dependencies,
					fixtureFiles: fixtureFiles,
					generatedFiles: #require(output.modules[module.name], sourceLocation: sourceLocation).generatedFiles,
				)
			})
		}
		try expectDifferentialValuesAgree(
			feature: path(of: modules, output: output),
			knownRight: path(of: inlineModules, output: inlineOutput),
			probes: probes,
			exempting: exemptions,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	private static func canonicalModules(appCaller: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Canonical.swift": canonicalCore]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Caller.swift": appCaller], dependencies: ["Core"]),
		]
	}

	private static let canonicalCore = """
	import SafeDI

	@Instantiable
	public final class Analytics: Instantiable, Sendable {
	    public init() {}
	}

	@Instantiable
	public struct Theme: Instantiable {
	    public init() {}
	}

	public protocol Logger {}

	@Instantiable(fulfillingAdditionalTypes: [Logger.self])
	public struct ConsoleLogger: Logger, Instantiable {
	    public init() {}
	}

	@Instantiable(fulfillingAdditionalTypes: [Logger.self], mockOnly: true)
	package final class FakeLogger: Logger {
	    package static func mock(verbose: Bool = false) -> FakeLogger {
	        FakeLogger()
	    }
	}

	@Instantiable
	package struct Session: Instantiable {
	    package init() {}
	}

	package struct Policy {
	    package static let standard = Policy()
	}

	enum Defaults {
	    static let capacity = 10
	    static let name: String? = "service"
	    static let policy: Policy? = .standard
	    static let label: String? = "dash"
	}

	@Instantiable
	package struct TokenCache: Instantiable {
	    static let defaultCapacity = Defaults.capacity

	    package init(analytics: Analytics, session: Session, theme: Theme?, capacity: Int = defaultCapacity) {
	        self.analytics = analytics
	        self.session = session
	        self.theme = theme
	    }

	    @Received let analytics: Analytics
	    @Received let session: Session
	    @Received(onlyIfAvailable: true) let theme: Theme?
	}

	@Instantiable(generateMock: .public)
	public struct Service: Instantiable {
	    package init(analytics: LazilyInstantiated<Analytics>, logger: any Logger, tokenCache: TokenCache, retries: Int = 3, name: String? = Defaults.name, policy: Policy? = Defaults.policy) {
	        self.analytics = analytics
	        self.logger = logger
	        self.tokenCache = tokenCache
	    }

	    @Received let analytics: LazilyInstantiated<Analytics>
	    @Instantiated let logger: any Logger
	    @Instantiated let tokenCache: TokenCache
	}

	@Instantiable
	@MainActor
	package final class ViewModel: Instantiable {
	    nonisolated static let defaultTitle: String? = "title"

	    package init(title: String? = defaultTitle) {}
	}

	@Instantiable(generateMock: .public)
	@MainActor
	public struct Dashboard: Instantiable {
	    package init(vm: ViewModel, label: String? = Defaults.label) {
	        self.vm = vm
	    }

	    @Instantiated let vm: ViewModel
	}
	"""

	private static let canonicalAppCaller = """
	import Core

	#if DEBUG
	func callPublicTiers() {
	    _ = Service.mock()
	    _ = Service.mock(retries: 9, analytics: Analytics(), theme: Theme(), safeDIOverrides: .init(logger: .init(verbose: true), analytics: { Analytics() }, tokenCache: .init(capacity: 5), name: nil))
	    _ = Service.__safeDI_Service_mock_209346FEA041FD20.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
	}

	@MainActor func callDashboard() {
	    _ = Dashboard.mock()
	    _ = Dashboard.mock(label: "custom", safeDIOverrides: .init(vm: .init(title: nil)))
	}
	#endif
	"""

	/// M2.23c's modules: `AppFilter` provides `filter` and receives `service` only if available, and `Service`'s public
	/// tier omits `filter`, which `TokenCache` receives only if available.
	private static func softEdgeModules(screenDeclaresFilterFirst: Bool) -> [ModuleFixture] {
		let filterDeclaration = "@Instantiated let filter: Hub.Filter"
		let serviceDeclaration = "@Instantiated let service: Service"
		let declarations = screenDeclaresFilterFirst ? [filterDeclaration, serviceDeclaration] : [serviceDeclaration, filterDeclaration]
		return [
			hubsModule,
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Filter.swift": hubTheme(named: "Filter", declarations: ["@Received(onlyIfAvailable: true) let service: Service?"]), "Service.swift": """
			import Hubs
			import SafeDI

			@Instantiable
			package struct TokenCache: Instantiable {
			    package init(filter: Hub.Filter?) {
			        self.filter = filter
			    }

			    @Received(onlyIfAvailable: true) let filter: Hub.Filter?
			}

			@Instantiable(generateMock: .public)
			public struct Service: Instantiable {
			    package init(tokenCache: TokenCache) {
			        self.tokenCache = tokenCache
			    }

			    @Instantiated let tokenCache: TokenCache
			}
			"""], dependencies: ["Hubs"]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
			import Core
			import Hubs
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(filter: Hub.Filter, service: Service) {
			        self.filter = filter
			        self.service = service
			    }

			    \(declarations[0])
			    \(declarations[1])
			}
			"""], dependencies: ["Core", "Hubs"]),
		]
	}

	/// M8.33d's modules: `Mid.Outer`, a public mock in another package, builds `Core.Service` through its public tier,
	/// which omits `filter`; `App.AppRoot` builds `Outer` through its public mock.
	/// `filter` is the `package` `Filter` `Core` declares, which `App` does not name, or, when `appRootForwardsFilter`,
	/// `[3 of Int]`, a spelling SafeDI cannot read, which `App` forwards while SafeDI proves it only `package`.
	private static func chainModules(appRootForwardsFilter: Bool) -> [ModuleFixture] {
		let filterType = appRootForwardsFilter ? "[3 of Int]" : "Filter"
		let filterDeclaration = appRootForwardsFilter ? "" : "package struct Filter {\n    package init() {}\n}\n\n"
		let appRootFilter = appRootForwardsFilter ? "\n    @Forwarded let filter: [3 of Int]" : ""
		let appRootInitializer = appRootForwardsFilter ? "public init(filter: [3 of Int], outer: Outer) {\n        self.filter = filter\n        self.outer = outer\n    }" : "public init(outer: Outer) {\n        self.outer = outer\n    }"
		return [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
			import SafeDI

			\(filterDeclaration)@Instantiable
			package struct TokenCache: Instantiable {
			    package init(filter: \(filterType)?) {
			        self.filter = filter
			    }

			    @Received(onlyIfAvailable: true) let filter: \(filterType)?
			}

			@Instantiable(generateMock: .public)
			public struct Service: Instantiable {
			    package init(tokenCache: TokenCache) {
			        self.tokenCache = tokenCache
			    }

			    @Instantiated let tokenCache: TokenCache
			}
			"""]),
			ModuleFixture(name: "Mid", packageName: "mid", swiftFileContentByFilePath: ["Outer.swift": """
			import Core
			import SafeDI

			@Instantiable(generateMock: .public)
			public struct Outer: Instantiable {
			    package init(service: Service) {
			        self.service = service
			    }

			    @Instantiated let service: Service
			}
			"""], dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["AppRoot.swift": """
			import Core
			import Mid
			import SafeDI

			@Instantiable(generateMock: true)
			public struct AppRoot: Instantiable {
			    \(appRootInitializer)
			\(appRootFilter)
			    @Instantiated let outer: Outer
			}
			"""], dependencies: ["Core", "Mid"]),
		]
	}

	/// R11's modules: `Core` generates its mocks under `TESTING`, and `App`, whose mock calls `Service`'s public mock,
	/// under `appMockCondition`, or `DEBUG` when it is `nil`.
	private static func mockConditionModules(appMockCondition: String?) -> [ModuleFixture] {
		[
			ModuleFixture(
				name: "Core",
				packageName: "pkg",
				swiftFileContentByFilePath: [
					"Service.swift": """
					import SafeDI

					@Instantiable
					package struct TokenCache: Instantiable {
					    package init() {}
					}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    package init(tokenCache: TokenCache) {
					        self.tokenCache = tokenCache
					    }

					    @Instantiated let tokenCache: TokenCache
					}
					""",
					"SafeDIConfiguration.swift": "#SafeDIConfiguration(mockConditionalCompilation: \"TESTING\")",
				],
				mockConditionalCompilation: "TESTING",
			),
			ModuleFixture(
				name: "App",
				packageName: "app",
				swiftFileContentByFilePath: [
					"Screen.swift": """
					import Core
					import SafeDI

					@Instantiable(generateMock: true)
					public struct Screen: Instantiable {
					    public init(service: Service) {
					        self.service = service
					    }

					    @Received let service: Service
					}
					""",
				].merging(appMockCondition.map { ["SafeDIConfiguration.swift": "#SafeDIConfiguration(mockConditionalCompilation: \"\($0)\")"] } ?? [:]) { first, _ in first },
				dependencies: ["Core"],
				mockConditionalCompilation: appMockCondition,
			),
		]
	}

	private static let canonicalBoard = """
	import Core
	import SafeDI

	@Instantiable
	public struct Wrapper: Instantiable {
	    public init(analytics: LazilyInstantiated<Analytics>, service: Service) {
	        self.analytics = analytics
	        self.service = service
	    }

	    @Instantiated let analytics: LazilyInstantiated<Analytics>
	    @Instantiated let service: Service
	}

	@Instantiable(generateMock: true)
	public struct Board: Instantiable {
	    public init(wrapperBuilder: SendableInstantiator<Wrapper>) {
	        self.wrapperBuilder = wrapperBuilder
	    }

	    @Instantiated let wrapperBuilder: SendableInstantiator<Wrapper>
	}
	"""

	/// M8.24's and M8.25's modules: `Service`, with a public mock, builds an `internal` `TokenCache`.
	private static func unknownModuleModules(omitsCoreModuleName: Bool, omitsAppModuleName: Bool = false) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
			import SafeDI

			@Instantiable
			struct TokenCache: Instantiable {
			    init() {}
			}

			@Instantiable(generateMock: .public)
			public struct Service: Instantiable {
			    init(tokenCache: TokenCache) {
			        self.tokenCache = tokenCache
			    }

			    @Instantiated let tokenCache: TokenCache
			}
			"""], omitsModuleName: omitsCoreModuleName),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(service: Service) {
			        self.service = service
			    }

			    @Received let service: Service
			}
			"""], dependencies: ["Core"], omitsModuleName: omitsAppModuleName),
		]
	}

	private static let canonicalScreen = """
	import Core
	import SafeDI

	@Instantiable(generateMock: true)
	public struct Screen: Instantiable {
	    public init(analytics: LazilyInstantiated<Analytics>, theme: Theme, service: Service) {
	        self.analytics = analytics
	        self.theme = theme
	        self.service = service
	    }

	    @Instantiated let analytics: LazilyInstantiated<Analytics>
	    @Instantiated let theme: Theme
	    @Received let service: Service
	}
	"""
}
