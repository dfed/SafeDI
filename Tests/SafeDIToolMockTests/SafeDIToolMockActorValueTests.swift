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

/// A mock of an actor reads its arguments' overrides apart from `safeDIOverrides`, so that Swift 6 lets it send them
/// to the actor’s initializer (`SafeDIToolMockActorArgumentTests`). These tests compare what such a mock builds with
/// what production builds: the values the actor is handed, `Sendable` or not, with and without an override, through a
/// public mock, and in a cycle through the actor.
struct SafeDIToolMockActorValueTests: ~Copyable {
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsProductionsValues_whenActorReceivesSendableAndNonSendableValues() async throws {
		let (mockFile, path) = try await Self.storeMockAndPath(of: Self.storeFixture(generateMock: "true"), filesToDelete: &filesToDelete)

		#expect(mockFile == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Store {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            worker: Worker.SafeDIMockConfiguration = .init(),
		            config: (@Sendable () -> Config)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                worker: worker,
		                config: config
		            )
		        }

		        var worker: Worker.SafeDIMockConfiguration { __safeDI_storage.worker }
		        var config: (@Sendable () -> Config)? { __safeDI_storage.config }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                worker: Worker.SafeDIMockConfiguration,
		                config: (@Sendable () -> Config)?
		            ) {
		                self.worker = worker
		                self.config = config
		            }

		            let worker: Worker.SafeDIMockConfiguration
		            let config: (@Sendable () -> Config)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Store {
		        let __safeDI_worker__overrides = safeDIOverrides.worker
		        func __safeDI_worker() -> Worker {
		            func __safeDI_tracker() -> Tracker {
		                return if let safeDIBuilder = __safeDI_worker__overrides.tracker.safeDIBuilder { safeDIBuilder(__safeDI_worker__overrides.tracker.name()) } else { Tracker(name: __safeDI_worker__overrides.tracker.name()) }
		            }
		            let tracker: Tracker = __safeDI_tracker()
		            func __safeDI_childBuilder() -> Child {
		                if let safeDIBuilder = __safeDI_worker__overrides.childBuilder.safeDIBuilder { safeDIBuilder(tracker, __safeDI_worker__overrides.childBuilder.name()) } else { Child(tracker: tracker, name: __safeDI_worker__overrides.childBuilder.name()) }
		            }
		            let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
		            return if let safeDIBuilder = __safeDI_worker__overrides.safeDIBuilder { safeDIBuilder(tracker, childBuilder) } else { Worker(tracker: tracker, childBuilder: childBuilder) }
		        }
		        let worker: Worker = __safeDI_worker()
		        let config = if let safeDIBuilder = safeDIOverrides.config { safeDIBuilder() } else { Config() }
		        return Store(config: config, worker: worker)
		    }
		}
		#endif
		""", "Unexpected output \(mockFile ?? "")")
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [
				DifferentialValueProbe(
					name: "Store.mock() against production",
					expression: "Store.mock()",
					knownRightExpression: "Root().store",
				),
			],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsOverriddenValues_whenOverridesReachActorsArgument() async throws {
		// The known-right build hands the actor a `Worker` the probe's closure built, whose region Swift 6 cannot tell from
		// the closure's, so it passes it through a `nonisolated(unsafe)` local; the generated mock needs none.
		let path = try await Self.path(of: Self.storeFixture(generateMock: "true"), filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [
				DifferentialValueProbe(
					name: "Store.mock() with overrides of its argument’s tree",
					expression: "Store.mock(safeDIOverrides: .init(worker: .init(tracker: .init(name: \"overridden\"), childBuilder: .init(name: \"overridden child\"))))",
					knownRightExpression: "{ () -> Store in let tracker = Tracker(name: \"overridden\"); nonisolated(unsafe) let worker = Worker(tracker: tracker, childBuilder: Instantiator<Child> { Child(tracker: tracker, name: \"overridden child\") }); return Store(config: Config(), worker: worker) }()",
				),
			],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsOverriddenValues_whenPublicMocksOverridesReachActorsArgument() async throws {
		let path = try await Self.path(of: Self.storeFixture(generateMock: ".public"), filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [
				DifferentialValueProbe(
					name: "Store.mock() with overrides of its argument’s tree",
					expression: "Store.mock(safeDIOverrides: .init(worker: .init(tracker: .init(name: \"overridden\"), childBuilder: .init(name: \"overridden child\"))))",
					knownRightExpression: "{ () -> Store in let tracker = Tracker(name: \"overridden\"); nonisolated(unsafe) let worker = Worker(tracker: tracker, childBuilder: Instantiator<Child> { Child(tracker: tracker, name: \"overridden child\") }); return Store(config: Config(), worker: worker) }()",
				),
			],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsProductionsValues_whenPublicMockOfActorReceivesSendableAndNonSendableValues() async throws {
		let (mockFile, path) = try await Self.storeMockAndPath(of: Self.storeFixture(generateMock: ".public"), filesToDelete: &filesToDelete)

		#expect(mockFile == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Store {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            worker: __safeDI_Worker_MockConfiguration = .init(),
		            config: (@Sendable () -> Config)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                worker: worker,
		                config: config
		            )
		        }

		        public var worker: __safeDI_Worker_MockConfiguration { __safeDI_storage.worker }
		        public var config: (@Sendable () -> Config)? { __safeDI_storage.config }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                worker: __safeDI_Worker_MockConfiguration,
		                config: (@Sendable () -> Config)?
		            ) {
		                self.worker = worker
		                self.config = config
		            }

		            let worker: __safeDI_Worker_MockConfiguration
		            let config: (@Sendable () -> Config)?
		        }
		    }

		    public static func mock(
		        config: Config? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Store {
		        Store.__safeDI_mock(config: config, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        config: Config? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Store {
		        let __safeDI_worker__worker_tracker_safeDIBuilder = safeDIOverrides.worker.tracker.safeDIBuilder
		        let __safeDI_worker__worker_tracker_name = safeDIOverrides.worker.tracker.name
		        let __safeDI_worker__worker_childBuilder_safeDIBuilder = safeDIOverrides.worker.childBuilder.safeDIBuilder
		        let __safeDI_worker__worker_childBuilder_name = safeDIOverrides.worker.childBuilder.name
		        let __safeDI_worker__safeDIBuilder = safeDIOverrides.worker.safeDIBuilder
		        func __safeDI_worker() -> Worker {
		            func __safeDI_tracker() -> Tracker {
		                return Tracker.__safeDI_init(name: __safeDI_worker__worker_tracker_name(), safeDIBuilder: __safeDI_worker__worker_tracker_safeDIBuilder)
		            }
		            let tracker: Tracker = __safeDI_tracker()
		            func __safeDI_childBuilder() -> Child {
		                Child.__safeDI_init(tracker: tracker, name: __safeDI_worker__worker_childBuilder_name(), safeDIBuilder: __safeDI_worker__worker_childBuilder_safeDIBuilder)
		            }
		            let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
		            return Worker.__safeDI_init(tracker: tracker, childBuilder: childBuilder, safeDIBuilder: __safeDI_worker__safeDIBuilder)
		        }
		        let worker: Worker = __safeDI_worker()
		        let config = if let config { config } else if let safeDIBuilder = safeDIOverrides.config { safeDIBuilder() } else { Config() }
		        return Store(config: config, worker: worker)
		    }
		}

		extension Store {
		    public enum __safeDI_Store_mock_C3F04A1DAADA0447 {}
		}
		#endif
		""", "Unexpected output \(mockFile ?? "")")
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [
				DifferentialValueProbe(
					name: "Store.mock() against production",
					expression: "Store.mock()",
					knownRightExpression: "Root().store",
				),
			],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsProductionsValues_whenActorIsInCycleThroughItsArgument() async throws {
		let fixtureFiles = [
			"Root.swift": """
			import SafeDI

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(store: Store) {
			        self.store = store
			    }

			    @Instantiated let store: Store
			}
			""",
			"Store.swift": """
			import SafeDI

			@Instantiable(generateMock: true)
			public actor Store: Instantiable {
			    public init(worker: Worker) {
			        self.worker = worker
			    }

			    @Instantiated let worker: Worker
			}
			""",
			"Worker.swift": """
			import SafeDI

			@Instantiable
			public final class Worker: Instantiable {
			    public init(storeBuilder: Instantiator<Store>) {
			        self.storeBuilder = storeBuilder
			    }

			    @Instantiated let storeBuilder: Instantiator<Store>
			}
			""",
		]
		let path = try await Self.path(of: fixtureFiles, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [
				DifferentialValueProbe(
					name: "Store.mock() against production",
					expression: "Store.mock()",
					knownRightExpression: "Root().store",
				),
			],
			filesToDelete: &filesToDelete,
		)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Store`, an actor `Root` builds, receives `Config`, which is `Sendable`, and builds `Worker`, which is not and
	/// builds `Tracker`, which is not either, and `Child` through an instantiator, which receives `Tracker`. A value that
	/// is not `Sendable` reaches the actor only from inside its argument's tree: production cannot send one received
	/// from above the actor to its initializer either.
	private static func storeFixture(generateMock: String) -> [String: String] {
		[
			"Root.swift": """
			import SafeDI

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(config: Config, store: Store) {
			        self.config = config
			        self.store = store
			    }

			    @Instantiated let config: Config
			    @Instantiated let store: Store
			}
			""",
			"Store.swift": """
			import SafeDI

			@Instantiable(generateMock: \(generateMock))
			public actor Store: Instantiable {
			    public init(config: Config, worker: Worker) {
			        self.config = config
			        self.worker = worker
			    }

			    @Received let config: Config
			    @Instantiated let worker: Worker
			}
			""",
			"Worker.swift": """
			import SafeDI

			@Instantiable
			public final class Worker: Instantiable {
			    public init(tracker: Tracker, childBuilder: Instantiator<Child>) {
			        self.tracker = tracker
			        self.childBuilder = childBuilder
			    }

			    @Instantiated let tracker: Tracker
			    @Instantiated let childBuilder: Instantiator<Child>
			}
			""",
			"Values.swift": """
			import SafeDI

			@Instantiable
			public final class Config: Instantiable, Sendable {
			    public init() {}
			}

			@Instantiable
			public final class Tracker: Instantiable {
			    public init(name: String = "tracker") {
			        self.name = name
			    }

			    let name: String
			}

			@Instantiable
			public final class Child: Instantiable {
			    public init(tracker: Tracker, name: String = "child") {
			        self.tracker = tracker
			        self.name = name
			    }

			    @Received let tracker: Tracker
			    let name: String
			}
			""",
		]
	}

	/// The `Store+SafeDIMock.swift` the tool generates for `fixtureFiles`, and the path that compiles them.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func storeMockAndPath(of fixtureFiles: [String: String], filesToDelete: inout [URL]) async throws -> (mockFile: String?, path: DifferentialValuePath) {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: fixtureFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		return try (output.mockFiles["Store+SafeDIMock.swift"], DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles)))
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func path(of fixtureFiles: [String: String], filesToDelete: inout [URL]) async throws -> DifferentialValuePath {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: fixtureFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		return try DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles))
	}
}
