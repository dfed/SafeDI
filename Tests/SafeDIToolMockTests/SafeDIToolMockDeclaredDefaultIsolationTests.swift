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

/// In a module that declares `#SafeDIConfiguration(defaultIsolation: MainActor.self)`, a type whose attribute text is
/// empty gets `@MainActor` on its `mock()`, and its mock's helper types take that isolation too: the internal
/// `SafeDIOverrides` and the plain-form `SafeDIMockConfiguration` are `@MainActor struct`s, and their `.init()` default
/// parameters default to `nil` instead, resolved first thing in the body, since Swift 5 mode evaluates a default argument
/// outside the function's isolation. A `@Sendable`-typed configuration and a public mock's helper types keep their form,
/// and a type whose attribute text is written keeps today's helpers. Each output compiles with and without
/// `-default-isolation MainActor`, and the shapes that show why the `nil` defaults are needed also in Swift 5 mode.
struct SafeDIToolMockDeclaredDefaultIsolationTests: ~Copyable {
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

	@Test(arguments: Build.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsHelpersMainActorWithNilDefaults_whenActorBuildsPlainTypeWithDefaultInDeclaredModule(build: Build) async throws {
		// #1016's reproduction: an actor whose mock builds a plain type that takes a default-valued parameter.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Client: Instantiable, Sendable {
				    public init(timeout: Int = 30) {}
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public actor Root: Instantiable {
				    public init(client: Client) {
				        self.client = client
				    }

				    @Instantiated let client: Client
				}
				""",
			],
			swiftFileContentByFilePath: Self.declaredConfiguration,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: build.settings,
		)

		#expect(output.generatedFiles == [
			"Client+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Client {
			    @MainActor static func mock(
			        timeout: Int = 30
			    ) -> Client {
			        return Client(timeout: timeout)
			    }
			}
			#endif

			#if DEBUG
			extension Client {
			    /// Configuration for how this type is constructed within a mock tree.
			    @MainActor struct SafeDIMockConfiguration {
			        init(
			            timeout: Int = 30,
			            _ safeDIBuilder: ((Int) -> Client)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                timeout: timeout,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var timeout: Int { __safeDI_storage.timeout }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int) -> Client)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                timeout: Int,
			                safeDIBuilder: ((Int) -> Client)?
			            ) {
			                self.timeout = timeout
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let timeout: Int
			            let safeDIBuilder: ((Int) -> Client)?
			        }
			    }
			}
			#endif
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    @MainActor struct SafeDIOverrides {
			        init(
			            client: Client.SafeDIMockConfiguration? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                client: client ?? .init()
			            )
			        }

			        var client: Client.SafeDIMockConfiguration { __safeDI_storage.client }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                client: Client.SafeDIMockConfiguration
			            ) {
			                self.client = client
			            }

			            let client: Client.SafeDIMockConfiguration
			        }
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides? = nil
			    ) -> Root {
			        let safeDIOverrides = safeDIOverrides ?? .init()
			        func __safeDI_client() -> Client {
			            return if let safeDIBuilder = safeDIOverrides.client.safeDIBuilder { safeDIBuilder(safeDIOverrides.client.timeout) } else { Client(timeout: safeDIOverrides.client.timeout) }
			        }
			        let client: Client = __safeDI_client()
			        return Root(client: client)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test(arguments: Build.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_resolvesNestedConfigurationsInBody_whenPlainOwnerBuildsConfiguredChildrenInDeclaredModule(build: Build) async throws {
		// A plain owner whose child's configuration nests its own child's: each nested configuration defaults to `nil`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(grandchild: Grandchild, limit: Int = 10) {
				        self.grandchild = grandchild
				    }

				    @Instantiated let grandchild: Grandchild
				}
				""",
				"""
				@Instantiable
				public final class Grandchild: Instantiable {
				    public init(name: String = "leaf") {}
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(child: Child) {
				        self.child = child
				    }

				    @Instantiated let child: Child
				}
				""",
			],
			swiftFileContentByFilePath: Self.declaredConfiguration,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: build.settings,
		)

