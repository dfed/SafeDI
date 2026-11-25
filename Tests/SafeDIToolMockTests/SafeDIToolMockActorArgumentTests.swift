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

/// An actor’s initializer takes each argument across the actor’s isolation boundary, so in Swift 6 an argument must not
/// share a region with `mock()`’s `safeDIOverrides`. Each argument’s overrides are read into a local of the `Sendable` form
/// before its builder function, as inside a `Sendable` wrapper, so no builder function beneath the actor captures them.
struct SafeDIToolMockActorArgumentTests: ~Copyable {
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
	mutating func mock_compilesActorRootMock_whenActorsArgumentHoldsInstantiator() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public actor Root: Instantiable {
				    public init(worker: Worker) {
				        self.worker = worker
				    }

				    @Instantiated let worker: Worker
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Worker: Instantiable {
				    public init(childBuilder: Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Child: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Child+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Child {
			    static func mock() -> Child {
			        Child()
			    }
			}
			#endif
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_childBuilder() -> Child {
			            Child()
			        }
			        func __safeDI_worker() -> Worker {
			            let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
			            return Worker(childBuilder: childBuilder)
			        }
			        let worker: Worker = __safeDI_worker()
			        self.init(worker: worker)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            worker: Worker.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                worker: worker
			            )
			        }

			        var worker: Worker.SafeDIMockConfiguration { __safeDI_storage.worker }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                worker: Worker.SafeDIMockConfiguration
			            ) {
			                self.worker = worker
			            }

