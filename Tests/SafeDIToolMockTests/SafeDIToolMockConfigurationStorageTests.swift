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

/// A mock's `SafeDIOverrides`, each `SafeDIMockConfiguration`, and a public mock's module-level configuration keep their
/// fields behind one reference, so that a configuration nested in another, which every builder function of a mock
/// captures, is copied as one reference rather than as every field beneath it.
struct SafeDIToolMockConfigurationStorageTests: ~Copyable {
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
	mutating func mock_keepsFieldsBehindOneReference_whenConfigurationHoldsAnotherConfiguration() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Root: Instantiable {
				    public init(child: Child, service: Service) {
				        self.child = child
				        self.service = service
				    }

				    @Instantiated let child: Child
				    @Instantiated let service: Service
				}
				""",
				"""
				@Instantiable
				public struct Child: Instantiable {
				    public init(grand: Grand, capacity: Int = 10) {
				        self.grand = grand
				    }

				    @Instantiated let grand: Grand
				}
				""",
				"@Instantiable\npublic struct Grand: Instantiable {\n    public init() {}\n}",
				"@Instantiable\npublic struct Service: Instantiable {\n    public init() {}\n}",
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
			            child: Child.SafeDIMockConfiguration = .init(),
			            service: (() -> Service)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                child: child,
			                service: service
			            )
			        }

			        var child: Child.SafeDIMockConfiguration { __safeDI_storage.child }
			        var service: (() -> Service)? { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                child: Child.SafeDIMockConfiguration,
			                service: (() -> Service)?
			            ) {
			                self.child = child
			                self.service = service
			            }

			            let child: Child.SafeDIMockConfiguration
			            let service: (() -> Service)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_child() -> Child {
			            let grand = if let safeDIBuilder = safeDIOverrides.child.grand { safeDIBuilder() } else { Grand() }
			            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(grand, safeDIOverrides.child.capacity) } else { Child(grand: grand, capacity: safeDIOverrides.child.capacity) }
			        }
			        let child: Child = __safeDI_child()
			        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service() }
			        return Root(child: child, service: service)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Child {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            grand: (() -> Grand)? = nil,
			            capacity: Int = 10,
			            _ safeDIBuilder: ((Grand, Int) -> Child)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grand: grand,
			                capacity: capacity,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var grand: (() -> Grand)? { __safeDI_storage.grand }
			        var capacity: Int { __safeDI_storage.capacity }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Grand, Int) -> Child)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grand: (() -> Grand)?,
			                capacity: Int,
			                safeDIBuilder: ((Grand, Int) -> Child)?
			            ) {
			                self.grand = grand
			                self.capacity = capacity
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let grand: (() -> Grand)?
			            let capacity: Int
			            let safeDIBuilder: ((Grand, Int) -> Child)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_declaresStorageSendable_whenEveryFieldIsSendable() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Root: Instantiable {
				    public init(childBuilder: SendableInstantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: SendableInstantiator<Child>
				}
				""",
				"""
				@Instantiable
				public struct Child: Instantiable, Sendable {
				    public init(grand: Grand, capacity: Int = 10) {
				        self.grand = grand
				    }

				    @Instantiated let grand: Grand
				}
				""",
				"@Instantiable\npublic struct Grand: Instantiable, Sendable {\n    public init() {}\n}",
			],
			swiftFileContentByFilePath: [
				// The compile fails unless both configurations are `Sendable`, as they were when their fields were stored.
				"SendableChecks.swift": """
				#if DEBUG
				func requireSendable<T: Sendable>(_: T.Type) {}

				func checkConfigurationsAreSendable() {
				    requireSendable(Root.SafeDIOverrides.self)
				    requireSendable(Child.SafeDIMockConfiguration.self)
				}
				#endif
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
			            childBuilder: Child.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                childBuilder: childBuilder
			            )
			        }

			        var childBuilder: Child.SafeDIMockConfiguration { __safeDI_storage.childBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                childBuilder: Child.SafeDIMockConfiguration
			            ) {
			                self.childBuilder = childBuilder
			            }

			            let childBuilder: Child.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_childBuilder__overrides = safeDIOverrides.childBuilder
			        @Sendable nonisolated func __safeDI_childBuilder() -> Child {
			            let grand = if let safeDIBuilder = __safeDI_childBuilder__overrides.grand { safeDIBuilder() } else { Grand() }
			            return if let safeDIBuilder = __safeDI_childBuilder__overrides.safeDIBuilder { safeDIBuilder(grand, __safeDI_childBuilder__overrides.capacity()) } else { Child(grand: grand, capacity: __safeDI_childBuilder__overrides.capacity()) }
			        }
			        let childBuilder = SendableInstantiator<Child>(__safeDI_childBuilder)
			        return Root(childBuilder: childBuilder)
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
			            grand: (@Sendable () -> Grand)? = nil,
			            capacity: @autoclosure @escaping @Sendable () -> Int = 10,
			            _ safeDIBuilder: (@Sendable (Grand, Int) -> Child)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grand: grand,
			                capacity: capacity,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var grand: (@Sendable () -> Grand)? { __safeDI_storage.grand }
			        var capacity: @Sendable () -> Int { __safeDI_storage.capacity }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Grand, Int) -> Child)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                grand: (@Sendable () -> Grand)?,
			                capacity: @escaping @Sendable () -> Int,
			                safeDIBuilder: (@Sendable (Grand, Int) -> Child)?
			            ) {
			                self.grand = grand
			                self.capacity = capacity
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let grand: (@Sendable () -> Grand)?
			            let capacity: @Sendable () -> Int
			            let safeDIBuilder: (@Sendable (Grand, Int) -> Child)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_declaresStorageSendableOnlyForConfigurationsWhoseFieldsAreAllSendable_whenOneFieldOfOverridesIsNotSendable() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Root: Instantiable {
				    public init(childBuilder: SendableInstantiator<Child>, service: Service) {
				        self.childBuilder = childBuilder
				        self.service = service
				    }

				    @Instantiated let childBuilder: SendableInstantiator<Child>
				    @Instantiated let service: Service
				}
				""",
				"""
				@Instantiable
				public struct Child: Instantiable, Sendable {
				    public init(capacity: Int = 10) {}
				}
				""",
				"@Instantiable\npublic struct Service: Instantiable {\n    public init() {}\n}",
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
			            childBuilder: Child.SafeDIMockConfiguration = .init(),
			            service: (() -> Service)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                childBuilder: childBuilder,
			                service: service
			            )
			        }

			        var childBuilder: Child.SafeDIMockConfiguration { __safeDI_storage.childBuilder }
			        var service: (() -> Service)? { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                childBuilder: Child.SafeDIMockConfiguration,
			                service: (() -> Service)?
			            ) {
			                self.childBuilder = childBuilder
			                self.service = service
			            }

			            let childBuilder: Child.SafeDIMockConfiguration
			            let service: (() -> Service)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_childBuilder__overrides = safeDIOverrides.childBuilder
			        @Sendable nonisolated func __safeDI_childBuilder() -> Child {
			            if let safeDIBuilder = __safeDI_childBuilder__overrides.safeDIBuilder { safeDIBuilder(__safeDI_childBuilder__overrides.capacity()) } else { Child(capacity: __safeDI_childBuilder__overrides.capacity()) }
			        }
			        let childBuilder = SendableInstantiator<Child>(__safeDI_childBuilder)
			        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service() }
			        return Root(childBuilder: childBuilder, service: service)
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
			            capacity: @autoclosure @escaping @Sendable () -> Int = 10,
			            _ safeDIBuilder: (@Sendable (Int) -> Child)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                capacity: capacity,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var capacity: @Sendable () -> Int { __safeDI_storage.capacity }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Int) -> Child)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                capacity: @escaping @Sendable () -> Int,
			                safeDIBuilder: (@Sendable (Int) -> Child)?
			            ) {
			                self.capacity = capacity
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let capacity: @Sendable () -> Int
			            let safeDIBuilder: (@Sendable (Int) -> Child)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_storesOverrideOfReceiveOnlyIfAvailableBesideStorage_whenOverridesHoldsBoth() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Root: Instantiable {
				    public init(childBuilder: SendableInstantiator<Child>, user: User?) {
				        self.childBuilder = childBuilder
				        self.user = user
				    }

				    @Instantiated let childBuilder: SendableInstantiator<Child>
				    @Received(onlyIfAvailable: true) let user: User?
				}
				""",
				"""
				@Instantiable
				public struct Child: Instantiable, Sendable {
				    public init() {}
				}
				""",
			],
			swiftFileContentByFilePath: [
				// The overrides stay `Sendable` where the type of what the mock receives only if available is, as they were
				// when every field was stored, since SafeDI cannot tell whether that type is.
				"User.swift": """
				public struct User: Sendable {}

				#if DEBUG
				func requireSendable<T: Sendable>(_: T.Type) {}

				func checkOverridesAreSendable() {
				    requireSendable(Root.SafeDIOverrides.self)
				}
				#endif
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
			            childBuilder: (@Sendable () -> Child)? = nil,
			            user: User? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                childBuilder: childBuilder
			            )
			            self.user = user
			        }

			        var childBuilder: (@Sendable () -> Child)? { __safeDI_storage.childBuilder }
			        let user: User?

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                childBuilder: (@Sendable () -> Child)?
			            ) {
			                self.childBuilder = childBuilder
			            }

			            let childBuilder: (@Sendable () -> Child)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let user: User? = safeDIOverrides.user
			        let __safeDI_childBuilder__safeDIBuilder = safeDIOverrides.childBuilder
			        @Sendable nonisolated func __safeDI_childBuilder() -> Child {
			            if let safeDIBuilder = __safeDI_childBuilder__safeDIBuilder { safeDIBuilder() } else { Child() }
			        }
			        let childBuilder = SendableInstantiator<Child>(__safeDI_childBuilder)
			        return Root(childBuilder: childBuilder, user: user)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_declaresNoStorage_whenOverridesHoldOnlyOverridesOfReceivesOnlyIfAvailable() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Root: Instantiable {
				    public init(user: User?) {
				        self.user = user
				    }

				    @Received(onlyIfAvailable: true) let user: User?
				}
				""",
			],
			swiftFileContentByFilePath: [
				"User.swift": "public struct User {}",
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
			            user: User? = nil
			        ) {
			            self.user = user
			        }

			        let user: User?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let user: User? = safeDIOverrides.user
			        return Root(user: user)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsFieldsBehindOneReferenceWithMainActorIsolation_whenModuleDefaultsToMainActorAndConfiguredTypesAreOnIt() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(child: Child) {
				        self.child = child
				    }

				    @Instantiated let child: Child
				}
				""",
				"""
				@MainActor
				@Instantiable
				public final class Child: Instantiable {
				    public init(grand: Grand, capacity: Int = 10) {
				        self.grand = grand
				    }

				    @Instantiated let grand: Grand
				}
				""",
				"@Instantiable\npublic final class Grand: Instantiable {\n    public init() {}\n}",
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
			            child: Child.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                child: child
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

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_child() -> Child {
			            let grand = if let safeDIBuilder = safeDIOverrides.child.grand { safeDIBuilder() } else { Grand() }
			            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(grand, safeDIOverrides.child.capacity) } else { Child(grand: grand, capacity: safeDIOverrides.child.capacity) }
			        }
			        let child: Child = __safeDI_child()
			        return Root(child: child)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Child {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            grand: (() -> Grand)? = nil,
			            capacity: Int = 10,
			            _ safeDIBuilder: ((Grand, Int) -> Child)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grand: grand,
			                capacity: capacity,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var grand: (() -> Grand)? { __safeDI_storage.grand }
			        var capacity: Int { __safeDI_storage.capacity }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Grand, Int) -> Child)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grand: (() -> Grand)?,
			                capacity: Int,
			                safeDIBuilder: ((Grand, Int) -> Child)?
			            ) {
			                self.grand = grand
			                self.capacity = capacity
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let grand: (() -> Grand)?
			            let capacity: Int
			            let safeDIBuilder: ((Grand, Int) -> Child)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsPublicConfigurationFieldsBehindOneReference_whenEachInitializerAssignsTheMembersItOmits() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    init(child: Child) {
				        self.child = child
				    }

				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				struct Child: Instantiable {
				    init(grand: Grand, capacity: Int = 10) {
				        self.grand = grand
				    }

				    @Instantiated let grand: Grand
				}
				""",
				"@Instantiable\nstruct Grand: Instantiable {\n    init() {}\n}",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Child` is constructed within the public mock trees of this module.
			nonisolated public struct __safeDI_Child_MockConfiguration {
			    public init(
			        capacity: Int? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            grand: nil,
			            capacity: capacity,
			            safeDIBuilder: nil
			        )
			    }

			    init(
			        grand: (() -> Grand)? = nil,
			        capacity: Int? = nil,
			        _ safeDIBuilder: ((Grand, Int) -> Child)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            grand: grand,
			            capacity: capacity,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    var grand: (() -> Grand)? { __safeDI_storage.grand }
			    /// `nil` keeps the default of `Child`’s `capacity`.
			    public var capacity: Int? { __safeDI_storage.capacity }
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    var safeDIBuilder: ((Grand, Int) -> Child)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            grand: (() -> Grand)?,
			            capacity: Int?,
			            safeDIBuilder: ((Grand, Int) -> Child)?
			        ) {
			            self.grand = grand
			            self.capacity = capacity
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let grand: (() -> Grand)?
			        let capacity: Int?
			        let safeDIBuilder: ((Grand, Int) -> Child)?
			    }
			}

			extension Child {
			    static func __safeDI_init(grand: Grand, capacity: Int?, safeDIBuilder: ((Grand, Int) -> Child)?) -> Child {
			        let capacity = capacity ?? (10)
			        return if let safeDIBuilder { safeDIBuilder(grand, capacity) } else { Child(grand: grand, capacity: capacity) }
			    }
			}
			#endif

			""",
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            child: __safeDI_Child_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                child: child
			            )
			        }

			        public var child: __safeDI_Child_MockConfiguration { __safeDI_storage.child }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                child: __safeDI_Child_MockConfiguration
			            ) {
			                self.child = child
			            }

			            let child: __safeDI_Child_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        Service.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        func __safeDI_child() -> Child {
			            let grand = if let safeDIBuilder = safeDIOverrides.child.grand { safeDIBuilder() } else { Grand() }
			            return Child.__safeDI_init(grand: grand, capacity: safeDIOverrides.child.capacity, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)
			        }
			        let child: Child = __safeDI_child()
			        return Service(child: child)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compilesWithinMemoryLimit_whenTwentyFourChainedSeamsEachBuildThreeOfTheNextLayer() async throws {
		// Six layers of four seams, each seam building three of the next layer's: the mock builds one builder function
		// per path through them, each of which captures the overrides. A configuration copied by value into each made the
		// compiler's memory grow with the square of the paths, past 12 GB at this depth.
		let layerCount = 6
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.chainedSeams(layerCount: layerCount),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(memoryLimitInMegabytes: Self.chainedSeamsMemoryLimitInMegabytes),
		)

		// The mock is thousands of lines long, so its count of builder functions stands in for it: one for each path from
		// the root to a seam, four in the first layer and three times as many in each layer after it.
		let mock = try #require(output.generatedFiles?["Root+SafeDIMock.swift"])
		let builderFunctionCount = mock.split(separator: "\n").count { $0.trimmingCharacters(in: .whitespaces).hasPrefix("func __safeDI_screen") }
		#expect(builderFunctionCount == (0..<layerCount).reduce(into: (count: 0, layerPathCount: 4)) { result, _ in result = (result.count + result.layerPathCount, result.layerPathCount * 3) }.count)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The virtual memory the compile of `chainedSeams(layerCount: 6)` may use on Linux. A compile that copies each
	/// configuration by value into every builder function exceeds it many times over. Only Linux enforces the limit
	/// (`VerificationCompilerSettings.memoryLimitInMegabytes`): on macOS the test compiles without one, so there it shows
	/// only that the mock compiles.
	private static let chainedSeamsMemoryLimitInMegabytes = 2_048

	/// A root that builds the four seams of the first of `layerCount` layers through instantiators, each seam building a
	/// model and, through instantiators, the three seams of the next layer whose index in their layer differs from its own.
	/// Every seam forwards an `id` and receives the root's `service`.
	private static func chainedSeams(layerCount: Int) -> [String] {
		func screenName(layer: Int, index: Int) -> String {
			"Screen\(layer * 4 + index)"
		}
		func builders(ofLayer layer: Int, besides excludedIndex: Int?) -> [(label: String, type: String)] {
			(0..<4).filter { $0 != excludedIndex }.map { index in
				let name = screenName(layer: layer, index: index)
				return (label: "\(name.prefix(1).lowercased())\(name.dropFirst())Builder", type: "Instantiator<\(name)>")
			}
		}
		func declaration(of name: String, attributes: String, properties: [(attribute: String, label: String, type: String)]) -> String {
			var lines = ["@Instantiable\(attributes)", "public final class \(name): Instantiable {"]
			lines.append("    public init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {")
			lines.append(contentsOf: properties.map { "        self.\($0.label) = \($0.label)" })
			lines.append("    }")
			lines.append("")
			lines.append(contentsOf: properties.map { "    @\($0.attribute) let \($0.label): \($0.type)" })
			lines.append("}")
			return lines.joined(separator: "\n")
		}

		var files = [String]()
		var rootProperties = [(attribute: "Instantiated", label: "service", type: "Service")]
		rootProperties.append(contentsOf: builders(ofLayer: 0, besides: nil).map { (attribute: "Instantiated", label: $0.label, type: $0.type) })
		files.append(declaration(of: "Root", attributes: "(generateMock: true)", properties: rootProperties))
		files.append(declaration(of: "Service", attributes: "", properties: []))
		for layer in 0..<layerCount {
			for index in 0..<4 {
				let name = screenName(layer: layer, index: index)
				let modelName = "Model\(layer * 4 + index)"
				var properties = [
					(attribute: "Forwarded", label: "id", type: "Int"),
					(attribute: "Received", label: "service", type: "Service"),
					(attribute: "Instantiated", label: "model\(layer * 4 + index)", type: modelName),
				]
				if layer + 1 < layerCount {
					properties.append(contentsOf: builders(ofLayer: layer + 1, besides: index).map { (attribute: "Instantiated", label: $0.label, type: $0.type) })
				}
				files.append(
					declaration(of: name, attributes: "(generateDependencyTree: true)", properties: properties)
						+ "\n\n"
						+ declaration(of: modelName, attributes: "", properties: [
							(attribute: "Received", label: "id", type: "Int"),
							(attribute: "Received", label: "service", type: "Service"),
						]),
				)
			}
		}
		return files
	}
}