		#expect(output.generatedFiles == [:])
	}

	@Test(arguments: Build.swift6Builds)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsHelpersMainActor_whenOwnerIsMainActorThroughProtocolInDeclaredModule(build: Build) async throws {
		// An owner on the main actor only through a protocol it conforms to.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				public protocol Screen {}
				""",
				"""
				@Instantiable
				public final class Grandchild: Instantiable {
				    public init(name: String = "leaf") {}
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Screen {
				    public init(grandchild: Grandchild) {
				        self.grandchild = grandchild
				    }

				    @Instantiated let grandchild: Grandchild
				}
				""",
			],
			swiftFileContentByFilePath: Self.declaredConfiguration,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: build.settings,
		)

		#expect(output.generatedFiles == [:])
	}

	@Test(arguments: Build.swift6Builds)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsHelpersMainActor_whenOwnerIsSpelledNonisolatedInDeclaredModule(build: Build) async throws {
		// An owner spelled `nonisolated`, whose attribute text is still empty, so SafeDI supplies `@MainActor` to its mock.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Grandchild: Instantiable {
				    public init(name: String = "leaf") {}
				}
				""",
				"""
				@Instantiable(generateMock: true)
				nonisolated public final class Root: Instantiable {
				    public init(grandchild: Grandchild) {
				        self.grandchild = grandchild
				    }

				    @Instantiated let grandchild: Grandchild
				}
				""",
			],
			swiftFileContentByFilePath: Self.declaredConfiguration,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: build.settings,
		)

		#expect(output.generatedFiles == [:])
	}

	@Test(arguments: Build.swift6Builds)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsHelpersAsToday_whenOwnerWritesMockAttributesInDeclaredModule(build: Build) async throws {
		// An owner whose `mockAttributes` text is written: SafeDI uses it exactly and spells its helpers as today.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Grandchild: Instantiable {
				    public init(name: String = "leaf") {}
				}
				""",
				"""
				@Instantiable(generateMock: true, mockAttributes: "@MainActor")
				public final class Root: Instantiable {
				    public init(grandchild: Grandchild) {
				        self.grandchild = grandchild
				    }

				    @Instantiated let grandchild: Grandchild
				}
				""",
			],
			swiftFileContentByFilePath: Self.declaredConfiguration,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: build.settings,
		)

		#expect(output.generatedFiles == [:])
	}

	@Test(arguments: Build.swift6Builds)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsConfigurationMainActor_whenChildHasMockOnlyMockInDeclaredModule(build: Build) async throws {
		// A `mockOnly` pair: the child is built with its hand-written mock, whose defaults its configuration takes.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Client: Instantiable {
				    public init(timeout: Int = 30) {}
				}
				""",
				"""
				@Instantiable(mockOnly: true)
				extension Client {
				    public static func mock(timeout: Int = 5) -> Client {
				        Client(timeout: timeout)
				    }
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(client: Client) {
				        self.client = client
				    }

				    @Instantiated let client: Client
				}
				""",
			],
			swiftFileContentByFilePath: Self.declaredConfiguration,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: build.settings,
		)

		#expect(output.generatedFiles == [:])
	}

	@Test(arguments: Build.swift6Builds)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsHelpersMainActor_whenAdditionalMocksToGenerateNamesTypeInDeclaredModule(build: Build) async throws {
		// A mock `additionalMocksToGenerate` asks for: the generating module's setting applies.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Grandchild: Instantiable {
				    public init(name: String = "leaf") {}
				}
				""",
				"""
				@Instantiable
				public final class Root: Instantiable {
				    public init(grandchild: Grandchild) {
				        self.grandchild = grandchild
				    }

				    @Instantiated let grandchild: Grandchild
				}
				""",
			],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration(defaultIsolation: MainActor.self, additionalMocksToGenerate: ["Root"])
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: build.settings,
		)

		#expect(output.generatedFiles == [:])
	}

	@Test(arguments: Build.swift6Builds)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_resolvesCycleClosingConfigurationInBody_whenOwnerBuildsCycleInDeclaredModule(build: Build) async throws {
		// A cycle through instantiators: the configuration of the node that closes it is its type's, defaulted to `nil` too.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class A: Instantiable {
				    public init(bBuilder: Instantiator<B>, label: String = "a") {
				        self.bBuilder = bBuilder
				    }

				    @Instantiated let bBuilder: Instantiator<B>
				}
				""",
				"""
				@Instantiable
				public final class B: Instantiable {
				    public init(aBuilder: Instantiator<A>) {
				        self.aBuilder = aBuilder
				    }

				    @Instantiated let aBuilder: Instantiator<A>
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(a: A) {
				        self.a = a
				    }

				    @Instantiated let a: A
				}
				""",
			],
			swiftFileContentByFilePath: Self.declaredConfiguration,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: build.settings,
		)

		#expect(output.generatedFiles == [:])
	}

	@Test(arguments: Build.swift6Builds)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsPublicHelpersNonisolated_whenPublicMocksChainInDeclaredModule(build: Build) async throws {
		// The public mocks chain of a protocol, an actor and a class: `mock()` takes `@MainActor`, the public helpers stay `nonisolated`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol Helping {}
				""",
				"""
				@Instantiable(generateMock: .public)
				public final class Client: Instantiable, Helping {
				    public init(timeout: Int = 30) {}
				}
				""",
				"""
				@Instantiable(generateMock: .public)
				public actor Store: Instantiable {
				    public init(client: Client) {
				        self.client = client
				    }

				    @Instantiated let client: Client
				}
				""",
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(store: Store, client: Client) {
				        self.store = store
				        self.client = client
				    }

				    @Instantiated let store: Store
				    @Instantiated let client: Client
				}
				""",
			],
			swiftFileContentByFilePath: Self.declaredConfiguration,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: build.settings,
		)

		#expect(output.generatedFiles == [:])
	}

	@Test(arguments: Build.swift6Builds)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsCallingMocksHelpersMainActor_whenItFillsCalledPublicMocksPlaceInDeclaredModule(build: Build) async throws {
		// A calling mock in a declared module that fills the place of another module's public mock: its overrides hold the
		// called mock's `nonisolated` overrides, defaulted to `nil` too.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Inner", packageName: "Shop", swiftFileContent: [
					"public protocol Api {}",
					"""
					@Instantiable(generateMock: .public)
					public final class Detail: Instantiable {
					    init(api: any Api) {
					        self.api = api
					    }

					    @Instantiated public let api: any Api
					}
					""",
				]),
				ModuleFixture(
					name: "Outer",
					packageName: "Other",
					swiftFileContent: [
						"""
						import Inner

						@Instantiable(fulfillingAdditionalTypes: [Api.self])
						public final class ApiImpl: Api, Instantiable {
						    public init() {}
						}
						""",
						"""
						import Inner

						@Instantiable(generateMock: true)
						public final class Home: Instantiable {
						    public init(detail: Detail) {
						        self.detail = detail
						    }

						    @Instantiated let detail: Detail
						}
						""",
					],
					swiftFileContentByFilePath: Self.declaredConfiguration,
					dependencies: ["Inner"],
					compilerSettings: build.settings,
				),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["Outer"]?.generatedFiles == [:])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The configuration that declares the module's default isolation.
	private static let declaredConfiguration = [
		"SafeDIConfiguration.swift": """
		#SafeDIConfiguration(defaultIsolation: MainActor.self)
		""",
	]

	/// How each test's generated code is compiled: Swift 6 with and without `-default-isolation MainActor`, and Swift 5
	/// mode with it, where a default argument is evaluated outside the function's isolation.
	enum Build: CaseIterable, CustomTestStringConvertible {
		case swift6
		case swift6DefaultingToMainActor
		case swift5DefaultingToMainActor

		var settings: VerificationCompilerSettings {
			switch self {
			case .swift6:
				VerificationCompilerSettings()
			case .swift6DefaultingToMainActor:
				VerificationCompilerSettings(defaultIsolation: "MainActor")
			case .swift5DefaultingToMainActor:
				VerificationCompilerSettings(swiftLanguageMode: "5", defaultIsolation: "MainActor")
			}
		}

		/// Swift 6 with and without the main actor default.
		static let swift6Builds = [Build.swift6, .swift6DefaultingToMainActor]

		var testDescription: String {
			switch self {
			case .swift6: "Swift 6"
			case .swift6DefaultingToMainActor: "Swift 6, main actor default"
			case .swift5DefaultingToMainActor: "Swift 5, main actor default"
			}
		}
	}
}
