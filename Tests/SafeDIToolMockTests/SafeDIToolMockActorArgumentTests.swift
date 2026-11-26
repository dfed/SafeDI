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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compilesPublicActorMock_whenActorsArgumentHoldsInstantiator() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
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
				    public init(childBuilder: Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
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
			/// Configuration for how `Worker` is constructed within the public mock trees of this module.
			nonisolated public struct __safeDI_Worker_MockConfiguration {
			    public init(
			        childBuilder: (@Sendable () -> Child)? = nil,
			        _ safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            childBuilder: childBuilder,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var childBuilder: (@Sendable () -> Child)? { __safeDI_storage.childBuilder }
			    /// Overrides how `Worker` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
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

			extension Worker {
			    static func __safeDI_init(childBuilder: Instantiator<Child>, safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)?) -> Worker {
			        if let safeDIBuilder { safeDIBuilder(childBuilder) } else { Worker(childBuilder: childBuilder) }
			    }
			}
			#endif

			""",
			"Store+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Store {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            worker: __safeDI_Worker_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                worker: worker
			            )
			        }

			        public var worker: __safeDI_Worker_MockConfiguration { __safeDI_storage.worker }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                worker: __safeDI_Worker_MockConfiguration
			            ) {
			                self.worker = worker
			            }

			            let worker: __safeDI_Worker_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Store {
			        Store.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Store {
			        let __safeDI_worker__worker_childBuilder_safeDIBuilder = safeDIOverrides.worker.childBuilder
			        let __safeDI_worker__safeDIBuilder = safeDIOverrides.worker.safeDIBuilder
			        func __safeDI_worker() -> Worker {
			            func __safeDI_childBuilder() -> Child {
			                if let safeDIBuilder = __safeDI_worker__worker_childBuilder_safeDIBuilder { safeDIBuilder() } else { Child() }
			            }
			            let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
			            return Worker.__safeDI_init(childBuilder: childBuilder, safeDIBuilder: __safeDI_worker__safeDIBuilder)
			        }
			        let worker: Worker = __safeDI_worker()
			        return Store(worker: worker)
			    }
			}

			extension Store {
			    public enum __safeDI_Store_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compilesPublicMock_whenActorInItsTreeHasArgumentHoldingInstantiator() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
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
				    public init(worker: Worker) {
				        self.worker = worker
				    }

				    @Instantiated let worker: Worker
				}
				""",
				"""
				@Instantiable
				public final class Worker: Instantiable {
				    public init(childBuilder: Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init() {}
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
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            store: __safeDI_Store_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                store: store
			            )
			        }

			        public var store: __safeDI_Store_MockConfiguration { __safeDI_storage.store }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                store: __safeDI_Store_MockConfiguration
			            ) {
			                self.store = store
			            }

			            let store: __safeDI_Store_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        Root.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_store() -> Store {
			            let __safeDI_worker__store_worker_childBuilder_safeDIBuilder = safeDIOverrides.store.worker.childBuilder
			            let __safeDI_worker__safeDIBuilder = safeDIOverrides.store.worker.safeDIBuilder
			            func __safeDI_worker() -> Worker {
			                func __safeDI_childBuilder() -> Child {
			                    if let safeDIBuilder = __safeDI_worker__store_worker_childBuilder_safeDIBuilder { safeDIBuilder() } else { Child() }
			                }
			                let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
			                return Worker.__safeDI_init(childBuilder: childBuilder, safeDIBuilder: __safeDI_worker__safeDIBuilder)
			            }
			            let worker: Worker = __safeDI_worker()
			            return Store.__safeDI_init(worker: worker, safeDIBuilder: safeDIOverrides.store.safeDIBuilder)
			        }
			        let store: Store = __safeDI_store()
			        return Root(store: store)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Worker` is constructed within the public mock trees of this module.
			nonisolated public struct __safeDI_Worker_MockConfiguration {
			    public init(
			        childBuilder: (@Sendable () -> Child)? = nil,
			        _ safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            childBuilder: childBuilder,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var childBuilder: (@Sendable () -> Child)? { __safeDI_storage.childBuilder }
			    /// Overrides how `Worker` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
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

			extension Worker {
			    static func __safeDI_init(childBuilder: Instantiator<Child>, safeDIBuilder: (@Sendable (Instantiator<Child>) -> Worker)?) -> Worker {
			        if let safeDIBuilder { safeDIBuilder(childBuilder) } else { Worker(childBuilder: childBuilder) }
			    }
			}

			/// Configuration for how `Store` is constructed within the public mock trees of this module.
			nonisolated public struct __safeDI_Store_MockConfiguration {
			    public init(
			        worker: __safeDI_Worker_MockConfiguration = .init(),
			        _ safeDIBuilder: ((sending Worker) -> Store)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            worker: worker,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var worker: __safeDI_Worker_MockConfiguration { __safeDI_storage.worker }
			    /// Overrides how `Store` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((sending Worker) -> Store)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            worker: __safeDI_Worker_MockConfiguration,
			            safeDIBuilder: ((sending Worker) -> Store)?
			        ) {
			            self.worker = worker
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let worker: __safeDI_Worker_MockConfiguration
			        let safeDIBuilder: ((sending Worker) -> Store)?
			    }
			}

			extension Store {
			    static func __safeDI_init(worker: sending Worker, safeDIBuilder: ((sending Worker) -> Store)?) -> Store {
			        if let safeDIBuilder { safeDIBuilder(worker) } else { Store(worker: worker) }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	mutating func mock_compilesPublicMocks_whenActorsArgumentHasDefaultValuedParameterAndPublicMockCallsActor() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol Helping {}

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
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Client+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Client {
			    public static func mock(
			        timeout: Int? = nil
			    ) -> Client {
			        Client.__safeDI_mock(timeout: timeout)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
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
			        timeout: @autoclosure @escaping @Sendable () -> Int? = nil,
			        _ safeDIBuilder: (@Sendable (Int) -> Client)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            timeout: timeout,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// `nil` keeps the default of `Client`’s `timeout`.
			    public var timeout: @Sendable () -> Int? { __safeDI_storage.timeout }
			    /// Overrides how `Client` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: (@Sendable (Int) -> Client)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            timeout: @escaping @Sendable () -> Int?,
			            safeDIBuilder: (@Sendable (Int) -> Client)?
			        ) {
			            self.timeout = timeout
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let timeout: @Sendable () -> Int?
			        let safeDIBuilder: (@Sendable (Int) -> Client)?
			    }
			}

			extension Client {
			    static func __safeDI_init(timeout: Int?, safeDIBuilder: (@Sendable (Int) -> Client)?) -> Client {
			        let timeout = timeout ?? (30)
			        return if let safeDIBuilder { safeDIBuilder(timeout) } else { Client(timeout: timeout) }
			    }
			}

			/// Configuration for how `Store` is constructed within the public mock trees of this module.
			nonisolated public struct __safeDI_Store_MockConfiguration {
			    public init(
			        client: __safeDI_Client_MockConfiguration = .init(),
			        _ safeDIBuilder: ((sending Client) -> Store)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            client: client,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var client: __safeDI_Client_MockConfiguration { __safeDI_storage.client }
			    /// Overrides how `Store` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((sending Client) -> Store)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            client: __safeDI_Client_MockConfiguration,
			            safeDIBuilder: ((sending Client) -> Store)?
			        ) {
			            self.client = client
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let client: __safeDI_Client_MockConfiguration
			        let safeDIBuilder: ((sending Client) -> Store)?
			    }
			}

			extension Store {
			    static func __safeDI_init(client: sending Client, safeDIBuilder: ((sending Client) -> Store)?) -> Store {
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

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_store() -> Store {
			            let __safeDI_client__safeDIBuilder = safeDIOverrides.store.client.safeDIBuilder
			            let __safeDI_client__store_client_timeout = safeDIOverrides.store.client.timeout
			            func __safeDI_client() -> Client {
			                return Client.__safeDI_init(timeout: __safeDI_client__store_client_timeout(), safeDIBuilder: __safeDI_client__safeDIBuilder)
			            }
			            let client: Client = __safeDI_client()
			            return Store.__safeDI_init(client: client, safeDIBuilder: safeDIOverrides.store.safeDIBuilder)
			        }
			        let store: Store = __safeDI_store()
			        func __safeDI_client() -> Client {
			            return Client.__safeDI_init(timeout: safeDIOverrides.client.timeout(), safeDIBuilder: safeDIOverrides.client.safeDIBuilder)
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

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Store {
			        Store.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Store {
			        let __safeDI_client__safeDIBuilder = safeDIOverrides.client.safeDIBuilder
			        let __safeDI_client__client_timeout = safeDIOverrides.client.timeout
			        func __safeDI_client() -> Client {
			            return Client.__safeDI_init(timeout: __safeDI_client__client_timeout(), safeDIBuilder: __safeDI_client__safeDIBuilder)
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

	// MARK: Private

	private var filesToDelete: [URL]
}
