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
/// A wrapper the actor builds is sent with its closure, so the override of each is read into a local before it, which
/// the closure captures and hands the wrapper's function.
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
		// An actor whose argument builds the actor again through an `Instantiator`. A function on the cycle is handed the
		// places entered, which are not `Sendable`, so the worker it builds cannot be sent to the actor, and the walk
		// writes the world.
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

		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [["mockActor"]])
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [false])
		#expect(output.generatedFiles == walkOutput.generatedFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsOverrideIntoLocalBeforeWrapper_whenActorAndClassBuildSameInstantiatorOfLeaf() async throws {
		// The actor is sent the `Instantiator` it builds, so the instantiator's closure captures a local the override is read
		// into, which is `Sendable`, and not the actor's configuration, which is not. The class's instantiator is the same
		// node of the world, so its closure reads a local too.
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.sharedWrapperFixture(buildsClassFirst: false, leafIsSendable: false), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter { $0.isMockRoot && $0.root == "Root" }.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            a: A.SafeDIMockConfiguration = .init(),
		            b: B.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                a: a,
		                b: b
		            )
		        }

		        var a: A.SafeDIMockConfiguration { __safeDI_storage.a }
		        var b: B.SafeDIMockConfiguration { __safeDI_storage.b }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                a: A.SafeDIMockConfiguration,
		                b: B.SafeDIMockConfiguration
		            ) {
		                self.a = a
		                self.b = b
		            }

		            let a: A.SafeDIMockConfiguration
		            let b: B.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_leafBuilder(safeDIOverrides: (() -> Leaf)?) -> Leaf {
		            if let safeDIBuilder = safeDIOverrides { safeDIBuilder() } else { Leaf() }
		        }
		        func __safeDI_a(safeDIOverrides: A.SafeDIMockConfiguration) -> A {
		            let __safeDI_leafBuilder__safeDIBuilder = safeDIOverrides.leafBuilder
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(safeDIOverrides: __safeDI_leafBuilder__safeDIBuilder)
		            }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(leafBuilder) } else { A(leafBuilder: leafBuilder) }
		        }
		        let a: A = __safeDI_a(safeDIOverrides: safeDIOverrides.a)
		        func __safeDI_b(safeDIOverrides: B.SafeDIMockConfiguration) -> B {
		            let __safeDI_leafBuilder__safeDIBuilder = safeDIOverrides.leafBuilder
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(safeDIOverrides: __safeDI_leafBuilder__safeDIBuilder)
		            }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(leafBuilder) } else { B(leafBuilder: leafBuilder) }
		        }
		        let b: B = __safeDI_b(safeDIOverrides: safeDIOverrides.b)
		        return Root(a: a, b: b)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsEachOverrideIntoLocalBeforeItsWrapper_whenActorBuildsEveryKindOfWrapper() async throws {
		// An actor built with its hand-written mock is sent nothing the mock builds, so its instantiator's closure reads the
		// configuration its function was handed, as the walk's does.
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.wrapperFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter { $0.isMockRoot && $0.root == "Root" }.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            store: Store.SafeDIMockConfiguration = .init(),
		            mockedStore: MockedStore.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                store: store,
		                mockedStore: mockedStore
		            )
		        }

		        var store: Store.SafeDIMockConfiguration { __safeDI_storage.store }
		        var mockedStore: MockedStore.SafeDIMockConfiguration { __safeDI_storage.mockedStore }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                store: Store.SafeDIMockConfiguration,
		                mockedStore: MockedStore.SafeDIMockConfiguration
		            ) {
		                self.store = store
		                self.mockedStore = mockedStore
		            }

		            let store: Store.SafeDIMockConfiguration
		            let mockedStore: MockedStore.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_workerBuilder(safeDIOverrides: Worker.SafeDIMockConfiguration) -> Worker {
		            let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(leaf) } else { Worker(leaf: leaf) }
		        }
		        func __safeDI_lazyLeaf(safeDIOverrides: (() -> Leaf)?) -> Leaf {
		            if let safeDIBuilder = safeDIOverrides { safeDIBuilder() } else { Leaf() }
		        }
		        func __safeDI_serviceBuilder(safeDIOverrides: (() -> AnyService)?) -> AnyService {
		            if let safeDIBuilder = safeDIOverrides { safeDIBuilder() } else { AnyService(DefaultService()) }
		        }
		        func __safeDI_store(safeDIOverrides: Store.SafeDIMockConfiguration) -> Store {
		            let __safeDI_workerBuilder__overrides = safeDIOverrides.workerBuilder
		            let workerBuilder = Instantiator<Worker> {
		                __safeDI_workerBuilder(safeDIOverrides: __safeDI_workerBuilder__overrides)
		            }
		            let __safeDI_lazyLeaf__safeDIBuilder = safeDIOverrides.lazyLeaf
		            let lazyLeaf = LazilyInstantiated<Leaf> {
		                __safeDI_lazyLeaf(safeDIOverrides: __safeDI_lazyLeaf__safeDIBuilder)
		            }
		            let __safeDI_serviceBuilder__safeDIBuilder = safeDIOverrides.serviceBuilder
		            let serviceBuilder = ErasedInstantiator<(), AnyService> {
		                __safeDI_serviceBuilder(safeDIOverrides: __safeDI_serviceBuilder__safeDIBuilder)
		            }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(workerBuilder, lazyLeaf, serviceBuilder) } else { Store(workerBuilder: workerBuilder, lazyLeaf: lazyLeaf, serviceBuilder: serviceBuilder) }
		        }
		        let store: Store = __safeDI_store(safeDIOverrides: safeDIOverrides.store)
		        func __safeDI_mockedStore(safeDIOverrides: MockedStore.SafeDIMockConfiguration) -> MockedStore {
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_lazyLeaf(safeDIOverrides: safeDIOverrides.leafBuilder)
		            }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(leafBuilder) } else { MockedStore.mock(leafBuilder: leafBuilder) }
		        }
		        let mockedStore: MockedStore = __safeDI_mockedStore(safeDIOverrides: safeDIOverrides.mockedStore)
		        return Root(store: store, mockedStore: mockedStore)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsEachWrappersFunctionItsLocal_whenMockedTypeIsActor() async throws {
		// `mock()`'s own body binds each local, and hands it to the wrapper's function, which the body declares.
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.wrapperFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter { $0.isMockRoot && $0.root == "Store" }.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(output.mockFiles["Store+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Store {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            workerBuilder: Worker.SafeDIMockConfiguration = .init(),
		            lazyLeaf: (@Sendable () -> Leaf)? = nil,
		            serviceBuilder: (@Sendable () -> AnyService)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                workerBuilder: workerBuilder,
		                lazyLeaf: lazyLeaf,
		                serviceBuilder: serviceBuilder
		            )
		        }

		        var workerBuilder: Worker.SafeDIMockConfiguration { __safeDI_storage.workerBuilder }
		        var lazyLeaf: (@Sendable () -> Leaf)? { __safeDI_storage.lazyLeaf }
		        var serviceBuilder: (@Sendable () -> AnyService)? { __safeDI_storage.serviceBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                workerBuilder: Worker.SafeDIMockConfiguration,
		                lazyLeaf: (@Sendable () -> Leaf)?,
		                serviceBuilder: (@Sendable () -> AnyService)?
		            ) {
		                self.workerBuilder = workerBuilder
		                self.lazyLeaf = lazyLeaf
		                self.serviceBuilder = serviceBuilder
		            }

		            let workerBuilder: Worker.SafeDIMockConfiguration
		            let lazyLeaf: (@Sendable () -> Leaf)?
		            let serviceBuilder: (@Sendable () -> AnyService)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Store {
		        let __safeDI_workerBuilder__overrides = safeDIOverrides.workerBuilder
		        func __safeDI_workerBuilder(safeDIOverrides: Worker.SafeDIMockConfiguration) -> Worker {
		            let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(leaf) } else { Worker(leaf: leaf) }
		        }
		        let workerBuilder = Instantiator<Worker> {
		            __safeDI_workerBuilder(safeDIOverrides: __safeDI_workerBuilder__overrides)
		        }
		        let __safeDI_lazyLeaf__safeDIBuilder = safeDIOverrides.lazyLeaf
		        func __safeDI_lazyLeaf(safeDIOverrides: (() -> Leaf)?) -> Leaf {
		            if let safeDIBuilder = safeDIOverrides { safeDIBuilder() } else { Leaf() }
		        }
		        let lazyLeaf = LazilyInstantiated<Leaf> {
		            __safeDI_lazyLeaf(safeDIOverrides: __safeDI_lazyLeaf__safeDIBuilder)
		        }
		        let __safeDI_serviceBuilder__safeDIBuilder = safeDIOverrides.serviceBuilder
		        func __safeDI_serviceBuilder(safeDIOverrides: (() -> AnyService)?) -> AnyService {
		            if let safeDIBuilder = safeDIOverrides { safeDIBuilder() } else { AnyService(DefaultService()) }
		        }
		        let serviceBuilder = ErasedInstantiator<(), AnyService> {
		            __safeDI_serviceBuilder(safeDIOverrides: __safeDI_serviceBuilder__safeDIBuilder)
		        }
		        return Store(workerBuilder: workerBuilder, lazyLeaf: lazyLeaf, serviceBuilder: serviceBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Store {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            workerBuilder: Worker.SafeDIMockConfiguration = .init(),
		            lazyLeaf: (@Sendable () -> Leaf)? = nil,
		            serviceBuilder: (@Sendable () -> AnyService)? = nil,
		            _ safeDIBuilder: ((sending Instantiator<Worker>, sending LazilyInstantiated<Leaf>, sending ErasedInstantiator<(), AnyService>) -> Store)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                workerBuilder: workerBuilder,
		                lazyLeaf: lazyLeaf,
		                serviceBuilder: serviceBuilder,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var workerBuilder: Worker.SafeDIMockConfiguration { __safeDI_storage.workerBuilder }
		        var lazyLeaf: (@Sendable () -> Leaf)? { __safeDI_storage.lazyLeaf }
		        var serviceBuilder: (@Sendable () -> AnyService)? { __safeDI_storage.serviceBuilder }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((sending Instantiator<Worker>, sending LazilyInstantiated<Leaf>, sending ErasedInstantiator<(), AnyService>) -> Store)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                workerBuilder: Worker.SafeDIMockConfiguration,
		                lazyLeaf: (@Sendable () -> Leaf)?,
		                serviceBuilder: (@Sendable () -> AnyService)?,
		                safeDIBuilder: ((sending Instantiator<Worker>, sending LazilyInstantiated<Leaf>, sending ErasedInstantiator<(), AnyService>) -> Store)?
		            ) {
		                self.workerBuilder = workerBuilder
		                self.lazyLeaf = lazyLeaf
		                self.serviceBuilder = serviceBuilder
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let workerBuilder: Worker.SafeDIMockConfiguration
		            let lazyLeaf: (@Sendable () -> Leaf)?
		            let serviceBuilder: (@Sendable () -> AnyService)?
		            let safeDIBuilder: ((sending Instantiator<Worker>, sending LazilyInstantiated<Leaf>, sending ErasedInstantiator<(), AnyService>) -> Store)?
		        }
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Store+SafeDIMock.swift"] ?? "")")
	}

	@Test(arguments: [false, true], [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenActorAndClassBuildSameInstantiatorOfLeaf(buildsClassFirst: Bool, leafIsSendable: Bool) async throws {
		// The generated mock is compiled as it ships, with a leaf that is `Sendable` and one that is not, and with the
		// actor or the class built first. The override is set through both, through the actor alone, and through the class
		// alone.
		let fixture = Self.sharedWrapperFixture(buildsClassFirst: buildsClassFirst, leafIsSendable: leafIsSendable)
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, _) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		// The two write other text, so the comparison is of two programs.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] != walkOutput.mockFiles["Root+SafeDIMock.swift"])
		let throughActor = "a: .init(leafBuilder: { Leaf(marker: \"a.leafBuilder\") })"
		let throughClass = "b: .init(leafBuilder: { Leaf(marker: \"b.leafBuilder\") })"
		let throughBoth = (buildsClassFirst ? [throughClass, throughActor] : [throughActor, throughClass]).joined(separator: ", ")
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: fixture, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: fixture, generatedFiles: #require(walkOutput.generatedFiles)),
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe(name: "overridden through both", expression: "Root.mock(safeDIOverrides: .init(\(throughBoth)))"),
				DifferentialValueProbe(name: "overridden through the actor", expression: "Root.mock(safeDIOverrides: .init(\(throughActor)))"),
				DifferentialValueProbe(name: "overridden through the class", expression: "Root.mock(safeDIOverrides: .init(\(throughClass)))"),
			],
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// Each override is read where it alone is set: the other place builds its leaf.
		let described = comparison.featureDescription.components(separatedBy: "probe ")
		for (probe, markers) in [("overridden through both", ["a.leafBuilder", "b.leafBuilder"]), ("overridden through the actor", ["a.leafBuilder", "built"]), ("overridden through the class", ["b.leafBuilder", "built"])] {
			let description = described.first { $0.hasPrefix(probe) } ?? ""
			for marker in markers {
				#expect(description.contains("\"\(marker)\""), "No value of \(probe) is marked \(marker):\n\(comparison.featureDescription)")
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenActorBuildsEveryKindOfWrapperAndEachIsOverridden() async throws {
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.wrapperFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, _) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.wrapperFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		// The two write other text, so the comparison is of two programs.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] != walkOutput.mockFiles["Root+SafeDIMock.swift"])
		let store = """
		.init(\
		workerBuilder: .init(leaf: { marked(Leaf(), "workerBuilder.leaf") }, { marked(Worker(leaf: $0), "workerBuilder") }), \
		lazyLeaf: { marked(Leaf(), "lazyLeaf") }, \
		serviceBuilder: { AnyService(marked(DefaultService(), "serviceBuilder")) })
		"""
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: Self.wrapperFixture, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: Self.wrapperFixture, generatedFiles: #require(walkOutput.generatedFiles)),
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe(name: "overridden root", expression: "Root.mock(safeDIOverrides: .init(store: \(store), mockedStore: .init(leafBuilder: { marked(Leaf(), \"mockedStore.leafBuilder\") })))"),
				DifferentialValueProbe("Store.mock()"),
				DifferentialValueProbe(name: "overridden actor root", expression: "Store.mock(safeDIOverrides: \(store))"),
			],
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// The comparator calls no `ErasedInstantiator`, so the erased wrapper's override is compared as present only.
		for marker in ["workerBuilder", "workerBuilder.leaf", "lazyLeaf", "mockedStore.leafBuilder"] {
			#expect(comparison.featureDescription.contains("\"\(marker)\""), "No value is marked \(marker):\n\(comparison.featureDescription)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsTheWalksStatements_whenSiblingTakesNameOfLocalActorsWrapperReads() async throws {
		// The override of the actor's instantiator is read into a local named as the function a sibling would be built in,
		// which the walk names apart, so the world is refused, and the walk writes it.
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(store: Store) {
			        self.store = store
			    }

			    @Instantiated let store: Store
			}
			""",
			"""
			@Instantiable
			public actor Store: Instantiable {
			    public init(leafBuilder: Instantiator<Leaf>, leafBuilder__safeDIBuilder: Leaf) {
			        self.leafBuilder = leafBuilder
			        self.leafBuilder__safeDIBuilder = leafBuilder__safeDIBuilder
			    }

			    @Instantiated let leafBuilder: Instantiator<Leaf>
			    @Instantiated let leafBuilder__safeDIBuilder: Leaf
			}
			""",
			"""
			@Instantiable
			public final class Leaf: Instantiable {
			    public init() {}
			}
			""",
		]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [["mockActor"]])
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [false])
		#expect(output.generatedFiles == walkOutput.generatedFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesOverrideToFunctionWithoutLocal_whenActorBuildsNodeReadingRename() async throws {
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.renameReaderFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.renameReaderFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true, true])
		// The walk reads the reader's override into a local its function captures; the records' function reads it from
		// `mock()`'s overrides, which an actor's mock makes `Sendable` (its storage is a `Sendable` class of `@Sendable`
		// closures), so capturing them is no transfer of a region and the local has nothing to do.
		#expect(walkOutput.mockFiles["Shelf+SafeDIMock.swift"]?.contains("let __safeDI_reader__safeDIBuilder = safeDIOverrides.reader") == true)
		#expect(output.mockFiles["Shelf+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Shelf {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            source: (@Sendable () -> Source)? = nil,
		            reader: (@Sendable (Source) -> Reader)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                source: source,
		                reader: reader
		            )
		        }

		        var source: (@Sendable () -> Source)? { __safeDI_storage.source }
		        var reader: (@Sendable (Source) -> Reader)? { __safeDI_storage.reader }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                source: (@Sendable () -> Source)?,
		                reader: (@Sendable (Source) -> Reader)?
		            ) {
		                self.source = source
		                self.reader = reader
		            }

		            let source: (@Sendable () -> Source)?
		            let reader: (@Sendable (Source) -> Reader)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Shelf {
		        let source = if let safeDIBuilder = safeDIOverrides.source { safeDIBuilder() } else { Source() }
		        func __safeDI_reader() -> Reader {
		            #sourceLocation(file: "\(output.fixtures["Reader.swift"])", line: 7)
		            let namedSource: Source = source
		            #sourceLocation()
		            return if let safeDIBuilder = safeDIOverrides.reader { safeDIBuilder(namedSource) } else { Reader(namedSource: namedSource) }
		        }
		        let reader: Reader = __safeDI_reader()
		        return Shelf(source: source, reader: reader)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Shelf+SafeDIMock.swift"] ?? "")")
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: Self.renameReaderFixture, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: Self.renameReaderFixture, generatedFiles: #require(walkOutput.generatedFiles)),
			probes: [
				DifferentialValueProbe("Shelf.mock()"),
				DifferentialValueProbe(name: "overridden reader", expression: "Shelf.mock(safeDIOverrides: .init(reader: { marked(Reader(namedSource: $0), \"reader\") }))"),
			],
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		#expect(comparison.featureDescription.contains("\"reader\""), "No value is marked reader:\n\(comparison.featureDescription)")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A root that builds an actor in place and through an `Instantiator`, and the actor's own mock. The actor takes a
	/// configured argument, a leaf argument and another actor it receives. Each class carries a marker an override's
	/// closure sets, and the received actor one its second initializer takes.
	/// A root that builds an actor and a class, each handed an `Instantiator` of one leaf it builds: the class first
	/// where `buildsClassFirst`, and a leaf that is a `Sendable` struct where `leafIsSendable`, and a class otherwise.
	private static func sharedWrapperFixture(buildsClassFirst: Bool, leafIsSendable: Bool) -> [String: String] {
		let properties = buildsClassFirst ? [("b", "B"), ("a", "A")] : [("a", "A"), ("b", "B")]
		return [
			"A.swift": """
			@Instantiable
			public actor A: Instantiable {
			    public init(leafBuilder: Instantiator<Leaf>) {
			        self.leafBuilder = leafBuilder
			    }

			    @Instantiated let leafBuilder: Instantiator<Leaf>
			}
			""",
			"B.swift": """
			@Instantiable
			public final class B: Instantiable {
			    public init(leafBuilder: Instantiator<Leaf>) {
			        self.leafBuilder = leafBuilder
			    }

			    @Instantiated let leafBuilder: Instantiator<Leaf>
			}
			""",
			"Leaf.swift": """
			@Instantiable
			public \(leafIsSendable ? "struct Leaf: Instantiable, Sendable" : "final class Leaf: Instantiable") {
			    public init() {
			        marker = "built"
			    }

			    public init(marker: String) {
			        self.marker = marker
			    }

			    public let marker: String
			}
			""",
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(\(properties.map { "\($0.0): \($0.1)" }.joined(separator: ", "))) {
			        self.a = a
			        self.b = b
			    }

			\(properties.map { "    @Instantiated let \($0.0): \($0.1)" }.joined(separator: "\n"))
			}
			""",
		]
	}

	/// A root that builds an actor handed each kind of wrapper it builds, one of a type that builds a child, and an actor
	/// built with its hand-written mock; the first actor has a mock of its own.
	private static let wrapperFixture: [String: String] = [
		"Leaf.swift": """
		@Instantiable
		public final class Leaf: Instantiable, Marked {
		    public init() {}

		    public var marker = "built"
		}
		""",
		"Marked.swift": """
		public protocol Marked: AnyObject {
		    var marker: String { get set }
		}

		public func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
		    value.marker = marker
		    return value
		}
		""",
		"MockedStore.swift": """
		@Instantiable
		public actor MockedStore: Instantiable {
		    public init(leafBuilder: Instantiator<Leaf>) {
		        self.leafBuilder = leafBuilder
		        marker = "built"
		    }

		    public static func mock(leafBuilder: Instantiator<Leaf>) -> MockedStore {
		        MockedStore(marker: leafBuilder.instantiate().marker)
		    }

		    private init(marker: String) {
		        leafBuilder = Instantiator { Leaf() }
		        self.marker = marker
		    }

		    @Instantiated public let leafBuilder: Instantiator<Leaf>
		    public nonisolated let marker: String
		}
		""",
		"Root.swift": """
		@Instantiable(generateMock: true)
		public final class Root: Instantiable {
		    public init(store: Store, mockedStore: MockedStore) {
		        self.store = store
		        self.mockedStore = mockedStore
		    }

		    @Instantiated let store: Store
		    @Instantiated let mockedStore: MockedStore
		}
		""",
		"Service.swift": """
		public protocol Service {}

		public final class AnyService: Service {
		    public init(_ service: some Service) {
		        self.service = service
		    }

		    public let service: any Service
		}

		@Instantiable(fulfillingAdditionalTypes: [Service.self])
		public final class DefaultService: Service, Instantiable, Marked {
		    public init() {}

		    public var marker = "built"
		}
		""",
		"Store.swift": """
		@Instantiable(generateMock: true)
		public actor Store: Instantiable {
		    public init(workerBuilder: Instantiator<Worker>, lazyLeaf: LazilyInstantiated<Leaf>, serviceBuilder: ErasedInstantiator<(), AnyService>) {
		        self.workerBuilder = workerBuilder
		        self.lazyLeaf = lazyLeaf
		        self.serviceBuilder = serviceBuilder
		    }

		    @Instantiated public let workerBuilder: Instantiator<Worker>
		    @Instantiated public let lazyLeaf: LazilyInstantiated<Leaf>
		    @Instantiated(fulfilledByType: "DefaultService", erasedToConcreteExistential: true) public let serviceBuilder: ErasedInstantiator<(), AnyService>
		}
		""",
		"Worker.swift": """
		@Instantiable
		public final class Worker: Instantiable, Marked {
		    public init(leaf: Leaf) {
		        self.leaf = leaf
		    }

		    @Instantiated public let leaf: Leaf
		    public var marker = "built"
		}
		""",
	]

	private static let renameReaderFixture: [String: String] = [
		"Marked.swift": """
		public protocol Marked: AnyObject {
		    var marker: String { get set }
		}

		public func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
		    value.marker = marker
		    return value
		}
		""",
		"Shelf.swift": """
		@Instantiable(generateMock: true)
		public actor Shelf: Instantiable {
		    public init(source: Source, reader: Reader) {
		        self.source = source
		        self.reader = reader
		    }

		    @Instantiated let source: Source
		    @Instantiated let reader: Reader
		}
		""",
		"Source.swift": """
		@Instantiable
		public final class Source: Instantiable, Sendable {
		    public init() {}
		}
		""",
		"Reader.swift": """
		@Instantiable(generateMock: true)
		public final class Reader: Instantiable, Marked {
		    public init(namedSource: Source) {
		        self.namedSource = namedSource
		    }

		    @Received(fulfilledByDependencyNamed: "source", ofType: Source.self) let namedSource: Source
		    public var marker = "built"
		}
		""",
	]

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
