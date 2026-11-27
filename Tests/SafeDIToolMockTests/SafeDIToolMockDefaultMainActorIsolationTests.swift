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
/// `defaultIsolation(MainActor.self)` and a new Xcode 26 app target set) infers a local function declared inside a
/// main-actor initializer or `mock()` to be on the main actor too, and Swift rejects a main-actor synchronous local
/// function marked `@Sendable`. The mock spells the function that backs a `Sendable` wrapper
/// `@Sendable nonisolated`, which is what Swift infers for it in every other module, so it compiles there too.
struct SafeDIToolMockDefaultMainActorIsolationTests: ~Copyable {
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
	mutating func mock_sendableInstantiatorBuilderCompiles_whenModuleDefaultsToMainActor() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(screenBuilder: SendableInstantiator<Screen>) {
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated let screenBuilder: SendableInstantiator<Screen>
				}
				""",
				"""
				@Instantiable
				public final class Screen: Instantiable {
				    public init() {}
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
			            screenBuilder: (@Sendable () -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                screenBuilder: screenBuilder
			            )
			        }

			        var screenBuilder: (@Sendable () -> Screen)? { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                screenBuilder: (@Sendable () -> Screen)?
			            ) {
			                self.screenBuilder = screenBuilder
			            }

			            let screenBuilder: (@Sendable () -> Screen)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_screenBuilder__safeDIBuilder = safeDIOverrides.screenBuilder
			        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
			            if let safeDIBuilder = __safeDI_screenBuilder__safeDIBuilder { safeDIBuilder() } else { Screen() }
			        }
			        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
			        return Root(screenBuilder: screenBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_sendableWrapperBuildersCompile_whenModuleDefaultsToMainActorAndRootSpellsMainActorGeneratedAttributes() async throws {
		// The Manual's remedy for a type that conforms only to `Instantiable` in such a module, `@MainActor` on its
		// generated declarations, beside `Sendable` wrappers of each kind: a forwarding one, a lazy one, and a cycle of two.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				/// No `@Instantiable` declaration fulfills this, so a mock can't build it.
				public protocol Logging: Sendable {
				    var name: String { get }
				}
				""",
				"""
				@Instantiable
				public final class Client: Instantiable, Sendable {
				    public nonisolated init(timeout: Int = 30) {
				        self.timeout = timeout
				    }

				    public let timeout: Int
				}
				""",
				"""
				@Instantiable
				public final class Cache: Instantiable, Sendable {
				    public nonisolated init(limit: Int = 10) {
				        self.limit = limit
				    }

				    public let limit: Int
				}
				""",
				"""
				@Instantiable
				public final class Worker: Instantiable, Sendable {
				    public nonisolated init(jobID: String, retries: Int = 3, logger: any Logging, client: Client) {
				        self.jobID = jobID
				        self.retries = retries
				        self.logger = logger
				        self.client = client
				    }

				    @Forwarded public let jobID: String
				    public let retries: Int
				    @Instantiated(fulfilledByType: "ConsoleLogger") public let logger: any Logging
				    @Instantiated public let client: Client
				}
				""",
				"""
				/// `Ping` and `Pong` open each other through `SendableInstantiator`s: a cycle whose every lap is built in a `@Sendable`
				/// function.
				@Instantiable
				public final class Ping: Instantiable, Sendable {
				    public nonisolated init(label: String = "ping", pongBuilder: SendableInstantiator<Pong>) {
				        self.label = label
				        self.pongBuilder = pongBuilder
				    }

				    public let label: String
				    @Instantiated public let pongBuilder: SendableInstantiator<Pong>
				}
				""",
				"""
				@Instantiable
				public final class Pong: Instantiable, Sendable {
				    public nonisolated init(label: String = "pong", pingBuilder: SendableInstantiator<Ping>) {
				        self.label = label
				        self.pingBuilder = pingBuilder
				    }

				    public let label: String
				    @Instantiated public let pingBuilder: SendableInstantiator<Ping>
				}
				""",
				"""
				@Instantiable(generatedAttributes: "@MainActor", generateMock: true)
				public final class Root: Instantiable {
				    public init(client: Client, workerBuilder: SendableInstantiator<Worker>, cache: SendableLazilyInstantiated<Cache>, pingBuilder: SendableInstantiator<Ping>) {
				        self.client = client
				        self.workerBuilder = workerBuilder
				        self.cache = cache
				        self.pingBuilder = pingBuilder
				    }

				    /// The same type as `Worker.client`, built outside the wrapper.
				    @Instantiated public let client: Client
				    @Instantiated public let workerBuilder: SendableInstantiator<Worker>
				    @Instantiated public let cache: SendableLazilyInstantiated<Cache>
				    @Instantiated public let pingBuilder: SendableInstantiator<Ping>
				}
				""",
				"""
				@Instantiable
				public final class ConsoleLogger: Logging, Instantiable {
				    public nonisolated init() {}
				    public var name: String { "console" }
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
			            workerBuilder: Worker.SafeDIMockConfiguration = .init(),
			            cache: Cache.SafeDIMockConfiguration = .init(),
			            pingBuilder: Ping.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                client: client,
			                workerBuilder: workerBuilder,
			                cache: cache,
			                pingBuilder: pingBuilder
			            )
			        }

			        var client: Client.SafeDIMockConfiguration { __safeDI_storage.client }
			        var workerBuilder: Worker.SafeDIMockConfiguration { __safeDI_storage.workerBuilder }
			        var cache: Cache.SafeDIMockConfiguration { __safeDI_storage.cache }
			        var pingBuilder: Ping.SafeDIMockConfiguration { __safeDI_storage.pingBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                client: Client.SafeDIMockConfiguration,
			                workerBuilder: Worker.SafeDIMockConfiguration,
			                cache: Cache.SafeDIMockConfiguration,
			                pingBuilder: Ping.SafeDIMockConfiguration
			            ) {
			                self.client = client
			                self.workerBuilder = workerBuilder
			                self.cache = cache
			                self.pingBuilder = pingBuilder
			            }

			            let client: Client.SafeDIMockConfiguration
			            let workerBuilder: Worker.SafeDIMockConfiguration
			            let cache: Cache.SafeDIMockConfiguration
			            let pingBuilder: Ping.SafeDIMockConfiguration
			        }
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_client() -> Client {
			            return if let safeDIBuilder = safeDIOverrides.client.safeDIBuilder { safeDIBuilder(safeDIOverrides.client.timeout()) } else { Client(timeout: safeDIOverrides.client.timeout()) }
			        }
			        let client: Client = __safeDI_client()
			        let __safeDI_workerBuilder__overrides = safeDIOverrides.workerBuilder
			        @Sendable nonisolated func __safeDI_workerBuilder(jobID: String) -> Worker {
			            let logger: any Logging = if let safeDIBuilder = __safeDI_workerBuilder__overrides.logger { safeDIBuilder() } else { ConsoleLogger() }
			            func __safeDI_client() -> Client {
			                return if let safeDIBuilder = __safeDI_workerBuilder__overrides.client.safeDIBuilder { safeDIBuilder(__safeDI_workerBuilder__overrides.client.timeout()) } else { Client(timeout: __safeDI_workerBuilder__overrides.client.timeout()) }
			            }
			            let client: Client = __safeDI_client()
			            return if let safeDIBuilder = __safeDI_workerBuilder__overrides.safeDIBuilder { safeDIBuilder(jobID, __safeDI_workerBuilder__overrides.retries(), logger, client) } else { Worker(jobID: jobID, retries: __safeDI_workerBuilder__overrides.retries(), logger: logger, client: client) }
			        }
			        let workerBuilder = SendableInstantiator<Worker> {
			            __safeDI_workerBuilder(jobID: $0)
			        }
			        let __safeDI_cache__overrides = safeDIOverrides.cache
			        @Sendable nonisolated func __safeDI_cache() -> Cache {
			            if let safeDIBuilder = __safeDI_cache__overrides.safeDIBuilder { safeDIBuilder(__safeDI_cache__overrides.limit()) } else { Cache(limit: __safeDI_cache__overrides.limit()) }
			        }
			        let cache = SendableLazilyInstantiated<Cache>(__safeDI_cache)
			        let __safeDI_pingBuilder__overrides = safeDIOverrides.pingBuilder
			        @Sendable nonisolated func __safeDI_pingBuilder() -> Ping {
			            @Sendable nonisolated func __safeDI_pongBuilder() -> Pong {
			                let pingBuilder = SendableInstantiator<Ping>(__safeDI_pingBuilder)
			                return if let safeDIBuilder = __safeDI_pingBuilder__overrides.pongBuilder.safeDIBuilder { safeDIBuilder(__safeDI_pingBuilder__overrides.pongBuilder.label(), pingBuilder) } else { Pong(label: __safeDI_pingBuilder__overrides.pongBuilder.label(), pingBuilder: pingBuilder) }
			            }
			            let pongBuilder = SendableInstantiator<Pong>(__safeDI_pongBuilder)
			            return if let safeDIBuilder = __safeDI_pingBuilder__overrides.safeDIBuilder { safeDIBuilder(__safeDI_pingBuilder__overrides.label(), pongBuilder) } else { Ping(label: __safeDI_pingBuilder__overrides.label(), pongBuilder: pongBuilder) }
			        }
			        let pingBuilder = SendableInstantiator<Ping>(__safeDI_pingBuilder)
			        return Root(client: client, workerBuilder: workerBuilder, cache: cache, pingBuilder: pingBuilder)
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
			            _ safeDIBuilder: (@Sendable (Int) -> Client)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                timeout: timeout,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var timeout: @Sendable () -> Int { __safeDI_storage.timeout }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Int) -> Client)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                timeout: @escaping @Sendable () -> Int,
			                safeDIBuilder: (@Sendable (Int) -> Client)?
			            ) {
			                self.timeout = timeout
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let timeout: @Sendable () -> Int
			            let safeDIBuilder: (@Sendable (Int) -> Client)?
			        }
			    }
			}

			extension Worker {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            logger: (@Sendable () -> any Logging)? = nil,
			            client: Client.SafeDIMockConfiguration = .init(),
			            retries: @autoclosure @escaping @Sendable () -> Int = 3,
			            _ safeDIBuilder: (@Sendable (String, Int, any Logging, Client) -> Worker)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                logger: logger,
			                client: client,
			                retries: retries,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var logger: (@Sendable () -> any Logging)? { __safeDI_storage.logger }
			        var client: Client.SafeDIMockConfiguration { __safeDI_storage.client }
			        var retries: @Sendable () -> Int { __safeDI_storage.retries }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (String, Int, any Logging, Client) -> Worker)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                logger: (@Sendable () -> any Logging)?,
			                client: Client.SafeDIMockConfiguration,
			                retries: @escaping @Sendable () -> Int,
			                safeDIBuilder: (@Sendable (String, Int, any Logging, Client) -> Worker)?
			            ) {
			                self.logger = logger
			                self.client = client
			                self.retries = retries
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let logger: (@Sendable () -> any Logging)?
			            let client: Client.SafeDIMockConfiguration
			            let retries: @Sendable () -> Int
			            let safeDIBuilder: (@Sendable (String, Int, any Logging, Client) -> Worker)?
			        }
			    }
			}

			extension Cache {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            limit: @autoclosure @escaping @Sendable () -> Int = 10,
			            _ safeDIBuilder: (@Sendable (Int) -> Cache)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                limit: limit,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var limit: @Sendable () -> Int { __safeDI_storage.limit }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Int) -> Cache)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                limit: @escaping @Sendable () -> Int,
			                safeDIBuilder: (@Sendable (Int) -> Cache)?
			            ) {
			                self.limit = limit
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let limit: @Sendable () -> Int
			            let safeDIBuilder: (@Sendable (Int) -> Cache)?
			        }
			    }
			}

			extension Pong {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            label: @autoclosure @escaping @Sendable () -> String = "pong",
			            _ safeDIBuilder: (@Sendable (String, SendableInstantiator<Ping>) -> Pong)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                label: label,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var label: @Sendable () -> String { __safeDI_storage.label }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (String, SendableInstantiator<Ping>) -> Pong)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                label: @escaping @Sendable () -> String,
			                safeDIBuilder: (@Sendable (String, SendableInstantiator<Ping>) -> Pong)?
			            ) {
			                self.label = label
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let label: @Sendable () -> String
			            let safeDIBuilder: (@Sendable (String, SendableInstantiator<Ping>) -> Pong)?
			        }
			    }
			}

			extension Ping {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            pongBuilder: Pong.SafeDIMockConfiguration = .init(),
			            label: @autoclosure @escaping @Sendable () -> String = "ping",
			            _ safeDIBuilder: (@Sendable (String, SendableInstantiator<Pong>) -> Ping)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                pongBuilder: pongBuilder,
			                label: label,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var pongBuilder: Pong.SafeDIMockConfiguration { __safeDI_storage.pongBuilder }
			        var label: @Sendable () -> String { __safeDI_storage.label }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (String, SendableInstantiator<Pong>) -> Ping)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                pongBuilder: Pong.SafeDIMockConfiguration,
			                label: @escaping @Sendable () -> String,
			                safeDIBuilder: (@Sendable (String, SendableInstantiator<Pong>) -> Ping)?
			            ) {
			                self.pongBuilder = pongBuilder
			                self.label = label
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let pongBuilder: Pong.SafeDIMockConfiguration
			            let label: @Sendable () -> String
			            let safeDIBuilder: (@Sendable (String, SendableInstantiator<Pong>) -> Ping)?
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
