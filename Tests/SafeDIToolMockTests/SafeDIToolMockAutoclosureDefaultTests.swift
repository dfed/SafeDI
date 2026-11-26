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

/// A labeled, default-valued `@autoclosure` parameter of a construction initializer, an extension's `instantiate(…)`,
/// or a hand-written mock: a generated mock takes the value as an autoclosure of its own, or stores it as a closure,
/// and passes the closure's call, so the value is evaluated where the type is built, once per construction, as in
/// production.
struct SafeDIToolMockAutoclosureDefaultTests: ~Copyable {
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
	mutating func dependencyTree_isUnchanged_whenInitializerHasDefaultValuedAutoclosureParameter() async throws {
		// Production leaves the parameter to its default, as 2.2.0 did.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Dependency: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable(isRoot: true)
				public final class Service: Instantiable {
				    public init(dependency: Dependency, retries: @autoclosure () -> Int = 3) {
				        self.dependency = dependency
				        self.retries = retries()
				    }

				    @Instantiated let dependency: Dependency
				    let retries: Int
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Service+SafeDI.swift": generatedFileHeader + """
			extension Service {
			    public convenience init() {
			        let dependency = Dependency()
			        self.init(dependency: dependency)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesCallOfOwnAutoclosureParameter_whenMockedTypesInitializerHasDefaultValuedAutoclosureParameter() async throws {
		// `mock()` takes the value as an autoclosure of its own and passes its call. 2.2.0 passed the autoclosure itself, which did not compile.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Dependency: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Service: Instantiable {
				    public init(dependency: Dependency, retries: @autoclosure () -> Int = 3) {
				        self.dependency = dependency
				        self.retries = retries()
				    }

				    @Instantiated let dependency: Dependency
				    let retries: Int
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            dependency: (() -> Dependency)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                dependency: dependency
			            )
			        }

			        var dependency: (() -> Dependency)? { __safeDI_storage.dependency }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                dependency: (() -> Dependency)?
			            ) {
			                self.dependency = dependency
			            }

			            let dependency: (() -> Dependency)?
			        }
			    }

			    static func mock(
			        retries: @escaping @autoclosure () -> Int = 3,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let dependency = if let safeDIBuilder = safeDIOverrides.dependency { safeDIBuilder() } else { Dependency() }
			        return Service(dependency: dependency, retries: retries())
			    }
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_storesClosureInConfiguration_whenTypeInMockedTreeHasDefaultValuedAutoclosureParameter() async throws {
		// The configuration stores a closure that returns the value, which each construction the `Instantiator` makes calls, and the builder takes the value.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(serviceBuilder: Instantiator<Service>) {
				        self.serviceBuilder = serviceBuilder
				    }