			            let worker: Worker.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_worker__overrides = safeDIOverrides.worker
			        func __safeDI_worker() -> Worker {
			            func __safeDI_childBuilder() -> Child {
			                if let safeDIBuilder = __safeDI_worker__overrides.childBuilder { safeDIBuilder() } else { Child() }
			            }
			            let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
			            return if let safeDIBuilder = __safeDI_worker__overrides.safeDIBuilder { safeDIBuilder(childBuilder) } else { Worker(childBuilder: childBuilder) }
			        }
			        let worker: Worker = __safeDI_worker()
			        return Root(worker: worker)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
			"Worker+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Worker {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            childBuilder: (() -> Child)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                childBuilder: childBuilder
			            )
			        }

			        var childBuilder: (() -> Child)? { __safeDI_storage.childBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                childBuilder: (() -> Child)?
			            ) {
			                self.childBuilder = childBuilder
			            }

			            let childBuilder: (() -> Child)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Worker {
			        func __safeDI_childBuilder() -> Child {
			            if let safeDIBuilder = safeDIOverrides.childBuilder { safeDIBuilder() } else { Child() }
			        }
			        let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
			        return Worker(childBuilder: childBuilder)
			    }
			}
			#endif

			#if DEBUG
			extension Worker {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            childBuilder: (@Sendable () -> Child)? = nil,
			            _ safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                childBuilder: childBuilder,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var childBuilder: (@Sendable () -> Child)? { __safeDI_storage.childBuilder }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                childBuilder: (@Sendable () -> Child)?,
			                safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)?
			            ) {
			                self.childBuilder = childBuilder
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let childBuilder: (@Sendable () -> Child)?
			            let safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)?
			        }
			    }
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compilesMock_whenActorBesideLaterSiblingHasArgumentHoldingInstantiator() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(store: Store, other: Other) {
				        self.store = store
				        self.other = other
				    }

				    @Instantiated let store: Store
				    @Instantiated let other: Other
				}
				""",
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
				@Instantiable(generateMock: true)
				public final class Worker: Instantiable {
				    public init(childBuilder: Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Child: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Other: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Child+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Child {
			    static func mock() -> Child {
			        Child()
			    }
			}
			#endif
			""",
			"Other+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Other {
			    static func mock() -> Other {
			        Other()
			    }
			}
			#endif
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_worker() -> Worker {
			            let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
			            return Worker(childBuilder: childBuilder)
			        }
			        func __safeDI_childBuilder() -> Child {
			            Child()
			        }
			        func __safeDI_store() -> Store {
			            let worker: Worker = __safeDI_worker()
			            return Store(worker: worker)
			        }
			        let store: Store = __safeDI_store()
			        let other = Other()
			        self.init(store: store, other: other)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            store: Store.SafeDIMockConfiguration = .init(),
			            other: (() -> Other)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                store: store,
			                other: other
			            )
			        }

			        var store: Store.SafeDIMockConfiguration { __safeDI_storage.store }
			        var other: (() -> Other)? { __safeDI_storage.other }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                store: Store.SafeDIMockConfiguration,
			                other: (() -> Other)?
			            ) {
			                self.store = store
			                self.other = other
			            }

			            let store: Store.SafeDIMockConfiguration
			            let other: (() -> Other)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_store() -> Store {
			            let __safeDI_worker__overrides = safeDIOverrides.store.worker
			            func __safeDI_worker() -> Worker {
			                func __safeDI_childBuilder() -> Child {
			                    if let safeDIBuilder = __safeDI_worker__overrides.childBuilder { safeDIBuilder() } else { Child() }
			                }
			                let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
			                return if let safeDIBuilder = __safeDI_worker__overrides.safeDIBuilder { safeDIBuilder(childBuilder) } else { Worker(childBuilder: childBuilder) }
			            }
			            let worker: Worker = __safeDI_worker()
			            return if let safeDIBuilder = safeDIOverrides.store.safeDIBuilder { safeDIBuilder(worker) } else { Store(worker: worker) }
			        }
			        let store: Store = __safeDI_store()
			        let other = if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder() } else { Other() }
			        return Root(store: store, other: other)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
			"Store+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Store {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            worker: Worker.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                worker: worker
			            )
			        }

			        var worker: Worker.SafeDIMockConfiguration { __safeDI_storage.worker }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                worker: Worker.SafeDIMockConfiguration
			            ) {
			                self.worker = worker
			            }

			            let worker: Worker.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Store {
			        let __safeDI_worker__overrides = safeDIOverrides.worker
			        func __safeDI_worker() -> Worker {
			            func __safeDI_childBuilder() -> Child {
			                if let safeDIBuilder = __safeDI_worker__overrides.childBuilder { safeDIBuilder() } else { Child() }
			            }
			            let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
			            return if let safeDIBuilder = __safeDI_worker__overrides.safeDIBuilder { safeDIBuilder(childBuilder) } else { Worker(childBuilder: childBuilder) }
			        }
			        let worker: Worker = __safeDI_worker()
			        return Store(worker: worker)
			    }
			}
			#endif

			#if DEBUG
			extension Store {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            worker: Worker.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((sending Worker) -> Store)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                worker: worker,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var worker: Worker.SafeDIMockConfiguration { __safeDI_storage.worker }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((sending Worker) -> Store)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                worker: Worker.SafeDIMockConfiguration,
			                safeDIBuilder: ((sending Worker) -> Store)?
			            ) {
			                self.worker = worker
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let worker: Worker.SafeDIMockConfiguration
			            let safeDIBuilder: ((sending Worker) -> Store)?
			        }
			    }
			}
			#endif
			""",
			"Worker+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Worker {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            childBuilder: (() -> Child)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                childBuilder: childBuilder
			            )
			        }

			        var childBuilder: (() -> Child)? { __safeDI_storage.childBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                childBuilder: (() -> Child)?
			            ) {
			                self.childBuilder = childBuilder
			            }

			            let childBuilder: (() -> Child)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Worker {
			        func __safeDI_childBuilder() -> Child {
			            if let safeDIBuilder = safeDIOverrides.childBuilder { safeDIBuilder() } else { Child() }
			        }
			        let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
			        return Worker(childBuilder: childBuilder)
			    }
			}
			#endif

			#if DEBUG
			extension Worker {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            childBuilder: (@Sendable () -> Child)? = nil,
			            _ safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                childBuilder: childBuilder,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var childBuilder: (@Sendable () -> Child)? { __safeDI_storage.childBuilder }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                childBuilder: (@Sendable () -> Child)?,
			                safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)?
			            ) {
			                self.childBuilder = childBuilder
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let childBuilder: (@Sendable () -> Child)?
			            let safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)?
			        }
			    }
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compilesOverrideThatHandsItsArgumentToActorsInitializer_whenActorsArgumentHoldsInstantiator() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(store: Store, other: Other) {
				        self.store = store
				        self.other = other
				    }

				    @Instantiated let store: Store
				    @Instantiated let other: Other
				}
				""",
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
				@Instantiable(generateMock: true)
				public final class Worker: Instantiable {
				    public init(childBuilder: Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Child: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Other: Instantiable {
				    public init() {}
				}
				""",
				"""
				#if DEBUG
				func storeBuiltByOverride() -> Root {
				    Root.mock(safeDIOverrides: .init(store: .init { worker in Store(worker: worker) }))
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Child+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Child {
			    static func mock() -> Child {
			        Child()
			    }
			}
			#endif
			""",
			"Other+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Other {
			    static func mock() -> Other {
			        Other()
			    }
			}
			#endif
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_worker() -> Worker {
			            let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
			            return Worker(childBuilder: childBuilder)
			        }
			        func __safeDI_childBuilder() -> Child {
			            Child()
			        }
			        func __safeDI_store() -> Store {
			            let worker: Worker = __safeDI_worker()
			            return Store(worker: worker)
			        }
			        let store: Store = __safeDI_store()
			        let other = Other()
			        self.init(store: store, other: other)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            store: Store.SafeDIMockConfiguration = .init(),
			            other: (() -> Other)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                store: store,
			                other: other
			            )
			        }

			        var store: Store.SafeDIMockConfiguration { __safeDI_storage.store }
			        var other: (() -> Other)? { __safeDI_storage.other }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                store: Store.SafeDIMockConfiguration,
			                other: (() -> Other)?
			            ) {
			                self.store = store
			                self.other = other
			            }

			            let store: Store.SafeDIMockConfiguration
			            let other: (() -> Other)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_store() -> Store {
			            let __safeDI_worker__overrides = safeDIOverrides.store.worker
			            func __safeDI_worker() -> Worker {
			                func __safeDI_childBuilder() -> Child {
			                    if let safeDIBuilder = __safeDI_worker__overrides.childBuilder { safeDIBuilder() } else { Child() }
			                }
			                let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
			                return if let safeDIBuilder = __safeDI_worker__overrides.safeDIBuilder { safeDIBuilder(childBuilder) } else { Worker(childBuilder: childBuilder) }
			            }
			            let worker: Worker = __safeDI_worker()
			            return if let safeDIBuilder = safeDIOverrides.store.safeDIBuilder { safeDIBuilder(worker) } else { Store(worker: worker) }
			        }
			        let store: Store = __safeDI_store()
			        let other = if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder() } else { Other() }
			        return Root(store: store, other: other)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
			"Store+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Store {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            worker: Worker.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                worker: worker
			            )
			        }

			        var worker: Worker.SafeDIMockConfiguration { __safeDI_storage.worker }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                worker: Worker.SafeDIMockConfiguration
			            ) {
			                self.worker = worker
			            }

			            let worker: Worker.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Store {
			        let __safeDI_worker__overrides = safeDIOverrides.worker
			        func __safeDI_worker() -> Worker {
			            func __safeDI_childBuilder() -> Child {
			                if let safeDIBuilder = __safeDI_worker__overrides.childBuilder { safeDIBuilder() } else { Child() }
			            }
			            let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
			            return if let safeDIBuilder = __safeDI_worker__overrides.safeDIBuilder { safeDIBuilder(childBuilder) } else { Worker(childBuilder: childBuilder) }
			        }
			        let worker: Worker = __safeDI_worker()
			        return Store(worker: worker)
			    }
			}
			#endif

			#if DEBUG
			extension Store {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            worker: Worker.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((sending Worker) -> Store)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                worker: worker,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var worker: Worker.SafeDIMockConfiguration { __safeDI_storage.worker }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((sending Worker) -> Store)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                worker: Worker.SafeDIMockConfiguration,
			                safeDIBuilder: ((sending Worker) -> Store)?
			            ) {
			                self.worker = worker
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let worker: Worker.SafeDIMockConfiguration
			            let safeDIBuilder: ((sending Worker) -> Store)?
			        }
			    }
			}
			#endif
			""",
			"Worker+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Worker {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            childBuilder: (() -> Child)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                childBuilder: childBuilder
			            )
			        }

			        var childBuilder: (() -> Child)? { __safeDI_storage.childBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                childBuilder: (() -> Child)?
			            ) {
			                self.childBuilder = childBuilder
			            }

			            let childBuilder: (() -> Child)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Worker {
			        func __safeDI_childBuilder() -> Child {
			            if let safeDIBuilder = safeDIOverrides.childBuilder { safeDIBuilder() } else { Child() }
			        }
			        let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
			        return Worker(childBuilder: childBuilder)
			    }
			}
			#endif

			#if DEBUG
			extension Worker {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            childBuilder: (@Sendable () -> Child)? = nil,
			            _ safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                childBuilder: childBuilder,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var childBuilder: (@Sendable () -> Child)? { __safeDI_storage.childBuilder }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                childBuilder: (@Sendable () -> Child)?,
			                safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)?
			            ) {
			                self.childBuilder = childBuilder
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let childBuilder: (@Sendable () -> Child)?
			            let safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)?
			        }
			    }
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compilesActorRootMock_whenInstantiatorTwoLevelsBeneathActorBuildsConfiguredType() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public actor Root: Instantiable {
				    public init(worker: Worker) {
				        self.worker = worker
				    }

				    @Instantiated let worker: Worker
				}
				""",
				"""
				@Instantiable
				public final class Worker: Instantiable {
				    public init(helper: Helper) {
				        self.helper = helper
				    }

				    @Instantiated let helper: Helper
				}
				""",
				"""
				@Instantiable
				public final class Helper: Instantiable {
				    public init(childBuilder: Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(name: String = "child") {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_helper() -> Helper {
			            let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
			            return Helper(childBuilder: childBuilder)
			        }
			        func __safeDI_childBuilder() -> Child {
			            Child()
			        }
			        func __safeDI_worker() -> Worker {
			            let helper: Helper = __safeDI_helper()
			            return Worker(helper: helper)
			        }
			        let worker: Worker = __safeDI_worker()
			        self.init(worker: worker)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            worker: Worker.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                worker: worker
			            )
			        }

			        var worker: Worker.SafeDIMockConfiguration { __safeDI_storage.worker }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                worker: Worker.SafeDIMockConfiguration
			            ) {
			                self.worker = worker
			            }

			            let worker: Worker.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_worker__overrides = safeDIOverrides.worker
			        func __safeDI_worker() -> Worker {
			            func __safeDI_helper() -> Helper {
			                func __safeDI_childBuilder() -> Child {
			                    if let safeDIBuilder = __safeDI_worker__overrides.helper.childBuilder.safeDIBuilder { safeDIBuilder(__safeDI_worker__overrides.helper.childBuilder.name()) } else { Child(name: __safeDI_worker__overrides.helper.childBuilder.name()) }
			                }
			                let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
			                return if let safeDIBuilder = __safeDI_worker__overrides.helper.safeDIBuilder { safeDIBuilder(childBuilder) } else { Helper(childBuilder: childBuilder) }
			            }
			            let helper: Helper = __safeDI_helper()
			            return if let safeDIBuilder = __safeDI_worker__overrides.safeDIBuilder { safeDIBuilder(helper) } else { Worker(helper: helper) }
			        }
			        let worker: Worker = __safeDI_worker()
			        return Root(worker: worker)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Child {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            name: @autoclosure @escaping @Sendable () -> String = "child",
			            _ safeDIBuilder: (@Sendable (String) -> Child)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                name: name,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var name: @Sendable () -> String { __safeDI_storage.name }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (String) -> Child)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                name: @escaping @Sendable () -> String,
			                safeDIBuilder: (@Sendable (String) -> Child)?
			            ) {
			                self.name = name
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let name: @Sendable () -> String
			            let safeDIBuilder: (@Sendable (String) -> Child)?
			        }
			    }
			}

			extension Helper {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            childBuilder: Child.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: (@Sendable (Instantiator<Child>) -> Helper)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                childBuilder: childBuilder,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var childBuilder: Child.SafeDIMockConfiguration { __safeDI_storage.childBuilder }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Instantiator<Child>) -> Helper)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                childBuilder: Child.SafeDIMockConfiguration,
			                safeDIBuilder: (@Sendable (Instantiator<Child>) -> Helper)?
			            ) {
			                self.childBuilder = childBuilder
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let childBuilder: Child.SafeDIMockConfiguration
			            let safeDIBuilder: (@Sendable (Instantiator<Child>) -> Helper)?
			        }
			    }
			}

			extension Worker {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            helper: Helper.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: (@Sendable (Helper) -> Worker)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                helper: helper,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var helper: Helper.SafeDIMockConfiguration { __safeDI_storage.helper }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Helper) -> Worker)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                helper: Helper.SafeDIMockConfiguration,
			                safeDIBuilder: (@Sendable (Helper) -> Worker)?
			            ) {
			                self.helper = helper
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let helper: Helper.SafeDIMockConfiguration
			            let safeDIBuilder: (@Sendable (Helper) -> Worker)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compilesActorMock_whenLazyWrapperBeneathActorsArgumentCapturesValueTheArgumentAlsoTakes() async throws {
		// `Child`’s builder function captures `token`, which `Worker` also takes: a builder function beneath the actor that
		// returned `sending` could not send a value that shares `token`’s region, so none reads the overrides itself.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
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
				    public init(token: Token, helper: Helper) {
				        self.token = token
				        self.helper = helper
				    }

				    @Instantiated let token: Token
				    @Instantiated let helper: Helper
				}
				""",
				"""
				@Instantiable
				public final class Helper: Instantiable {
				    public init(child: LazilyInstantiated<Child>) {
				        self.child = child
				    }

				    @Instantiated let child: LazilyInstantiated<Child>
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(token: Token, name: String = "child") {
				        self.token = token
				    }

				    @Received let token: Token
				}
				""",
				"""
				@Instantiable
				public final class Token: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Child {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            name: @autoclosure @escaping @Sendable () -> String = "child",
			            _ safeDIBuilder: (@Sendable (Token, String) -> Child)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                name: name,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var name: @Sendable () -> String { __safeDI_storage.name }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Token, String) -> Child)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                name: @escaping @Sendable () -> String,
			                safeDIBuilder: (@Sendable (Token, String) -> Child)?
			            ) {
			                self.name = name
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let name: @Sendable () -> String
			            let safeDIBuilder: (@Sendable (Token, String) -> Child)?
			        }
			    }
			}

			extension Helper {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            child: Child.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: (@Sendable (LazilyInstantiated<Child>) -> Helper)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                child: child,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var child: Child.SafeDIMockConfiguration { __safeDI_storage.child }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (LazilyInstantiated<Child>) -> Helper)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                child: Child.SafeDIMockConfiguration,
			                safeDIBuilder: (@Sendable (LazilyInstantiated<Child>) -> Helper)?
			            ) {
			                self.child = child
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let child: Child.SafeDIMockConfiguration
			            let safeDIBuilder: (@Sendable (LazilyInstantiated<Child>) -> Helper)?
			        }
			    }
			}

			extension Worker {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            token: (@Sendable () -> Token)? = nil,
			            helper: Helper.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: (@Sendable (Token, Helper) -> Worker)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                token: token,
			                helper: helper,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var token: (@Sendable () -> Token)? { __safeDI_storage.token }
			        var helper: Helper.SafeDIMockConfiguration { __safeDI_storage.helper }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Token, Helper) -> Worker)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                token: (@Sendable () -> Token)?,
			                helper: Helper.SafeDIMockConfiguration,
			                safeDIBuilder: (@Sendable (Token, Helper) -> Worker)?
			            ) {
			                self.token = token
			                self.helper = helper
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let token: (@Sendable () -> Token)?
			            let helper: Helper.SafeDIMockConfiguration
			            let safeDIBuilder: (@Sendable (Token, Helper) -> Worker)?
			        }
			    }
			}
			#endif

			""",
			"Store+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Store {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            worker: Worker.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                worker: worker
			            )
			        }

			        var worker: Worker.SafeDIMockConfiguration { __safeDI_storage.worker }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                worker: Worker.SafeDIMockConfiguration
			            ) {
			                self.worker = worker
			            }

			            let worker: Worker.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Store {
			        let __safeDI_worker__overrides = safeDIOverrides.worker
			        func __safeDI_worker() -> Worker {
			            let token = if let safeDIBuilder = __safeDI_worker__overrides.token { safeDIBuilder() } else { Token() }
			            func __safeDI_helper() -> Helper {
			                func __safeDI_child() -> Child {
			                    if let safeDIBuilder = __safeDI_worker__overrides.helper.child.safeDIBuilder { safeDIBuilder(token, __safeDI_worker__overrides.helper.child.name()) } else { Child(token: token, name: __safeDI_worker__overrides.helper.child.name()) }
			                }
			                let child = LazilyInstantiated<Child>(__safeDI_child)
			                return if let safeDIBuilder = __safeDI_worker__overrides.helper.safeDIBuilder { safeDIBuilder(child) } else { Helper(child: child) }
			            }
			            let helper: Helper = __safeDI_helper()
			            return if let safeDIBuilder = __safeDI_worker__overrides.safeDIBuilder { safeDIBuilder(token, helper) } else { Worker(token: token, helper: helper) }
			        }
			        let worker: Worker = __safeDI_worker()
			        return Store(worker: worker)
			    }
			}
			#endif
			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
