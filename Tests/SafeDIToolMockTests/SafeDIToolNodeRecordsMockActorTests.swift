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

/// An internal mock root whose world holds an actor, laid out from the node records of its world
/// (`NodeRecords+MockConstruction.swift`). An actor is a node as any other: its override takes each argument `sending`,
/// and what it is sent is built by functions that are each handed their configuration, so none captures `mock()`'s
/// overrides, which the walk keeps its functions from doing by reading them into a local before each.
struct SafeDIToolNodeRecordsMockActorTests: ~Copyable {
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
	mutating func mock_handsEachFunctionItsConfiguration_whenRootBuildsActorWithConfiguredAndLeafArguments() async throws {
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true, true])
		// The actor's function and its argument's are each declared once, for the constant and the `Instantiator` alike, and
		// no function reads `mock()`'s own overrides: `safeDIOverrides` inside one is its own argument.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            counter: (() -> Counter)? = nil,
		            store: Store.SafeDIMockConfiguration = .init(),
		            storeBuilder: Store.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                counter: counter,
		                store: store,
		                storeBuilder: storeBuilder
		            )
		        }

		        var counter: (() -> Counter)? { __safeDI_storage.counter }
		        var store: Store.SafeDIMockConfiguration { __safeDI_storage.store }
		        var storeBuilder: Store.SafeDIMockConfiguration { __safeDI_storage.storeBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                counter: (() -> Counter)?,
		                store: Store.SafeDIMockConfiguration,
		                storeBuilder: Store.SafeDIMockConfiguration
		            ) {
		                self.counter = counter
		                self.store = store
		                self.storeBuilder = storeBuilder
		            }

		            let counter: (() -> Counter)?
		            let store: Store.SafeDIMockConfiguration
		            let storeBuilder: Store.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let counter = if let safeDIBuilder = safeDIOverrides.counter { safeDIBuilder() } else { Counter() }
		        func __safeDI_store(safeDIOverrides: Store.SafeDIMockConfiguration) -> Store {
		            let worker: Worker = __safeDI_worker(safeDIOverrides: safeDIOverrides.worker)
		            let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(worker, leaf, counter) } else { Store(worker: worker, leaf: leaf, counter: counter) }
		        }
		        func __safeDI_worker(safeDIOverrides: Worker.SafeDIMockConfiguration) -> Worker {
		            let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(leaf) } else { Worker(leaf: leaf) }
		        }
		        let store: Store = __safeDI_store(safeDIOverrides: safeDIOverrides.store)
		        let storeBuilder = Instantiator<Store> {
		            __safeDI_store(safeDIOverrides: safeDIOverrides.storeBuilder)
		        }
		        return Root(store: store, counter: counter, storeBuilder: storeBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsArgumentsFunctionItsConfiguration_whenMockedTypeIsActor() async throws {
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true, true])
		#expect(output.mockFiles["Store+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Store {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            worker: Worker.SafeDIMockConfiguration = .init(),
		            leaf: (@Sendable () -> Leaf)? = nil,
		            counter: (@Sendable () -> Counter)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                worker: worker,
		                leaf: leaf,
		                counter: counter
		            )
		        }

		        var worker: Worker.SafeDIMockConfiguration { __safeDI_storage.worker }
		        var leaf: (@Sendable () -> Leaf)? { __safeDI_storage.leaf }
		        var counter: (@Sendable () -> Counter)? { __safeDI_storage.counter }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                worker: Worker.SafeDIMockConfiguration,
		                leaf: (@Sendable () -> Leaf)?,
		                counter: (@Sendable () -> Counter)?
		            ) {
		                self.worker = worker
		                self.leaf = leaf
		                self.counter = counter
		            }

		            let worker: Worker.SafeDIMockConfiguration
		            let leaf: (@Sendable () -> Leaf)?
		            let counter: (@Sendable () -> Counter)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Store {
		        func __safeDI_worker(safeDIOverrides: Worker.SafeDIMockConfiguration) -> Worker {
		            let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(leaf) } else { Worker(leaf: leaf) }
		        }
		        let worker: Worker = __safeDI_worker(safeDIOverrides: safeDIOverrides.worker)
		        let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		        let counter = if let safeDIBuilder = safeDIOverrides.counter { safeDIBuilder() } else { Counter() }
		        return Store(worker: worker, leaf: leaf, counter: counter)
		    }
		}
		#endif

		#if DEBUG
		extension Store {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            worker: Worker.SafeDIMockConfiguration = .init(),
		            leaf: (@Sendable () -> Leaf)? = nil,
		            _ safeDIBuilder: ((sending Worker, sending Leaf, sending Counter) -> Store)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                worker: worker,
		                leaf: leaf,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var worker: Worker.SafeDIMockConfiguration { __safeDI_storage.worker }
		        var leaf: (@Sendable () -> Leaf)? { __safeDI_storage.leaf }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((sending Worker, sending Leaf, sending Counter) -> Store)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                worker: Worker.SafeDIMockConfiguration,
		                leaf: (@Sendable () -> Leaf)?,
		                safeDIBuilder: ((sending Worker, sending Leaf, sending Counter) -> Store)?
		            ) {
		                self.worker = worker
		                self.leaf = leaf
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let worker: Worker.SafeDIMockConfiguration
		            let leaf: (@Sendable () -> Leaf)?
		            let safeDIBuilder: ((sending Worker, sending Leaf, sending Counter) -> Store)?
		        }
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Store+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenEveryPlaceOfActorsTreeIsOverridden() async throws {
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, _) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		// The two write other text, so the comparison is of two programs.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] != walkOutput.mockFiles["Root+SafeDIMock.swift"])
		// An actor has no member an override can set from outside it, so the override of the received actor builds it with a
		// marker, and the override of the actor that receives it hands it another one, marked for the place.
		func store(_ place: String) -> String {
			"""
			.init(\
			worker: .init(leaf: { marked(Leaf(), "\(place).worker.leaf") }, { marked(Worker(leaf: $0), "\(place).worker") }), \
			leaf: { marked(Leaf(), "\(place).leaf") }, \
			{ worker, leaf, _ in Store(worker: worker, leaf: leaf, counter: Counter(marker: "\(place)’s own counter")) })
			"""
		}
		let overridden = "Root.mock(safeDIOverrides: .init(counter: { Counter(marker: \"counter\") }, store: \(store("store")), storeBuilder: \(store("storeBuilder"))))"
		let actorOverridden = "Store.mock(safeDIOverrides: .init(worker: .init(leaf: { marked(Leaf(), \"worker.leaf\") }, { marked(Worker(leaf: $0), \"worker\") }), leaf: { marked(Leaf(), \"leaf\") }, counter: { Counter(marker: \"counter\") }))"
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: Self.fixture, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: Self.fixture, generatedFiles: #require(walkOutput.generatedFiles)),
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe("Root.mock().storeBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden root", expression: overridden),
				DifferentialValueProbe(name: "overridden instantiator", expression: "\(overridden).storeBuilder.instantiate()"),
				DifferentialValueProbe("Store.mock()"),
				DifferentialValueProbe(name: "overridden actor root", expression: actorOverridden),
			],
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// Every override was read: each marks a value its closure built.
		for marker in ["counter", "store.leaf", "store.worker.leaf", "store.worker", "store’s own counter", "storeBuilder.leaf", "storeBuilder.worker.leaf", "storeBuilder.worker", "storeBuilder’s own counter", "leaf", "worker.leaf", "worker"] {
			#expect(comparison.featureDescription.contains("\"\(marker)\""), "No value is marked \(marker):\n\(comparison.featureDescription)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsTheWalksStatements_whenActorIsOnLazyCycle() async throws {
		// The acceptance case of the kind that lays out a cycle's closer: an actor whose argument builds the actor again
		// through an `Instantiator`. Until that kind is made the world is refused for the cycle, and the walk writes it.
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public actor Store: Instantiable {
			    public init(worker: Worker) {
			        self.worker = worker
			    }

			    @Instantiated let worker: Worker
			}
			""",
			"""
			@Instantiable
			public final class Worker: Instantiable {
			    public init(storeBuilder: Instantiator<Store>) {
			        self.storeBuilder = storeBuilder
			    }

			    @Instantiated let storeBuilder: Instantiator<Store>
			}
			""",
		]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [["cycle"]])
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [false])
		#expect(output.generatedFiles == walkOutput.generatedFiles)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A root that builds an actor in place and through an `Instantiator`, and the actor's own mock. The actor takes a
	/// configured argument, a leaf argument and another actor it receives. Each class carries a marker an override's
	/// closure sets, and the received actor one its second initializer takes.
	private static let fixture: [String: String] = [
		"Marked.swift": """
		public protocol Marked: AnyObject {
		    var marker: String { get set }
		}

		public func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
		    value.marker = marker
		    return value
		}
		""",
		"Root.swift": """
		@Instantiable(generateMock: true)
		public final class Root: Instantiable {
		    public init(store: Store, counter: Counter, storeBuilder: Instantiator<Store>) {
		        self.store = store
		        self.counter = counter
		        self.storeBuilder = storeBuilder
		    }

		    @Instantiated let store: Store
		    @Instantiated let counter: Counter
		    @Instantiated let storeBuilder: Instantiator<Store>
		}
		""",
		"Counter.swift": """
		@Instantiable
		public actor Counter: Instantiable {
		    public init() {
		        marker = "built"
		    }

		    public init(marker: String) {
		        self.marker = marker
		    }

		    public nonisolated let marker: String
		}
		""",
		"Store.swift": """
		@Instantiable(generateMock: true)
		public actor Store: Instantiable {
		    public init(worker: Worker, leaf: Leaf, counter: Counter) {
		        self.worker = worker
		        self.leaf = leaf
		        self.counter = counter
		    }

		    @Instantiated let worker: Worker
		    @Instantiated let leaf: Leaf
		    @Received let counter: Counter
		}
		""",
		"Worker.swift": """
		@Instantiable
		public final class Worker: Instantiable, Marked {
		    public init(leaf: Leaf) {
		        self.leaf = leaf
		    }

		    @Instantiated let leaf: Leaf
		    public var marker = "built"
		}
		""",
		"Leaf.swift": """
		@Instantiable
		public final class Leaf: Instantiable, Marked {
		    public init() {}

		    public var marker = "built"
		}
		""",
	]

	/// What `body` returns with every internal mock root node records accept laid out from them, and the report of each
	/// mock root of the run, in the order of the roots' names.
	private static func layingOutMockRoots<Output>(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> Output,
	) async throws -> (Output, [NodeRecordsReport]) {
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		let output = try await NodeRecordsObservation.$laysOutMockRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
				try await body(&filesMade)
			}
		}
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream {
			reports.append(report)
		}
		return (output, reports.sorted { $0.root < $1.root })
	}
}