				    @Instantiated let serviceBuilder: Instantiator<Service>
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable {
				    public init(retries: @autoclosure () -> Int = 3) {
				        self.retries = retries()
				    }

				    let retries: Int
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_serviceBuilder() -> Service {
			            Service()
			        }
			        let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
			        self.init(serviceBuilder: serviceBuilder)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            serviceBuilder: Service.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                serviceBuilder: serviceBuilder
			            )
			        }

			        var serviceBuilder: Service.SafeDIMockConfiguration { __safeDI_storage.serviceBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                serviceBuilder: Service.SafeDIMockConfiguration
			            ) {
			                self.serviceBuilder = serviceBuilder
			            }

			            let serviceBuilder: Service.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_serviceBuilder() -> Service {
			            if let safeDIBuilder = safeDIOverrides.serviceBuilder.safeDIBuilder { safeDIBuilder(safeDIOverrides.serviceBuilder.retries()) } else { Service(retries: safeDIOverrides.serviceBuilder.retries()) }
			        }
			        let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
			        return Root(serviceBuilder: serviceBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            retries: @autoclosure @escaping () -> Int = 3,
			            _ safeDIBuilder: ((Int) -> Service)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                retries: retries,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var retries: () -> Int { __safeDI_storage.retries }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int) -> Service)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                retries: @escaping () -> Int,
			                safeDIBuilder: ((Int) -> Service)?
			            ) {
			                self.retries = retries
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let retries: () -> Int
			            let safeDIBuilder: ((Int) -> Service)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_storesClosureInConfiguration_whenExtensionsInstantiateHasDefaultValuedAutoclosureParameter() async throws {
		// An extension's `instantiate(…)` is passed the value as an initializer is.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
				"""
				public final class Service {
				    init(retries: Int) {
				        self.retries = retries
				    }

				    let retries: Int
				}

				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(retries: @autoclosure () -> Int = 3) -> Service {
				        Service(retries: retries())
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let service: Service = Service.instantiate()
			        self.init(service: service)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: Service.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service
			            )
			        }

			        var service: Service.SafeDIMockConfiguration { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: Service.SafeDIMockConfiguration
			            ) {
			                self.service = service
			            }

			            let service: Service.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_service() -> Service {
			            return if let safeDIBuilder = safeDIOverrides.service.safeDIBuilder { safeDIBuilder(safeDIOverrides.service.retries()) } else { Service.instantiate(retries: safeDIOverrides.service.retries()) }
			        }
			        let service: Service = __safeDI_service()
			        return Root(service: service)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            retries: @autoclosure @escaping () -> Int = 3,
			            _ safeDIBuilder: ((Int) -> Service)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                retries: retries,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var retries: () -> Int { __safeDI_storage.retries }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int) -> Service)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                retries: @escaping () -> Int,
			                safeDIBuilder: ((Int) -> Service)?
			            ) {
			                self.retries = retries
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let retries: () -> Int
			            let safeDIBuilder: ((Int) -> Service)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_storesClosureInConfiguration_whenHandWrittenMockHasDefaultValuedAutoclosureParameter() async throws {
		// A hand-written mock's `@autoclosure` parameter is passed the value as an initializer's is.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(serviceBuilder: Instantiator<Service>) {
				        self.serviceBuilder = serviceBuilder
				    }

				    @Instantiated let serviceBuilder: Instantiator<Service>
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable {
				    public init(retries: Int) {
				        self.retries = retries
				    }

				    @Forwarded let retries: Int

				    public static func mock(retries: Int, attempts: @autoclosure () -> Int = 3) -> Service {
				        Service(retries: retries + attempts())
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_serviceBuilder(retries: Int) -> Service {
			            Service(retries: retries)
			        }
			        let serviceBuilder = Instantiator<Service> {
			            __safeDI_serviceBuilder(retries: $0)
			        }
			        self.init(serviceBuilder: serviceBuilder)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            serviceBuilder: Service.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                serviceBuilder: serviceBuilder
			            )
			        }

			        var serviceBuilder: Service.SafeDIMockConfiguration { __safeDI_storage.serviceBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                serviceBuilder: Service.SafeDIMockConfiguration
			            ) {
			                self.serviceBuilder = serviceBuilder
			            }

			            let serviceBuilder: Service.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_serviceBuilder(retries: Int) -> Service {
			            if let safeDIBuilder = safeDIOverrides.serviceBuilder.safeDIBuilder { safeDIBuilder(retries, safeDIOverrides.serviceBuilder.attempts()) } else { Service.mock(retries: retries, attempts: safeDIOverrides.serviceBuilder.attempts()) }
			        }
			        let serviceBuilder = Instantiator<Service> {
			            __safeDI_serviceBuilder(retries: $0)
			        }
			        return Root(serviceBuilder: serviceBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            attempts: @autoclosure @escaping () -> Int = 3,
			            _ safeDIBuilder: ((Int, Int) -> Service)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                attempts: attempts,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var attempts: () -> Int { __safeDI_storage.attempts }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int, Int) -> Service)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                attempts: @escaping () -> Int,
			                safeDIBuilder: ((Int, Int) -> Service)?
			            ) {
			                self.attempts = attempts
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let attempts: () -> Int
			            let safeDIBuilder: ((Int, Int) -> Service)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_storesSendableClosureInConfiguration_whenTypeBuiltInSendableBuilderHasDefaultValuedAutoclosureParameter() async throws {
		// A configuration a `@Sendable` builder function reads stores the `@Sendable` closure it stores for every value.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(serviceBuilder: SendableInstantiator<Service>) {
				        self.serviceBuilder = serviceBuilder
				    }

				    @Instantiated let serviceBuilder: SendableInstantiator<Service>
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable, Sendable {
				    public init(retries: @autoclosure () -> Int = 3) {
				        self.retries = retries()
				    }

				    let retries: Int
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        @Sendable nonisolated func __safeDI_serviceBuilder() -> Service {
			            Service()
			        }
			        let serviceBuilder = SendableInstantiator<Service>(__safeDI_serviceBuilder)
			        self.init(serviceBuilder: serviceBuilder)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            serviceBuilder: Service.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                serviceBuilder: serviceBuilder
			            )
			        }

			        var serviceBuilder: Service.SafeDIMockConfiguration { __safeDI_storage.serviceBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                serviceBuilder: Service.SafeDIMockConfiguration
			            ) {
			                self.serviceBuilder = serviceBuilder
			            }

			            let serviceBuilder: Service.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_serviceBuilder__overrides = safeDIOverrides.serviceBuilder
			        @Sendable nonisolated func __safeDI_serviceBuilder() -> Service {
			            if let safeDIBuilder = __safeDI_serviceBuilder__overrides.safeDIBuilder { safeDIBuilder(__safeDI_serviceBuilder__overrides.retries()) } else { Service(retries: __safeDI_serviceBuilder__overrides.retries()) }
			        }
			        let serviceBuilder = SendableInstantiator<Service>(__safeDI_serviceBuilder)
			        return Root(serviceBuilder: serviceBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            retries: @autoclosure @escaping @Sendable () -> Int = 3,
			            _ safeDIBuilder: (@Sendable (Int) -> Service)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                retries: retries,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var retries: @Sendable () -> Int { __safeDI_storage.retries }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Int) -> Service)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                retries: @escaping @Sendable () -> Int,
			                safeDIBuilder: (@Sendable (Int) -> Service)?
			            ) {
			                self.retries = retries
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let retries: @Sendable () -> Int
			            let safeDIBuilder: (@Sendable (Int) -> Service)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesCallOfOwnAutoclosureParameter_whenInitializerParameterIsAlreadyEscapingAutoclosure() async throws {
		// A parameter declared `@escaping @autoclosure` is passed the call too, which it wraps in a closure that evaluates the value each time the type calls it, as the default does in production.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(service: Service, retries: @escaping @autoclosure () -> Int = 3) {
				        self.service = service
				        self.retries = retries
				    }

				    @Instantiated let service: Service
				    let retries: () -> Int
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable {
				    public init(retries: @escaping @autoclosure () -> Int = 3) {
				        self.retries = retries
				    }

				    let retries: () -> Int
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let service = Service()
			        self.init(service: service)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: Service.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service
			            )
			        }

			        var service: Service.SafeDIMockConfiguration { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: Service.SafeDIMockConfiguration
			            ) {
			                self.service = service
			            }

			            let service: Service.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        retries: @escaping @autoclosure () -> Int = 3,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_service() -> Service {
			            return if let safeDIBuilder = safeDIOverrides.service.safeDIBuilder { safeDIBuilder(safeDIOverrides.service.retries()) } else { Service(retries: safeDIOverrides.service.retries()) }
			        }
			        let service: Service = __safeDI_service()
			        return Root(service: service, retries: retries())
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            retries: @autoclosure @escaping () -> Int = 3,
			            _ safeDIBuilder: ((Int) -> Service)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                retries: retries,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var retries: () -> Int { __safeDI_storage.retries }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int) -> Service)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                retries: @escaping () -> Int,
			                safeDIBuilder: ((Int) -> Service)?
			            ) {
			                self.retries = retries
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let retries: () -> Int
			            let safeDIBuilder: ((Int) -> Service)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_leavesOutUnlabeledAutoclosureParameter_whenItsArgumentLabelIsUnderscore() async throws {
		// A `_`-labeled parameter is left to its default, as before.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(service: Service, _ retries: @autoclosure () -> Int = 3) {
				        self.service = service
				        self.retries = retries()
				    }

				    @Instantiated let service: Service
				    let retries: Int
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable {
				    public init(_ retries: @autoclosure () -> Int = 3) {
				        self.retries = retries()
				    }

				    let retries: Int
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let service = Service()
			        self.init(service: service)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: (() -> Service)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service
			            )
			        }

			        var service: (() -> Service)? { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: (() -> Service)?
			            ) {
			                self.service = service
			            }

			            let service: (() -> Service)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service() }
			        return Root(service: service)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func publicMock_takesOptionalClosure_whenMockedTypeAndTypeInItsTreeHaveDefaultValuedAutoclosureParameters() async throws {
		// A public mock takes the value as an optional closure, which defaults to one that evaluates the default in the declaring module, and calls it where it builds the type.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				struct Child: Instantiable {
				    init(capacity: @autoclosure () -> Int = 10) {}
				}
				""",
				"""
				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    init(child: Child, retries: @autoclosure () -> Int = 3) {
				        self.child = child
				    }

				    @Instantiated let child: Child
				}
				""",
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
			        capacity: (() -> Int)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            capacity: capacity,
			            safeDIBuilder: nil
			        )
			    }

			    init(
			        capacity: (() -> Int)? = nil,
			        _ safeDIBuilder: ((Int) -> Child)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            capacity: capacity,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// `nil` keeps the default of `Child`’s `capacity`.
			    public var capacity: (() -> Int)? { __safeDI_storage.capacity }
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    var safeDIBuilder: ((Int) -> Child)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            capacity: (() -> Int)?,
			            safeDIBuilder: ((Int) -> Child)?
			        ) {
			            self.capacity = capacity
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let capacity: (() -> Int)?
			        let safeDIBuilder: ((Int) -> Child)?
			    }
			}

			extension Child {
			    static func __safeDI_init(capacity: (() -> Int)?, safeDIBuilder: ((Int) -> Child)?) -> Child {
			        let capacity = capacity ?? ({ 10 })
			        return if let safeDIBuilder { safeDIBuilder(capacity()) } else { Child(capacity: capacity()) }
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
			        retries: (() -> Int)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        Service.__safeDI_mock(retries: retries, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        retries: (() -> Int)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let retries = retries ?? ({ 3 })
			        func __safeDI_child() -> Child {
			            return Child.__safeDI_init(capacity: safeDIOverrides.child.capacity, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)
			        }
			        let child: Child = __safeDI_child()
			        return Service(child: child, retries: retries())
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_88F7917B74D30085 {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_storesClosureReturningValue_whenAutoclosureValueIsOptionalFunctionOrExistential() async throws {
		// The value's type is spelled as the closure returns it, whether it is optional, a function, or an existential.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol Formatter {}
				public struct PlainFormatter: Formatter {
				    public init() {}
				}

				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(serviceBuilder: Instantiator<Service>, limit: @autoclosure () -> Int? = 5) {
				        self.serviceBuilder = serviceBuilder
				    }

				    @Instantiated let serviceBuilder: Instantiator<Service>
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable {
				    public init(
				        limit: @autoclosure () -> Int? = 5,
				        onFinish: @autoclosure () -> () -> Void = ({}),
				        formatter: @autoclosure () -> any Formatter = PlainFormatter()
				    ) {
				        self.limit = limit()
				        self.onFinish = onFinish()
				        self.formatter = formatter()
				    }

				    let limit: Int?
				    let onFinish: () -> Void
				    let formatter: any Formatter
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_serviceBuilder() -> Service {
			            Service()
			        }
			        let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
			        self.init(serviceBuilder: serviceBuilder)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            serviceBuilder: Service.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                serviceBuilder: serviceBuilder
			            )
			        }

			        var serviceBuilder: Service.SafeDIMockConfiguration { __safeDI_storage.serviceBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                serviceBuilder: Service.SafeDIMockConfiguration
			            ) {
			                self.serviceBuilder = serviceBuilder
			            }

			            let serviceBuilder: Service.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        limit: @escaping @autoclosure () -> Int? = 5,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_serviceBuilder() -> Service {
			            if let safeDIBuilder = safeDIOverrides.serviceBuilder.safeDIBuilder { safeDIBuilder(safeDIOverrides.serviceBuilder.limit(), safeDIOverrides.serviceBuilder.onFinish(), safeDIOverrides.serviceBuilder.formatter()) } else { Service(limit: safeDIOverrides.serviceBuilder.limit(), onFinish: safeDIOverrides.serviceBuilder.onFinish(), formatter: safeDIOverrides.serviceBuilder.formatter()) }
			        }
			        let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
			        return Root(serviceBuilder: serviceBuilder, limit: limit())
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            limit: @autoclosure @escaping () -> Int? = 5,
			            onFinish: @autoclosure @escaping () -> () -> Void = ({}),
			            formatter: @autoclosure @escaping () -> any Formatter = PlainFormatter(),
			            _ safeDIBuilder: ((Int?, @escaping () -> Void, any Formatter) -> Service)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                limit: limit,
			                onFinish: onFinish,
			                formatter: formatter,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var limit: () -> Int? { __safeDI_storage.limit }
			        var onFinish: () -> () -> Void { __safeDI_storage.onFinish }
			        var formatter: () -> any Formatter { __safeDI_storage.formatter }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int?, @escaping () -> Void, any Formatter) -> Service)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                limit: @escaping () -> Int?,
			                onFinish: @escaping () -> () -> Void,
			                formatter: @escaping () -> any Formatter,
			                safeDIBuilder: ((Int?, @escaping () -> Void, any Formatter) -> Service)?
			            ) {
			                self.limit = limit
			                self.onFinish = onFinish
			                self.formatter = formatter
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let limit: () -> Int?
			            let onFinish: () -> () -> Void
			            let formatter: () -> any Formatter
			            let safeDIBuilder: ((Int?, @escaping () -> Void, any Formatter) -> Service)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func publicMock_storesSendableClosureReturningClosure_whenTypeBuiltInSendableBuilderHasDefaultValuedAutoclosureParameter() async throws {
		// A public configuration a `@Sendable` builder function reads stores a `@Sendable` closure that returns the optional closure, and the construction function calls what it returns.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				final class Child: Instantiable, Sendable {
				    init(limit: @autoclosure () -> Int? = 5) {
				        self.limit = limit()
				    }

				    let limit: Int?
				}
				""",
				"""
				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    init(childBuilder: SendableInstantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: SendableInstantiator<Child>
				}
				""",
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
			        limit: @autoclosure @escaping @Sendable () -> (() -> Int?)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            limit: limit,
			            safeDIBuilder: nil
			        )
			    }

			    init(
			        limit: @autoclosure @escaping @Sendable () -> (() -> Int?)? = nil,
			        _ safeDIBuilder: (@Sendable (Int?) -> Child)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            limit: limit,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// `nil` keeps the default of `Child`’s `limit`.
			    public var limit: @Sendable () -> (() -> Int?)? { __safeDI_storage.limit }
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    var safeDIBuilder: (@Sendable (Int?) -> Child)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            limit: @escaping @Sendable () -> (() -> Int?)?,
			            safeDIBuilder: (@Sendable (Int?) -> Child)?
			        ) {
			            self.limit = limit
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let limit: @Sendable () -> (() -> Int?)?
			        let safeDIBuilder: (@Sendable (Int?) -> Child)?
			    }
			}

			extension Child {
			    static func __safeDI_init(limit: (() -> Int?)?, safeDIBuilder: (@Sendable (Int?) -> Child)?) -> Child {
			        let limit = limit ?? ({ 5 })
			        return if let safeDIBuilder { safeDIBuilder(limit()) } else { Child(limit: limit()) }
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
			            childBuilder: __safeDI_Child_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                childBuilder: childBuilder
			            )
			        }

			        public var childBuilder: __safeDI_Child_MockConfiguration { __safeDI_storage.childBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                childBuilder: __safeDI_Child_MockConfiguration
			            ) {
			                self.childBuilder = childBuilder
			            }

			            let childBuilder: __safeDI_Child_MockConfiguration
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
			        let __safeDI_childBuilder__childBuilder_limit = safeDIOverrides.childBuilder.limit
			        let __safeDI_childBuilder__safeDIBuilder = safeDIOverrides.childBuilder.safeDIBuilder
			        @Sendable nonisolated func __safeDI_childBuilder() -> Child {
			            Child.__safeDI_init(limit: __safeDI_childBuilder__childBuilder_limit(), safeDIBuilder: __safeDI_childBuilder__safeDIBuilder)
			        }
			        let childBuilder = SendableInstantiator<Child>(__safeDI_childBuilder)
			        return Service(childBuilder: childBuilder)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
		])
	}

	@Test(arguments: [MultiModuleIntegration.moduleInfo, .swiftPackagePlugin])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func publicMock_isCalledFromAnotherModule_whenMockedTypeHasDefaultValuedAutoclosureParameter(integration: MultiModuleIntegration) async throws {
		// Another module calls the public mock without the closure, which the declaring module resolves.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.publicMockModules,
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let pluginComment = integration.seamCallComment(type: "Service", declaringModule: "Core")
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Service {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {
			            __safeDI_storage = __safeDI_Storage(
			                session: nil
			            )
			        }

			        package init(
			            session: (() -> Session)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session
			            )
			        }

			        package var session: (() -> Session)? { __safeDI_storage.session }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?
			            ) {
			                self.session = session
			            }

			            let session: (() -> Session)?
			        }
			    }

			    public static func mock(
			        retries: (() -> Int)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        Service.__safeDI_mock(retries: retries, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        retries: (() -> Int)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let retries = retries ?? ({ 3 })
			        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        return Service(session: session, retries: retries())
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_88F7917B74D30085 {}
			}
			#endif
			"""])
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
			#if canImport(Core)
			import Core
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: Service.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service
			            )
			        }

			        var service: Service.SafeDIOverrides { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: Service.SafeDIOverrides
			            ) {
			                self.service = service
			            }

			            let service: Service.SafeDIOverrides
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        _ = Service.__safeDI_Service_mock_88F7917B74D30085.self\(pluginComment)
			        let service = Service.__safeDI_mock(safeDIOverrides: safeDIOverrides.service)
			        return Screen(service: service)
			    }
			}
			#endif
			"""])
		case .swiftPackagePlugin:
			#expect(output.modules["Core"]?.generatedFiles == (integration == .moduleInfo ? [
				"Core.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Service {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init() {
				            __safeDI_storage = __safeDI_Storage(
				                session: nil
				            )
				        }

				        package init(
				            session: (() -> Session)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                session: session
				            )
				        }

				        package var session: (() -> Session)? { __safeDI_storage.session }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                session: (() -> Session)?
				            ) {
				                self.session = session
				            }

				            let session: (() -> Session)?
				        }
				    }

				    public static func mock(
				        retries: (() -> Int)? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Service {
				        Service.__safeDI_mock(retries: retries, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        retries: (() -> Int)? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Service {
				        let retries = retries ?? ({ 3 })
				        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
				        return Service(session: session, retries: retries())
				    }
				}

				extension Service {
				    public enum __safeDI_Service_mock_88F7917B74D30085 {}
				}
				#endif
				""",
			] : [
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif


				""",
				"Service+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Service {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init() {
				            __safeDI_storage = __safeDI_Storage(
				                session: nil
				            )
				        }

				        package init(
				            session: (() -> Session)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                session: session
				            )
				        }

				        package var session: (() -> Session)? { __safeDI_storage.session }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                session: (() -> Session)?
				            ) {
				                self.session = session
				            }

				            let session: (() -> Session)?
				        }
				    }

				    public static func mock(
				        retries: (() -> Int)? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Service {
				        Service.__safeDI_mock(retries: retries, safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        retries: (() -> Int)? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Service {
				        let retries = retries ?? ({ 3 })
				        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
				        return Service(session: session, retries: retries())
				    }
				}

				extension Service {
				    public enum __safeDI_Service_mock_88F7917B74D30085 {}
				}
				#endif
				""",
			]))
			#expect(output.modules["App"]?.generatedFiles == (integration == .moduleInfo ? [
				"App.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Screen {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            service: Service.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                service: service
				            )
				        }

				        var service: Service.SafeDIOverrides { __safeDI_storage.service }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                service: Service.SafeDIOverrides
				            ) {
				                self.service = service
				            }

				            let service: Service.SafeDIOverrides
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        _ = Service.__safeDI_Service_mock_88F7917B74D30085.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				        let service = Service.__safeDI_mock(safeDIOverrides: safeDIOverrides.service)
				        return Screen(service: service)
				    }
				}
				#endif
				""",
			] : [
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif


				""",
				"Screen+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif
				#if canImport(SafeDI)
				import SafeDI
				#endif

				#if DEBUG
				extension Screen {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            service: Service.SafeDIOverrides = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                service: service
				            )
				        }

				        var service: Service.SafeDIOverrides { __safeDI_storage.service }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                service: Service.SafeDIOverrides
				            ) {
				                self.service = service
				            }

				            let service: Service.SafeDIOverrides
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        _ = Service.__safeDI_Service_mock_88F7917B74D30085.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
				        let service = Service.__safeDI_mock(safeDIOverrides: safeDIOverrides.service)
				        return Screen(service: service)
				    }
				}
				#endif
				""",
			]))
		}
	}

	private static let publicMockModules = [
		ModuleFixture(name: "Core", packageName: "corepkg", swiftFileContentByFilePath: ["Service.swift": """
		import SafeDI

		@Instantiable
		package struct Session: Instantiable {
		    package init() {}
		}

		@Instantiable(generateMock: .public)
		public final class Service: Instantiable {
		    package init(session: Session, retries: @autoclosure () -> Int = 3) {
		        self.session = session
		        self.retries = retries()
		    }

		    @Instantiated let session: Session
		    public let retries: Int
		}
		"""]),
		ModuleFixture(name: "App", packageName: "apppkg", swiftFileContentByFilePath: ["Screen.swift": """
		import Core
		import SafeDI

		@Instantiable(generateMock: true)
		public struct Screen: Instantiable {
		    public init(service: Service) {
		        self.service = service
		    }

		    @Instantiated let service: Service
		}
		"""], dependencies: ["Core"]),
	]

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesThrowingAutoclosureParameterAsAutoclosureThatDoesNotThrow_whenMockedTypesDefaultDoesNotThrow() async throws {
		// `mock()` calls the autoclosure where it builds the type, outside any function that throws, so it takes one that does not throw, which the default, or a `try?` in it, satisfies. 2.2.0 passed the autoclosure itself, which did not compile.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public func compute() throws -> Int { 3 }
				@Instantiable(generateMock: true)
				public final class Service: Instantiable {
				    public init(retries: @autoclosure () throws -> Int = 3, limit: @escaping @autoclosure () throws -> Int = (try? compute()) ?? 1) {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    static func mock(
			        retries: @escaping @autoclosure () -> Int = 3,
			        limit: @escaping @autoclosure () -> Int = (try? compute()) ?? 1
			    ) -> Service {
			        return Service(retries: retries(), limit: limit())
			    }
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesThrowingAutoclosureParameterAsAutoclosureThatDoesNotThrow_whenMockedTypesDefaultTriesOnlyInsideAClosure() async throws {
		// A `try` inside a closure the default declares throws out of that closure, never out of the default, so the default does not throw and `mock()` takes the parameter.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public func compute() throws -> Int { 3 }
				@Instantiable(generateMock: true)
				public final class Service: Instantiable {
				    public init(retries: @autoclosure () throws -> Int = { do { return try compute() } catch { return 1 } }()) {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    static func mock(
			        retries: @escaping @autoclosure () -> Int = { do { return try compute() } catch { return 1 } }()
			    ) -> Service {
			        return Service(retries: retries())
			    }
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_leavesThrowingAutoclosureParameterToItsDefault_whenMockedTypesDefaultThrows() async throws {
		// An autoclosure that does not throw cannot hold a default that throws, so `mock()` takes no parameter for it and the initializer evaluates its default, as in production.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public func compute() throws -> Int { 3 }
				@Instantiable(generateMock: true)
				public final class Service: Instantiable {
				    public init(retries: @autoclosure () throws -> Int = try compute()) {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    static func mock() -> Service {
			        Service()
			    }
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_storesClosureThatDoesNotThrowInConfiguration_whenTypeInMockedTreeHasThrowingAutoclosureParameter() async throws {
		// The configuration stores a closure that does not throw, which the construction calls outside any function that throws.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable {
				    public init(retries: @autoclosure () throws -> Int = 3) {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let service = Service()
			        self.init(service: service)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: Service.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service
			            )
			        }

			        var service: Service.SafeDIMockConfiguration { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: Service.SafeDIMockConfiguration
			            ) {
			                self.service = service
			            }

			            let service: Service.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_service() -> Service {
			            return if let safeDIBuilder = safeDIOverrides.service.safeDIBuilder { safeDIBuilder(safeDIOverrides.service.retries()) } else { Service(retries: safeDIOverrides.service.retries()) }
			        }
			        let service: Service = __safeDI_service()
			        return Root(service: service)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            retries: @autoclosure @escaping () -> Int = 3,
			            _ safeDIBuilder: ((Int) -> Service)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                retries: retries,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var retries: () -> Int { __safeDI_storage.retries }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int) -> Service)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                retries: @escaping () -> Int,
			                safeDIBuilder: ((Int) -> Service)?
			            ) {
			                self.retries = retries
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let retries: () -> Int
			            let safeDIBuilder: ((Int) -> Service)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_leavesThrowingAutoclosureParameterToItsDefault_whenTypeInMockedTreeHasThrowingDefault() async throws {
		// The configuration takes no value for a parameter whose default throws, and neither the construction nor its override closure is handed one: the initializer evaluates the default, as in production.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
				"""
				public func compute() throws -> Int { 3 }
				@Instantiable
				public final class Service: Instantiable {
				    public init(retries: @autoclosure () throws -> Int = try compute(), limit: Int = 1) {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let service = Service()
			        self.init(service: service)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: Service.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service
			            )
			        }

			        var service: Service.SafeDIMockConfiguration { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: Service.SafeDIMockConfiguration
			            ) {
			                self.service = service
			            }

			            let service: Service.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_service() -> Service {
			            return if let safeDIBuilder = safeDIOverrides.service.safeDIBuilder { safeDIBuilder(safeDIOverrides.service.limit) } else { Service(limit: safeDIOverrides.service.limit) }
			        }
			        let service: Service = __safeDI_service()
			        return Root(service: service)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            limit: Int = 1,
			            _ safeDIBuilder: ((Int) -> Service)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                limit: limit,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var limit: Int { __safeDI_storage.limit }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int) -> Service)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                limit: Int,
			                safeDIBuilder: ((Int) -> Service)?
			            ) {
			                self.limit = limit
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let limit: Int
			            let safeDIBuilder: ((Int) -> Service)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_storesSendableClosureThatDoesNotThrow_whenTypeBuiltInSendableBuilderHasThrowingAutoclosureParameters() async throws {
		// Beneath a `Sendable` wrapper the configuration stores a `@Sendable` closure that does not throw, and leaves a parameter whose default throws to the initializer.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(serviceBuilder: SendableInstantiator<Service>) {
				        self.serviceBuilder = serviceBuilder
				    }

				    @Instantiated let serviceBuilder: SendableInstantiator<Service>
				}
				""",
				"""
				public func compute() throws -> Int { 3 }
				@Instantiable
				public final class Service: Instantiable, Sendable {
				    public init(retries: @autoclosure () throws -> Int = 3, seed: @autoclosure () throws -> Int = try compute()) {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        @Sendable nonisolated func __safeDI_serviceBuilder() -> Service {
			            Service()
			        }
			        let serviceBuilder = SendableInstantiator<Service>(__safeDI_serviceBuilder)
			        self.init(serviceBuilder: serviceBuilder)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            serviceBuilder: Service.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                serviceBuilder: serviceBuilder
			            )
			        }

			        var serviceBuilder: Service.SafeDIMockConfiguration { __safeDI_storage.serviceBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                serviceBuilder: Service.SafeDIMockConfiguration
			            ) {
			                self.serviceBuilder = serviceBuilder
			            }

			            let serviceBuilder: Service.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_serviceBuilder__overrides = safeDIOverrides.serviceBuilder
			        @Sendable nonisolated func __safeDI_serviceBuilder() -> Service {
			            if let safeDIBuilder = __safeDI_serviceBuilder__overrides.safeDIBuilder { safeDIBuilder(__safeDI_serviceBuilder__overrides.retries()) } else { Service(retries: __safeDI_serviceBuilder__overrides.retries()) }
			        }
			        let serviceBuilder = SendableInstantiator<Service>(__safeDI_serviceBuilder)
			        return Root(serviceBuilder: serviceBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    /// Configuration for how this type is constructed within a mock tree.
			    nonisolated struct SafeDIMockConfiguration: Sendable {
			        init(
			            retries: @autoclosure @escaping @Sendable () -> Int = 3,
			            _ safeDIBuilder: (@Sendable (Int) -> Service)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                retries: retries,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var retries: @Sendable () -> Int { __safeDI_storage.retries }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Int) -> Service)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                retries: @escaping @Sendable () -> Int,
			                safeDIBuilder: (@Sendable (Int) -> Service)?
			            ) {
			                self.retries = retries
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let retries: @Sendable () -> Int
			            let safeDIBuilder: (@Sendable (Int) -> Service)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func publicMock_takesClosureThatDoesNotThrow_whenMockedTypeAndTypeInItsTreeHaveThrowingAutoclosureParameters() async throws {
		// A public mock takes a closure that does not throw, and leaves a parameter whose default throws to the initializer.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				struct Child: Instantiable {
				    init(capacity: @autoclosure () throws -> Int = 10, seed: @autoclosure () throws -> Int = try compute()) {}
				}
				""",
				"""
				public func compute() throws -> Int { 3 }
				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    init(child: Child, retries: @autoclosure () throws -> Int = 3, seed: @autoclosure () throws -> Int = try compute()) {
				        self.child = child
				    }

				    @Instantiated let child: Child
				}
				""",
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
			        capacity: (() -> Int)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            capacity: capacity,
			            safeDIBuilder: nil
			        )
			    }

			    init(
			        capacity: (() -> Int)? = nil,
			        _ safeDIBuilder: ((Int) -> Child)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            capacity: capacity,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// `nil` keeps the default of `Child`’s `capacity`.
			    public var capacity: (() -> Int)? { __safeDI_storage.capacity }
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    var safeDIBuilder: ((Int) -> Child)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            capacity: (() -> Int)?,
			            safeDIBuilder: ((Int) -> Child)?
			        ) {
			            self.capacity = capacity
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let capacity: (() -> Int)?
			        let safeDIBuilder: ((Int) -> Child)?
			    }
			}

			extension Child {
			    static func __safeDI_init(capacity: (() -> Int)?, safeDIBuilder: ((Int) -> Child)?) -> Child {
			        let capacity = capacity ?? ({ 10 })
			        return if let safeDIBuilder { safeDIBuilder(capacity()) } else { Child(capacity: capacity()) }
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
			        retries: (() -> Int)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        Service.__safeDI_mock(retries: retries, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        retries: (() -> Int)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let retries = retries ?? ({ 3 })
			        func __safeDI_child() -> Child {
			            return Child.__safeDI_init(capacity: safeDIOverrides.child.capacity, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)
			        }
			        let child: Child = __safeDI_child()
			        return Service(child: child, retries: retries())
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_88F7917B74D30085 {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesSendableClosureForAutoclosureDefault_whenPublicMockTypeTakesSendableAutoclosure() async throws {
		// A public mock takes a `@Sendable` autoclosure default as an optional `@Sendable` closure, which the `@Sendable` autoclosure the construction is passed can capture.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable, Sendable {
				    public init(tag: @autoclosure @escaping @Sendable () -> String = "tag") {
				        self.tag = tag
				    }

				    let tag: @Sendable () -> String
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": generatedFileHeader,
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    public static func mock(
			        tag: (@Sendable () -> String)? = nil
			    ) -> Screen {
			        Screen.__safeDI_mock(tag: tag)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        tag: (@Sendable () -> String)? = nil
			    ) -> Screen {
			        let tag = tag ?? ({ "tag" })
			        return Screen(tag: tag())
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_CE97C8015E0A28F8 {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsSendableAutoclosureDefaultBeforeConstruction_whenTypeIsBuiltInAnotherMocksTree() async throws {
		// A configuration stores a `@Sendable` autoclosure default as a `@Sendable` closure, and the builder function reads its configuration into locals before it, as a `@Sendable` builder function does, so the `@Sendable` autoclosure the construction is passed captures that closure and not the overrides.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Screen: Instantiable, Sendable {
				    public init(tag: @autoclosure @escaping @Sendable () -> String = "tag") {
				        self.tag = tag
				    }

				    let tag: @Sendable () -> String
				}

				@Instantiable(generateMock: true)
				public final class Host: Instantiable {
				    public init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated let screen: Screen
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            tag: @autoclosure @escaping @Sendable () -> String = "tag",
			            _ safeDIBuilder: ((String) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                tag: tag,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var tag: @Sendable () -> String { __safeDI_storage.tag }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((String) -> Screen)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                tag: @escaping @Sendable () -> String,
			                safeDIBuilder: ((String) -> Screen)?
			            ) {
			                self.tag = tag
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let tag: @Sendable () -> String
			            let safeDIBuilder: ((String) -> Screen)?
			        }
			    }
			}
			#endif

			""",
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Host {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            screen: Screen.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                screen: screen
			            )
			        }

			        var screen: Screen.SafeDIMockConfiguration { __safeDI_storage.screen }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                screen: Screen.SafeDIMockConfiguration
			            ) {
			                self.screen = screen
			            }

			            let screen: Screen.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Host {
			        let __safeDI_screen__safeDIBuilder = safeDIOverrides.screen.safeDIBuilder
			        let __safeDI_screen__screen_tag = safeDIOverrides.screen.tag
			        func __safeDI_screen() -> Screen {
			            return if let safeDIBuilder = __safeDI_screen__safeDIBuilder { safeDIBuilder(__safeDI_screen__screen_tag()) } else { Screen(tag: __safeDI_screen__screen_tag()) }
			        }
			        let screen: Screen = __safeDI_screen()
			        return Host(screen: screen)
			    }
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func publicMock_readsSendableAutoclosureDefaultBeforeConstruction_whenTypeIsBuiltInPublicMocksTree() async throws {
		// A public configuration and the construction function take a `@Sendable` autoclosure default as an optional `@Sendable` closure, which the `@Sendable` autoclosure the construction is passed can capture.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Screen: Instantiable, Sendable {
				    public init(tag: @autoclosure @escaping @Sendable () -> String = "tag") {
				        self.tag = tag
				    }

				    let tag: @Sendable () -> String
				}

				@Instantiable(generateMock: .public)
				public final class Host: Instantiable {
				    public init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated let screen: Screen
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Screen` is constructed within the public mock trees of this module.
			nonisolated public struct __safeDI_Screen_MockConfiguration {
			    public init(
			        tag: (@Sendable () -> String)? = nil,
			        _ safeDIBuilder: ((String) -> Screen)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            tag: tag,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    /// `nil` keeps the default of `Screen`’s `tag`.
			    public var tag: (@Sendable () -> String)? { __safeDI_storage.tag }
			    /// Overrides how `Screen` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((String) -> Screen)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            tag: (@Sendable () -> String)?,
			            safeDIBuilder: ((String) -> Screen)?
			        ) {
			            self.tag = tag
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let tag: (@Sendable () -> String)?
			        let safeDIBuilder: ((String) -> Screen)?
			    }
			}

			extension Screen {
			    static func __safeDI_init(tag: (@Sendable () -> String)?, safeDIBuilder: ((String) -> Screen)?) -> Screen {
			        let tag = tag ?? ({ "tag" })
			        return if let safeDIBuilder { safeDIBuilder(tag()) } else { Screen(tag: tag()) }
			    }
			}
			#endif

			""",
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Host {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            screen: __safeDI_Screen_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                screen: screen
			            )
			        }

			        public var screen: __safeDI_Screen_MockConfiguration { __safeDI_storage.screen }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                screen: __safeDI_Screen_MockConfiguration
			            ) {
			                self.screen = screen
			            }

			            let screen: __safeDI_Screen_MockConfiguration
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Host {
			        Host.__safeDI_mock(safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Host {
			        func __safeDI_screen() -> Screen {
			            return Screen.__safeDI_init(tag: safeDIOverrides.screen.tag, safeDIBuilder: safeDIOverrides.screen.safeDIBuilder)
			        }
			        let screen: Screen = __safeDI_screen()
			        return Host(screen: screen)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
