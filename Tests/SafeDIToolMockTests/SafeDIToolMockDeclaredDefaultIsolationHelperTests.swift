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
struct SafeDIToolMockDeclaredDefaultIsolationHelperTests: ~Copyable {
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

		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    @MainActor struct SafeDIOverrides {
			        init(
			            child: Child.SafeDIMockConfiguration? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                child: child ?? .init()
			            )
			        }

			        var child: Child.SafeDIMockConfiguration { __safeDI_storage.child }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                child: Child.SafeDIMockConfiguration
			            ) {
			                self.child = child
			            }

			            let child: Child.SafeDIMockConfiguration
			        }
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides? = nil
			    ) -> Root {
			        let safeDIOverrides = safeDIOverrides ?? .init()
			        func __safeDI_child() -> Child {
			            func __safeDI_grandchild() -> Grandchild {
			                return if let safeDIBuilder = safeDIOverrides.child.grandchild.safeDIBuilder { safeDIBuilder(safeDIOverrides.child.grandchild.name) } else { Grandchild(name: safeDIOverrides.child.grandchild.name) }
			            }
			            let grandchild: Grandchild = __safeDI_grandchild()
			            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(grandchild, safeDIOverrides.child.limit) } else { Child(grandchild: grandchild, limit: safeDIOverrides.child.limit) }
			        }
			        let child: Child = __safeDI_child()
			        return Root(child: child)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Grandchild {
			    /// Configuration for how this type is constructed within a mock tree.
			    @MainActor struct SafeDIMockConfiguration {
			        init(
			            name: String = "leaf",
			            _ safeDIBuilder: ((String) -> Grandchild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                name: name,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var name: String { __safeDI_storage.name }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((String) -> Grandchild)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                name: String,
			                safeDIBuilder: ((String) -> Grandchild)?
			            ) {
			                self.name = name
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let name: String
			            let safeDIBuilder: ((String) -> Grandchild)?
			        }
			    }
			}

			extension Child {
			    /// Configuration for how this type is constructed within a mock tree.
			    @MainActor struct SafeDIMockConfiguration {
			        init(
			            grandchild: Grandchild.SafeDIMockConfiguration? = nil,
			            limit: Int = 10,
			            _ safeDIBuilder: ((Grandchild, Int) -> Child)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grandchild: grandchild ?? .init(),
			                limit: limit,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var grandchild: Grandchild.SafeDIMockConfiguration { __safeDI_storage.grandchild }
			        var limit: Int { __safeDI_storage.limit }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Grandchild, Int) -> Child)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grandchild: Grandchild.SafeDIMockConfiguration,
			                limit: Int,
			                safeDIBuilder: ((Grandchild, Int) -> Child)?
			            ) {
			                self.grandchild = grandchild
			                self.limit = limit
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let grandchild: Grandchild.SafeDIMockConfiguration
			            let limit: Int
			            let safeDIBuilder: ((Grandchild, Int) -> Child)?
			        }
			    }
			}
			#endif

			""",
		])
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

		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    @MainActor struct SafeDIOverrides {
			        init(
			            grandchild: Grandchild.SafeDIMockConfiguration? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grandchild: grandchild ?? .init()
			            )
			        }

			        var grandchild: Grandchild.SafeDIMockConfiguration { __safeDI_storage.grandchild }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grandchild: Grandchild.SafeDIMockConfiguration
			            ) {
			                self.grandchild = grandchild
			            }

			            let grandchild: Grandchild.SafeDIMockConfiguration
			        }
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides? = nil
			    ) -> Root {
			        let safeDIOverrides = safeDIOverrides ?? .init()
			        func __safeDI_grandchild() -> Grandchild {
			            return if let safeDIBuilder = safeDIOverrides.grandchild.safeDIBuilder { safeDIBuilder(safeDIOverrides.grandchild.name) } else { Grandchild(name: safeDIOverrides.grandchild.name) }
			        }
			        let grandchild: Grandchild = __safeDI_grandchild()
			        return Root(grandchild: grandchild)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Grandchild {
			    /// Configuration for how this type is constructed within a mock tree.
			    @MainActor struct SafeDIMockConfiguration {
			        init(
			            name: String = "leaf",
			            _ safeDIBuilder: ((String) -> Grandchild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                name: name,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var name: String { __safeDI_storage.name }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((String) -> Grandchild)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                name: String,
			                safeDIBuilder: ((String) -> Grandchild)?
			            ) {
			                self.name = name
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let name: String
			            let safeDIBuilder: ((String) -> Grandchild)?
			        }
			    }
			}
			#endif

			""",
		])
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

		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    @MainActor struct SafeDIOverrides {
			        init(
			            grandchild: Grandchild.SafeDIMockConfiguration? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grandchild: grandchild ?? .init()
			            )
			        }

			        var grandchild: Grandchild.SafeDIMockConfiguration { __safeDI_storage.grandchild }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grandchild: Grandchild.SafeDIMockConfiguration
			            ) {
			                self.grandchild = grandchild
			            }

			            let grandchild: Grandchild.SafeDIMockConfiguration
			        }
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides? = nil
			    ) -> Root {
			        let safeDIOverrides = safeDIOverrides ?? .init()
			        func __safeDI_grandchild() -> Grandchild {
			            return if let safeDIBuilder = safeDIOverrides.grandchild.safeDIBuilder { safeDIBuilder(safeDIOverrides.grandchild.name) } else { Grandchild(name: safeDIOverrides.grandchild.name) }
			        }
			        let grandchild: Grandchild = __safeDI_grandchild()
			        return Root(grandchild: grandchild)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Grandchild {
			    /// Configuration for how this type is constructed within a mock tree.
			    @MainActor struct SafeDIMockConfiguration {
			        init(
			            name: String = "leaf",
			            _ safeDIBuilder: ((String) -> Grandchild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                name: name,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var name: String { __safeDI_storage.name }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((String) -> Grandchild)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                name: String,
			                safeDIBuilder: ((String) -> Grandchild)?
			            ) {
			                self.name = name
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let name: String
			            let safeDIBuilder: ((String) -> Grandchild)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test(arguments: [Build.swift6DefaultingToMainActor])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsHelpersAsToday_whenOwnerWritesMockAttributesInDeclaredModule(build: Build) async throws {
		// An owner whose `mockAttributes` text is written: SafeDI uses it exactly and spells its helpers as today. Compiled
		// under the main actor default only: without it, the owner’s `SafeDIOverrides` is nonisolated, and its default
		// `.init()` of the `@MainActor` configuration SafeDI gives `Grandchild` is “main actor-isolated default value in a
		// nonisolated context”.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Grandchild: Instantiable {
				    public init(name: String = "leaf") {}
				}
				""",
				"""
				@Instantiable(mockAttributes: "@MainActor", generateMock: true)
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

		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            grandchild: Grandchild.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grandchild: grandchild
			            )
			        }

			        var grandchild: Grandchild.SafeDIMockConfiguration { __safeDI_storage.grandchild }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grandchild: Grandchild.SafeDIMockConfiguration
			            ) {
			                self.grandchild = grandchild
			            }

			            let grandchild: Grandchild.SafeDIMockConfiguration
			        }
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_grandchild() -> Grandchild {
			            return if let safeDIBuilder = safeDIOverrides.grandchild.safeDIBuilder { safeDIBuilder(safeDIOverrides.grandchild.name) } else { Grandchild(name: safeDIOverrides.grandchild.name) }
			        }
			        let grandchild: Grandchild = __safeDI_grandchild()
			        return Root(grandchild: grandchild)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Grandchild {
			    /// Configuration for how this type is constructed within a mock tree.
			    @MainActor struct SafeDIMockConfiguration {
			        init(
			            name: String = "leaf",
			            _ safeDIBuilder: ((String) -> Grandchild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                name: name,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var name: String { __safeDI_storage.name }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((String) -> Grandchild)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                name: String,
			                safeDIBuilder: ((String) -> Grandchild)?
			            ) {
			                self.name = name
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let name: String
			            let safeDIBuilder: ((String) -> Grandchild)?
			        }
			    }
			}
			#endif

			""",
		])
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

		#expect(output.generatedFiles == [
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
			            return if let safeDIBuilder = safeDIOverrides.client.safeDIBuilder { safeDIBuilder(safeDIOverrides.client.timeout) } else { Client.mock(timeout: safeDIOverrides.client.timeout) }
			        }
			        let client: Client = __safeDI_client()
			        return Root(client: client)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Client {
			    /// Configuration for how this type is constructed within a mock tree.
			    @MainActor struct SafeDIMockConfiguration {
			        init(
			            timeout: Int = 5,
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
		])
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
				#SafeDIConfiguration(additionalMocksToGenerate: ["Root"], defaultIsolation: MainActor.self)
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: build.settings,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    @MainActor struct SafeDIOverrides {
			        init(
			            grandchild: Grandchild.SafeDIMockConfiguration? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grandchild: grandchild ?? .init()
			            )
			        }

			        var grandchild: Grandchild.SafeDIMockConfiguration { __safeDI_storage.grandchild }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grandchild: Grandchild.SafeDIMockConfiguration
			            ) {
			                self.grandchild = grandchild
			            }

			            let grandchild: Grandchild.SafeDIMockConfiguration
			        }
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides? = nil
			    ) -> Root {
			        let safeDIOverrides = safeDIOverrides ?? .init()
			        func __safeDI_grandchild() -> Grandchild {
			            return if let safeDIBuilder = safeDIOverrides.grandchild.safeDIBuilder { safeDIBuilder(safeDIOverrides.grandchild.name) } else { Grandchild(name: safeDIOverrides.grandchild.name) }
			        }
			        let grandchild: Grandchild = __safeDI_grandchild()
			        return Root(grandchild: grandchild)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Grandchild {
			    /// Configuration for how this type is constructed within a mock tree.
			    @MainActor struct SafeDIMockConfiguration {
			        init(
			            name: String = "leaf",
			            _ safeDIBuilder: ((String) -> Grandchild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                name: name,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var name: String { __safeDI_storage.name }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((String) -> Grandchild)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                name: String,
			                safeDIBuilder: ((String) -> Grandchild)?
			            ) {
			                self.name = name
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let name: String
			            let safeDIBuilder: ((String) -> Grandchild)?
			        }
			    }
			}
			#endif

			""",
		])
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

		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    @MainActor struct SafeDIOverrides {
			        init(
			            a: A.SafeDIMockConfiguration? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                a: a ?? .init()
			            )
			        }

			        var a: A.SafeDIMockConfiguration { __safeDI_storage.a }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                a: A.SafeDIMockConfiguration
			            ) {
			                self.a = a
			            }

			            let a: A.SafeDIMockConfiguration
			        }
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides? = nil
			    ) -> Root {
			        let safeDIOverrides = safeDIOverrides ?? .init()
			        func __safeDI_a() -> A {
			            func __safeDI_bBuilder() -> B {
			                func __safeDI_aBuilder() -> A {
			                    let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                    return A(bBuilder: bBuilder)
			                }
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                return if let safeDIBuilder = safeDIOverrides.a.bBuilder.safeDIBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			            }
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.a.safeDIBuilder { safeDIBuilder(bBuilder, safeDIOverrides.a.label) } else { A(bBuilder: bBuilder, label: safeDIOverrides.a.label) }
			        }
			        let a: A = __safeDI_a()
			        return Root(a: a)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension B {
			    /// Configuration for how this type is constructed within a mock tree.
			    @MainActor struct SafeDIMockConfiguration {
			        init(
			            _ safeDIBuilder: ((Instantiator<A>) -> B)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Instantiator<A>) -> B)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                safeDIBuilder: ((Instantiator<A>) -> B)?
			            ) {
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let safeDIBuilder: ((Instantiator<A>) -> B)?
			        }
			    }
			}

			extension A {
			    /// Configuration for how this type is constructed within a mock tree.
			    @MainActor struct SafeDIMockConfiguration {
			        init(
			            bBuilder: B.SafeDIMockConfiguration? = nil,
			            label: String = "a",
			            _ safeDIBuilder: ((Instantiator<B>, String) -> A)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                bBuilder: bBuilder ?? .init(),
			                label: label,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var bBuilder: B.SafeDIMockConfiguration { __safeDI_storage.bBuilder }
			        var label: String { __safeDI_storage.label }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Instantiator<B>, String) -> A)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                bBuilder: B.SafeDIMockConfiguration,
			                label: String,
			                safeDIBuilder: ((Instantiator<B>, String) -> A)?
			            ) {
			                self.bBuilder = bBuilder
			                self.label = label
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let bBuilder: B.SafeDIMockConfiguration
			            let label: String
			            let safeDIBuilder: ((Instantiator<B>, String) -> A)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test(arguments: [Build.swift6DefaultingToMainActor])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsPublicHelpersNonisolated_whenPublicMocksChainInDeclaredModule(build: Build) async throws {
		// The public mocks chain of a protocol, an actor and a class: `mock()` takes `@MainActor`, the public helpers stay
		// `nonisolated`. Compiled under the main actor default only: without it, `Store`’s `@MainActor` mock sends the
		// `Client` it builds, which is not `Sendable`, to the actor’s initializer, which Swift 6 rejects
		// (#SendingRisksDataRace), in `mock()` and in `Store.__safeDI_init`.
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

		#expect(output.generatedFiles == [
			"Client+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Client {
			    @MainActor public static func mock(
			        timeout: Int? = nil
			    ) -> Client {
			        Client.__safeDI_mock(timeout: timeout)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    @MainActor public static func __safeDI_mock(
			        timeout: Int? = nil
			    ) -> Client {
			        let timeout = timeout ?? (30)
			        return Client(timeout: timeout)
			    }
			}

			extension Client {
			    public enum __safeDI_Client_mock_641EE6583CCA40BE {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Client` is constructed within the public mock trees of this module.
			nonisolated public struct __safeDI_Client_MockConfiguration {
			    public init(
			        timeout: Int? = nil,
			        _ safeDIBuilder: ((Int) -> Client)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            timeout: timeout,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// `nil` keeps the default of `Client`’s `timeout`.
			    public var timeout: Int? { __safeDI_storage.timeout }
			    /// Overrides how `Client` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Int) -> Client)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            timeout: Int?,
			            safeDIBuilder: ((Int) -> Client)?
			        ) {
			            self.timeout = timeout
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let timeout: Int?
			        let safeDIBuilder: ((Int) -> Client)?
			    }
			}

			extension Client {
			    static func __safeDI_init(timeout: Int?, safeDIBuilder: ((Int) -> Client)?) -> Client {
			        let timeout = timeout ?? (30)
			        return if let safeDIBuilder { safeDIBuilder(timeout) } else { Client(timeout: timeout) }
			    }
			}

			/// Configuration for how `Store` is constructed within the public mock trees of this module.
			nonisolated public struct __safeDI_Store_MockConfiguration {
			    public init(
			        client: __safeDI_Client_MockConfiguration = .init(),
			        _ safeDIBuilder: ((Client) -> Store)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            client: client,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var client: __safeDI_Client_MockConfiguration { __safeDI_storage.client }
			    /// Overrides how `Store` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Client) -> Store)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            client: __safeDI_Client_MockConfiguration,
			            safeDIBuilder: ((Client) -> Store)?
			        ) {
			            self.client = client
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let client: __safeDI_Client_MockConfiguration
			        let safeDIBuilder: ((Client) -> Store)?
			    }
			}

			extension Store {
			    static func __safeDI_init(client: Client, safeDIBuilder: ((Client) -> Store)?) -> Store {
			        if let safeDIBuilder { safeDIBuilder(client) } else { Store(client: client) }
			    }
			}
			#endif

			""",
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            store: __safeDI_Store_MockConfiguration = .init(),
			            client: __safeDI_Client_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                store: store,
			                client: client
			            )
			        }

			        public var store: __safeDI_Store_MockConfiguration { __safeDI_storage.store }
			        public var client: __safeDI_Client_MockConfiguration { __safeDI_storage.client }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                store: __safeDI_Store_MockConfiguration,
			                client: __safeDI_Client_MockConfiguration
			            ) {
			                self.store = store
			                self.client = client
			            }

			            let store: __safeDI_Store_MockConfiguration
			            let client: __safeDI_Client_MockConfiguration
			        }
			    }

			    @MainActor public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    @MainActor public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_store() -> Store {
			            func __safeDI_client() -> Client {
			                return Client.__safeDI_init(timeout: safeDIOverrides.store.client.timeout, safeDIBuilder: safeDIOverrides.store.client.safeDIBuilder)
			            }
			            let client: Client = __safeDI_client()
			            return Store.__safeDI_init(client: client, safeDIBuilder: safeDIOverrides.store.safeDIBuilder)
			        }
			        let store: Store = __safeDI_store()
			        func __safeDI_client() -> Client {
			            return Client.__safeDI_init(timeout: safeDIOverrides.client.timeout, safeDIBuilder: safeDIOverrides.client.safeDIBuilder)
			        }
			        let client: Client = __safeDI_client()
			        return Screen(store: store, client: client)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
			"Store+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Store {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            client: __safeDI_Client_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                client: client
			            )
			        }

			        public var client: __safeDI_Client_MockConfiguration { __safeDI_storage.client }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                client: __safeDI_Client_MockConfiguration
			            ) {
			                self.client = client
			            }

			            let client: __safeDI_Client_MockConfiguration
			        }
			    }

			    @MainActor public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Store {
			        Store.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    @MainActor public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Store {
			        func __safeDI_client() -> Client {
			            return Client.__safeDI_init(timeout: safeDIOverrides.client.timeout, safeDIBuilder: safeDIOverrides.client.safeDIBuilder)
			        }
			        let client: Client = __safeDI_client()
			        return Store(client: client)
			    }
			}

			extension Store {
			    public enum __safeDI_Store_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
		])
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

		#expect(output.modules["Outer"]?.generatedFiles == [
			"Outer.swift": generatedFileHeader + """
			#if canImport(Inner)
			import Inner
			#endif

			#if DEBUG
			extension Home {
			    /// Overrides for the mock dependency tree.
			    @MainActor struct SafeDIOverrides {
			        init(
			            detail: ((@escaping () -> any Api) -> Detail)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                detail: detail
			            )
			        }

			        var detail: ((@escaping () -> any Api) -> Detail)? { __safeDI_storage.detail }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                detail: ((@escaping () -> any Api) -> Detail)?
			            ) {
			                self.detail = detail
			            }

			            let detail: ((@escaping () -> any Api) -> Detail)?
			        }
			    }

			    @MainActor static func mock(
			        apiBuilder: (() -> any Api)? = nil,
			        safeDIOverrides: SafeDIOverrides? = nil
			    ) -> Home {
			        let safeDIOverrides = safeDIOverrides ?? .init()
			        func __safeDI_detail() -> Detail {
			            func __safeDI_apiBuilder_Detail_api() -> any Api {
			                let api: any Api = ApiImpl()
			                return api
			            }
			            func __safeDI_apiBuilder_Detail() -> Detail.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
			                .init(api: { _ in __safeDI_apiBuilder_Detail_api() })
			            }
			            _ = Detail.__safeDI_Detail_mock_84DC57D5B04EB47D.self // If this line does not compile, compile the code SafeDI generates for module Inner into Inner: under Bazel, add Inner’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return if let safeDIBuilder = safeDIOverrides.detail { safeDIBuilder({ if let apiBuilder { apiBuilder() } else { __safeDI_apiBuilder_Detail_api() } }) } else { Detail.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_Detail()) }
			        }
			        let detail: Detail = __safeDI_detail()
			        return Home(detail: detail)
			    }
			}
			#endif
			""",
		])
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
