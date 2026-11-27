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

/// A configuration that takes the `Sendable` form (its type is built in a `@Sendable` function) is declared
/// `nonisolated struct SafeDIMockConfiguration: Sendable`, so `@Sendable nonisolated` functions and an actor's `mock()` can
/// read it in a module whose declarations default to the main actor. A plain configuration keeps the module's isolation, so
/// its default values may call main-actor code. Each cell compiles in the kind of module it names.
struct SafeDIToolMockSendableConfigurationIsolationTests: ~Copyable {
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_declaresSendableConfigurationNonisolated_whenModuleDefaultsToMainActor() async throws {
		// A configuration a `@Sendable nonisolated` function reads is `nonisolated` and `Sendable`, so that function can read it
		// in a module whose declarations default to the main actor. Its defaults are a literal, a static member and an
		// autoclosure; a call to a main-actor initializer is no default of a type built in a `@Sendable` function, whose
		// initializer is then `nonisolated` and cannot evaluate it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				/// A default value a `nonisolated` initializer can read in every kind of module.
				nonisolated public struct Policy: Sendable {
				    public static let standard = Policy()
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Client: Instantiable, Sendable {
				    public nonisolated init(timeout: Int = 30, policy: Policy = Policy.standard, name: @autoclosure @escaping () -> String = "client") {}
				}
				""",
				"""
				@Instantiable(generatedAttributes: "@MainActor", generateMock: true)
				public final class Root: Instantiable {
				    public init(client: Client, clientBuilder: SendableInstantiator<Client>) {
				        self.client = client
				        self.clientBuilder = clientBuilder
				    }

				    /// `Client` is built outside a `Sendable` wrapper here and inside one below, so its configuration takes the `Sendable` form.
				    @Instantiated let client: Client
				    @Instantiated let clientBuilder: SendableInstantiator<Client>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: "MainActor"),
		)

		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            client: Client.SafeDIMockConfiguration = .init(),
			            clientBuilder: Client.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                client: client,
			                clientBuilder: clientBuilder
			            )
			        }

			        var client: Client.SafeDIMockConfiguration { __safeDI_storage.client }
			        var clientBuilder: Client.SafeDIMockConfiguration { __safeDI_storage.clientBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                client: Client.SafeDIMockConfiguration,
			                clientBuilder: Client.SafeDIMockConfiguration
			            ) {
			                self.client = client
			                self.clientBuilder = clientBuilder
			            }

			            let client: Client.SafeDIMockConfiguration
			            let clientBuilder: Client.SafeDIMockConfiguration
			        }
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_client() -> Client {
			            return if let safeDIBuilder = safeDIOverrides.client.safeDIBuilder { safeDIBuilder(safeDIOverrides.client.timeout(), safeDIOverrides.client.policy(), safeDIOverrides.client.name()) } else { Client(timeout: safeDIOverrides.client.timeout(), policy: safeDIOverrides.client.policy(), name: safeDIOverrides.client.name()) }
			        }
			        let client: Client = __safeDI_client()
			        let __safeDI_clientBuilder__overrides = safeDIOverrides.clientBuilder
			        @Sendable nonisolated func __safeDI_clientBuilder() -> Client {
			            if let safeDIBuilder = __safeDI_clientBuilder__overrides.safeDIBuilder { safeDIBuilder(__safeDI_clientBuilder__overrides.timeout(), __safeDI_clientBuilder__overrides.policy(), __safeDI_clientBuilder__overrides.name()) } else { Client(timeout: __safeDI_clientBuilder__overrides.timeout(), policy: __safeDI_clientBuilder__overrides.policy(), name: __safeDI_clientBuilder__overrides.name()) }
			        }
			        let clientBuilder = SendableInstantiator<Client>(__safeDI_clientBuilder)
			        return Root(client: client, clientBuilder: clientBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Client {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            timeout: @autoclosure @escaping @Sendable () -> Int = 30,
			            policy: @autoclosure @escaping @Sendable () -> Policy = Policy.standard,
			            name: @autoclosure @escaping @Sendable () -> String = "client",
			            _ safeDIBuilder: (@Sendable (Int, Policy, String) -> Client)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                timeout: timeout,
			                policy: policy,
			                name: name,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var timeout: @Sendable () -> Int { __safeDI_storage.timeout }
			        var policy: @Sendable () -> Policy { __safeDI_storage.policy }
			        var name: @Sendable () -> String { __safeDI_storage.name }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Int, Policy, String) -> Client)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                timeout: @escaping @Sendable () -> Int,
			                policy: @escaping @Sendable () -> Policy,
			                name: @escaping @Sendable () -> String,
			                safeDIBuilder: (@Sendable (Int, Policy, String) -> Client)?
			            ) {
			                self.timeout = timeout
			                self.policy = policy
			                self.name = name
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let timeout: @Sendable () -> Int
			            let policy: @Sendable () -> Policy
			            let name: @Sendable () -> String
			            let safeDIBuilder: (@Sendable (Int, Policy, String) -> Client)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_declaresSendableConfigurationNonisolated_whenModuleIsNonisolatedByDefault() async throws {
		// The same configuration in a module whose declarations are nonisolated by default.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				/// A default value a `nonisolated` initializer can read in every kind of module.
				nonisolated public struct Policy: Sendable {
				    public static let standard = Policy()
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Client: Instantiable, Sendable {
				    public nonisolated init(timeout: Int = 30, policy: Policy = Policy.standard, name: @autoclosure @escaping () -> String = "client") {}
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(client: Client, clientBuilder: SendableInstantiator<Client>) {
				        self.client = client
				        self.clientBuilder = clientBuilder
				    }

				    /// `Client` is built outside a `Sendable` wrapper here and inside one below, so its configuration takes the `Sendable` form.
				    @Instantiated let client: Client
				    @Instantiated let clientBuilder: SendableInstantiator<Client>
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
			    struct SafeDIOverrides {
			        init(
			            client: Client.SafeDIMockConfiguration = .init(),
			            clientBuilder: Client.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                client: client,
			                clientBuilder: clientBuilder
			            )
			        }

			        var client: Client.SafeDIMockConfiguration { __safeDI_storage.client }
			        var clientBuilder: Client.SafeDIMockConfiguration { __safeDI_storage.clientBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                client: Client.SafeDIMockConfiguration,
			                clientBuilder: Client.SafeDIMockConfiguration
			            ) {
			                self.client = client
			                self.clientBuilder = clientBuilder
			            }

			            let client: Client.SafeDIMockConfiguration
			            let clientBuilder: Client.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_client() -> Client {
			            return if let safeDIBuilder = safeDIOverrides.client.safeDIBuilder { safeDIBuilder(safeDIOverrides.client.timeout(), safeDIOverrides.client.policy(), safeDIOverrides.client.name()) } else { Client(timeout: safeDIOverrides.client.timeout(), policy: safeDIOverrides.client.policy(), name: safeDIOverrides.client.name()) }
			        }
			        let client: Client = __safeDI_client()
			        let __safeDI_clientBuilder__overrides = safeDIOverrides.clientBuilder
			        @Sendable nonisolated func __safeDI_clientBuilder() -> Client {
			            if let safeDIBuilder = __safeDI_clientBuilder__overrides.safeDIBuilder { safeDIBuilder(__safeDI_clientBuilder__overrides.timeout(), __safeDI_clientBuilder__overrides.policy(), __safeDI_clientBuilder__overrides.name()) } else { Client(timeout: __safeDI_clientBuilder__overrides.timeout(), policy: __safeDI_clientBuilder__overrides.policy(), name: __safeDI_clientBuilder__overrides.name()) }
			        }
			        let clientBuilder = SendableInstantiator<Client>(__safeDI_clientBuilder)
			        return Root(client: client, clientBuilder: clientBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Client {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            timeout: @autoclosure @escaping @Sendable () -> Int = 30,
			            policy: @autoclosure @escaping @Sendable () -> Policy = Policy.standard,
			            name: @autoclosure @escaping @Sendable () -> String = "client",
			            _ safeDIBuilder: (@Sendable (Int, Policy, String) -> Client)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                timeout: timeout,
			                policy: policy,
			                name: name,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var timeout: @Sendable () -> Int { __safeDI_storage.timeout }
			        var policy: @Sendable () -> Policy { __safeDI_storage.policy }
			        var name: @Sendable () -> String { __safeDI_storage.name }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Int, Policy, String) -> Client)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                timeout: @escaping @Sendable () -> Int,
			                policy: @escaping @Sendable () -> Policy,
			                name: @escaping @Sendable () -> String,
			                safeDIBuilder: (@Sendable (Int, Policy, String) -> Client)?
			            ) {
			                self.timeout = timeout
			                self.policy = policy
			                self.name = name
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let timeout: @Sendable () -> Int
			            let policy: @Sendable () -> Policy
			            let name: @Sendable () -> String
			            let safeDIBuilder: (@Sendable (Int, Policy, String) -> Client)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsPlainConfigurationInModuleIsolation_whenModuleDefaultsToMainActorAndDefaultCallsMainActorInitializer() async throws {
		// A plain configuration keeps the module’s isolation, so its initializer can evaluate defaults that call main-actor
		// code: a static member of a main-actor type and a call to a main-actor initializer, beside a literal and an autoclosure.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				/// Isolated to the main actor where the module's declarations default to it.
				public struct Policy: Sendable {
				    public static let standard = Policy()
				    public init() {}
				}
				""",
				"""
				@MainActor
				public final class Theme {
				    public init() {}
				}
				""",
				"""
				@Instantiable @MainActor
				public final class Client: Instantiable {
				    public init(timeout: Int = 30, policy: Policy = Policy.standard, theme: Theme = Theme(), name: @autoclosure @escaping () -> String = "client") {}
				}
				""",
				"""
				@Instantiable(generateMock: true) @MainActor
				public final class Root: Instantiable {
				    public init(client: Client) {
				        self.client = client
				    }

				    /// `Client` is built only outside `Sendable` wrappers, so its configuration takes the plain form.
				    @Instantiated let client: Client
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: "MainActor"),
		)

		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            client: Client.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                client: client
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

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_client() -> Client {
			            return if let safeDIBuilder = safeDIOverrides.client.safeDIBuilder { safeDIBuilder(safeDIOverrides.client.timeout, safeDIOverrides.client.policy, safeDIOverrides.client.theme, safeDIOverrides.client.name()) } else { Client(timeout: safeDIOverrides.client.timeout, policy: safeDIOverrides.client.policy, theme: safeDIOverrides.client.theme, name: safeDIOverrides.client.name()) }
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
			    struct SafeDIMockConfiguration {
			        init(
			            timeout: Int = 30,
			            policy: Policy = Policy.standard,
			            theme: Theme = Theme(),
			            name: @autoclosure @escaping () -> String = "client",
			            _ safeDIBuilder: ((Int, Policy, Theme, String) -> Client)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                timeout: timeout,
			                policy: policy,
			                theme: theme,
			                name: name,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var timeout: Int { __safeDI_storage.timeout }
			        var policy: Policy { __safeDI_storage.policy }
			        var theme: Theme { __safeDI_storage.theme }
			        var name: () -> String { __safeDI_storage.name }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int, Policy, Theme, String) -> Client)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                timeout: Int,
			                policy: Policy,
			                theme: Theme,
			                name: @escaping () -> String,
			                safeDIBuilder: ((Int, Policy, Theme, String) -> Client)?
			            ) {
			                self.timeout = timeout
			                self.policy = policy
			                self.theme = theme
			                self.name = name
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let timeout: Int
			            let policy: Policy
			            let theme: Theme
			            let name: () -> String
			            let safeDIBuilder: ((Int, Policy, Theme, String) -> Client)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsPlainConfigurationInModuleIsolation_whenModuleIsNonisolatedByDefault() async throws {
		// A plain configuration in a module whose declarations are nonisolated by default stays as it was. A default that
		// calls a main-actor initializer does not compile there, with or without this change: the configuration's
		// initializer is nonisolated, as the module's declarations are.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				/// A default value a `nonisolated` initializer can read in every kind of module.
				nonisolated public struct Policy: Sendable {
				    public static let standard = Policy()
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Client: Instantiable, Sendable {
				    public nonisolated init(timeout: Int = 30, policy: Policy = Policy.standard, name: @autoclosure @escaping () -> String = "client") {}
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(client: Client) {
				        self.client = client
				    }

				    /// `Client` is built only outside `Sendable` wrappers, so its configuration takes the plain form.
				    @Instantiated let client: Client
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
			    struct SafeDIOverrides {
			        init(
			            client: Client.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                client: client
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

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_client() -> Client {
			            return if let safeDIBuilder = safeDIOverrides.client.safeDIBuilder { safeDIBuilder(safeDIOverrides.client.timeout, safeDIOverrides.client.policy, safeDIOverrides.client.name()) } else { Client(timeout: safeDIOverrides.client.timeout, policy: safeDIOverrides.client.policy, name: safeDIOverrides.client.name()) }
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
			    struct SafeDIMockConfiguration {
			        init(
			            timeout: Int = 30,
			            policy: Policy = Policy.standard,
			            name: @autoclosure @escaping () -> String = "client",
			            _ safeDIBuilder: ((Int, Policy, String) -> Client)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                timeout: timeout,
			                policy: policy,
			                name: name,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var timeout: Int { __safeDI_storage.timeout }
			        var policy: Policy { __safeDI_storage.policy }
			        var name: () -> String { __safeDI_storage.name }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int, Policy, String) -> Client)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                timeout: Int,
			                policy: Policy,
			                name: @escaping () -> String,
			                safeDIBuilder: ((Int, Policy, String) -> Client)?
			            ) {
			                self.timeout = timeout
			                self.policy = policy
			                self.name = name
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let timeout: Int
			            let policy: Policy
			            let name: () -> String
			            let safeDIBuilder: ((Int, Policy, String) -> Client)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compilesActorMock_whenModuleDefaultsToMainActorAndConfiguredTypeTakesSendableForm() async throws {
		// An actor’s `mock()` is `nonisolated`, so it can read only a configuration that is not isolated to the main actor:
		// the `Sendable` form’s. A plain configuration there stays isolated to the main actor, a deliberate gap (issue 661):
		// a `nonisolated` one could not evaluate a default that reads main-actor state, which SafeDI cannot see.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				/// A default value a `nonisolated` initializer can read in every kind of module.
				nonisolated public struct Policy: Sendable {
				    public static let standard = Policy()
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Client: Instantiable, Sendable {
				    public nonisolated init(timeout: Int = 30, policy: Policy = Policy.standard, name: @autoclosure @escaping () -> String = "client") {}
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public actor Root: Instantiable {
				    public init(client: Client, clientBuilder: SendableInstantiator<Client>) {
				        self.client = client
				        self.clientBuilder = clientBuilder
				    }

				    /// `Client` is built outside a `Sendable` wrapper here and inside one below, so its configuration takes the `Sendable` form.
				    @Instantiated let client: Client
				    @Instantiated let clientBuilder: SendableInstantiator<Client>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: "MainActor"),
		)

		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            client: Client.SafeDIMockConfiguration = .init(),
			            clientBuilder: Client.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                client: client,
			                clientBuilder: clientBuilder
			            )
			        }

			        var client: Client.SafeDIMockConfiguration { __safeDI_storage.client }
			        var clientBuilder: Client.SafeDIMockConfiguration { __safeDI_storage.clientBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                client: Client.SafeDIMockConfiguration,
			                clientBuilder: Client.SafeDIMockConfiguration
			            ) {
			                self.client = client
			                self.clientBuilder = clientBuilder
			            }

			            let client: Client.SafeDIMockConfiguration
			            let clientBuilder: Client.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_client__overrides = safeDIOverrides.client
			        func __safeDI_client() -> Client {
			            return if let safeDIBuilder = __safeDI_client__overrides.safeDIBuilder { safeDIBuilder(__safeDI_client__overrides.timeout(), __safeDI_client__overrides.policy(), __safeDI_client__overrides.name()) } else { Client(timeout: __safeDI_client__overrides.timeout(), policy: __safeDI_client__overrides.policy(), name: __safeDI_client__overrides.name()) }
			        }
			        let client: Client = __safeDI_client()
			        let __safeDI_clientBuilder__overrides = safeDIOverrides.clientBuilder
			        @Sendable nonisolated func __safeDI_clientBuilder() -> Client {
			            if let safeDIBuilder = __safeDI_clientBuilder__overrides.safeDIBuilder { safeDIBuilder(__safeDI_clientBuilder__overrides.timeout(), __safeDI_clientBuilder__overrides.policy(), __safeDI_clientBuilder__overrides.name()) } else { Client(timeout: __safeDI_clientBuilder__overrides.timeout(), policy: __safeDI_clientBuilder__overrides.policy(), name: __safeDI_clientBuilder__overrides.name()) }
			        }
			        let clientBuilder = SendableInstantiator<Client>(__safeDI_clientBuilder)
			        return Root(client: client, clientBuilder: clientBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Client {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            timeout: @autoclosure @escaping @Sendable () -> Int = 30,
			            policy: @autoclosure @escaping @Sendable () -> Policy = Policy.standard,
			            name: @autoclosure @escaping @Sendable () -> String = "client",
			            _ safeDIBuilder: (@Sendable (Int, Policy, String) -> Client)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                timeout: timeout,
			                policy: policy,
			                name: name,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var timeout: @Sendable () -> Int { __safeDI_storage.timeout }
			        var policy: @Sendable () -> Policy { __safeDI_storage.policy }
			        var name: @Sendable () -> String { __safeDI_storage.name }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Int, Policy, String) -> Client)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                timeout: @escaping @Sendable () -> Int,
			                policy: @escaping @Sendable () -> Policy,
			                name: @escaping @Sendable () -> String,
			                safeDIBuilder: (@Sendable (Int, Policy, String) -> Client)?
			            ) {
			                self.timeout = timeout
			                self.policy = policy
			                self.name = name
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let timeout: @Sendable () -> Int
			            let policy: @Sendable () -> Policy
			            let name: @Sendable () -> String
			            let safeDIBuilder: (@Sendable (Int, Policy, String) -> Client)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
