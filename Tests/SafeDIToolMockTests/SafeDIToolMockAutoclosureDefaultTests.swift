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
			            self.dependency = dependency
			        }

			        private(set) var dependency: (() -> Dependency)?
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
			            self.serviceBuilder = serviceBuilder
			        }

			        private(set) var serviceBuilder: Service.SafeDIMockConfiguration
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
			            self.retries = retries
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var retries: () -> Int
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((Int) -> Service)?
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
			            self.service = service
			        }

			        private(set) var service: Service.SafeDIMockConfiguration
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
			            self.retries = retries
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var retries: () -> Int
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((Int) -> Service)?
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
			            self.serviceBuilder = serviceBuilder
			        }

			        private(set) var serviceBuilder: Service.SafeDIMockConfiguration
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
			            self.attempts = attempts
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var attempts: () -> Int
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((Int, Int) -> Service)?
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
			        @Sendable func __safeDI_serviceBuilder() -> Service {
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
			            self.serviceBuilder = serviceBuilder
			        }

			        private(set) var serviceBuilder: Service.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_serviceBuilder__serviceBuilder_retries = safeDIOverrides.serviceBuilder.retries
			        let __safeDI_serviceBuilder__safeDIBuilder = safeDIOverrides.serviceBuilder.safeDIBuilder
			        @Sendable func __safeDI_serviceBuilder() -> Service {
			            if let safeDIBuilder = __safeDI_serviceBuilder__safeDIBuilder { safeDIBuilder(__safeDI_serviceBuilder__serviceBuilder_retries()) } else { Service(retries: __safeDI_serviceBuilder__serviceBuilder_retries()) }
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
			    struct SafeDIMockConfiguration {
			        init(
			            retries: @autoclosure @escaping @Sendable () -> Int = 3,
			            _ safeDIBuilder: (@Sendable (Int) -> Service)? = nil
			        ) {
			            self.retries = retries
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var retries: @Sendable () -> Int
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: (@Sendable (Int) -> Service)?
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
			            self.service = service
			        }

			        private(set) var service: Service.SafeDIMockConfiguration
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
			            self.retries = retries
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var retries: () -> Int
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((Int) -> Service)?
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
			            self.service = service
			        }

			        private(set) var service: (() -> Service)?
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
			        self.capacity = capacity
			        self.safeDIBuilder = nil
			    }

			    init(
			        capacity: (() -> Int)? = nil,
			        _ safeDIBuilder: ((Int) -> Child)? = nil
			    ) {
			        self.capacity = capacity
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Child`'s `capacity`.
			    public private(set) var capacity: (() -> Int)?
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    private(set) var safeDIBuilder: ((Int) -> Child)?
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
			            self.child = child
			        }

			        public private(set) var child: __safeDI_Child_MockConfiguration
			    }

			    public static func mock(
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
			            self.serviceBuilder = serviceBuilder
			        }

			        private(set) var serviceBuilder: Service.SafeDIMockConfiguration
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
			            self.limit = limit
			            self.onFinish = onFinish
			            self.formatter = formatter
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var limit: () -> Int?
			        private(set) var onFinish: () -> () -> Void
			        private(set) var formatter: () -> any Formatter
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((Int?, @escaping () -> Void, any Formatter) -> Service)?
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
			        self.limit = limit
			        self.safeDIBuilder = nil
			    }

			    init(
			        limit: @autoclosure @escaping @Sendable () -> (() -> Int?)? = nil,
			        _ safeDIBuilder: (@Sendable (Int?) -> Child)? = nil
			    ) {
			        self.limit = limit
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Child`'s `limit`.
			    public private(set) var limit: @Sendable () -> (() -> Int?)?
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    private(set) var safeDIBuilder: (@Sendable (Int?) -> Child)?
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
			            self.childBuilder = childBuilder
			        }

			        public private(set) var childBuilder: __safeDI_Child_MockConfiguration
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let __safeDI_childBuilder__childBuilder_limit = safeDIOverrides.childBuilder.limit
			        let __safeDI_childBuilder__safeDIBuilder = safeDIOverrides.childBuilder.safeDIBuilder
			        @Sendable func __safeDI_childBuilder() -> Child {
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
		let coreImports = """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		"""
		let serviceMock = """
		#if DEBUG
		extension Service {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init() {
		            self.session = nil
		        }

		        package init(
		            session: (() -> Session)? = nil
		        ) {
		            self.session = session
		        }

		        package private(set) var session: (() -> Session)?
		    }

		    public static func mock(
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
		"""
		let appImports = """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		"""
		let pluginComment = integration.seamCallComment(type: "Service", declaringModule: "Core")
		let screenMock = """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.service = service
		        }

		        private(set) var service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Service.__safeDI_Service_mock_88F7917B74D30085.self\(pluginComment)
		        let service = Service.mock(safeDIOverrides: safeDIOverrides.service)
		        return Screen(service: service)
		    }
		}
		#endif
		"""
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + coreImports + "\n\n" + serviceMock])
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + appImports + "\n\n" + screenMock])
		case .swiftPackagePlugin:
			#expect(output.modules["Core"]?.generatedFiles == [
				"SafeDIMockConfiguration.swift": generatedFileHeader + coreImports + "\n\n",
				"Service+SafeDIMock.swift": generatedFileHeader + coreImports + "\n\n" + serviceMock,
			])
			#expect(output.modules["App"]?.generatedFiles == [
				"SafeDIMockConfiguration.swift": generatedFileHeader + appImports + "\n\n",
				"Screen+SafeDIMock.swift": generatedFileHeader + appImports + "\n\n" + screenMock,
			])
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

	// MARK: Private

	private var filesToDelete: [URL]
}
