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
/// function marked `@Sendable`. The production tree spells the function that backs a `Sendable` wrapper
/// `@Sendable nonisolated`, which is what Swift infers for it in every other module, so it compiles there too.
struct SafeDIToolDefaultMainActorIsolationTests: ~Copyable {
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
	mutating func generate_sendableInstantiatorBuilderCompiles_whenModuleDefaultsToMainActor() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				@Instantiable(isRoot: true)
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
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
			            Screen()
			        }
			        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
			        self.init(screenBuilder: screenBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_sendableWrapperBuildersCompile_whenModuleDefaultsToMainActorAndRootSpellsMainActorGeneratedAttributes() async throws {
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
				@Instantiable(isRoot: true, generatedAttributes: "@MainActor")
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
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    @MainActor public convenience init() {
			        let client = Client()
			        @Sendable nonisolated func __safeDI_workerBuilder(jobID: String) -> Worker {
			            let logger: any Logging = ConsoleLogger()
			            let client = Client()
			            return Worker(jobID: jobID, logger: logger, client: client)
			        }
			        let workerBuilder = SendableInstantiator<Worker> {
			            __safeDI_workerBuilder(jobID: $0)
			        }
			        @Sendable nonisolated func __safeDI_cache() -> Cache {
			            Cache()
			        }
			        let cache = SendableLazilyInstantiated<Cache>(__safeDI_cache)
			        @Sendable nonisolated func __safeDI_pingBuilder() -> Ping {
			            let pongBuilder = SendableInstantiator<Pong>(__safeDI_pongBuilder)
			            return Ping(pongBuilder: pongBuilder)
			        }
			        @Sendable nonisolated func __safeDI_pongBuilder() -> Pong {
			            let pingBuilder = SendableInstantiator<Ping>(__safeDI_pingBuilder)
			            return Pong(pingBuilder: pingBuilder)
			        }
			        let pingBuilder = SendableInstantiator<Ping>(__safeDI_pingBuilder)
			        self.init(client: client, workerBuilder: workerBuilder, cache: cache, pingBuilder: pingBuilder)
			    }
			}
			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
