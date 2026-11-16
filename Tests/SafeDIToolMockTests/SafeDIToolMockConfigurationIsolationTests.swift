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

/// A configuration of a type that every mock builds on one global actor – the actor the type's initializer,
/// `instantiate(…)` or hand-written mock spells, or else its declaration – stores each default the type's declaration
/// spells as a closure of that actor, which its nonisolated initializer takes as an autoclosure, and the mock calls it
/// where it builds the type. So a default that reads the actor's state compiles, and a caller still passes a value.
struct SafeDIToolMockConfigurationIsolationTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Internal mocks

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_configurationEvaluatesDefaultOnMainActor_whenTypeInTreeHasMainActorInitializer() async throws {
		// 2.2.0 repeated `Defaults.name` in the configuration's nonisolated initializer, which does not compile.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				public enum Defaults {
				    public static var name: String? = "name"
				}

				@Instantiable
				public final class Service: Instantiable {
				    @MainActor public init(name: String? = Defaults.name) {}
				}
				""",
				"""
				@Instantiable(mockAttributes: "@MainActor", generateMock: true)
				public final class Parent: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Parent+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Parent {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: Service.SafeDIMockConfiguration = .init()
			        ) {
			            self.service = service
			        }

			        let service: Service.SafeDIMockConfiguration
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Parent {
			        func __safeDI_service() -> Service {
			            return if let safeDIBuilder = safeDIOverrides.service.safeDIBuilder { safeDIBuilder(safeDIOverrides.service.name()) } else { Service(name: safeDIOverrides.service.name()) }
			        }
			        let service: Service = __safeDI_service()
			        return Parent(service: service)
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
			            name: @autoclosure @escaping @MainActor () -> String? = Defaults.name,
			            _ safeDIBuilder: ((String?) -> Service)? = nil
			        ) {
			            self.name = name
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let name: @MainActor () -> String?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((String?) -> Service)?
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_configurationEvaluatesDefaultOnMainActor_whenTypeInTreeHasMainActorHandWrittenMock() async throws {
		// The mock returns the type itself, so every mock builds `Service` with it, on the main actor, whatever its
		// nonisolated initializer spells.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				public enum Defaults {
				    public static var name: String? = "name"
				}

				@Instantiable
				public final class Service: Instantiable {
				    public init() {}

				    @MainActor public static func mock(name: String? = Defaults.name) -> Service {
				        Service()
				    }
				}
				""",
				"""
				@Instantiable(mockAttributes: "@MainActor", generateMock: true)
				public final class Parent: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Parent+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Parent {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: Service.SafeDIMockConfiguration = .init()
			        ) {
			            self.service = service
			        }

			        let service: Service.SafeDIMockConfiguration
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Parent {
			        func __safeDI_service() -> Service {
			            return if let safeDIBuilder = safeDIOverrides.service.safeDIBuilder { safeDIBuilder(safeDIOverrides.service.name()) } else { Service.mock(name: safeDIOverrides.service.name()) }
			        }
			        let service: Service = __safeDI_service()
			        return Parent(service: service)
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
			            name: @autoclosure @escaping @MainActor () -> String? = Defaults.name,
			            _ safeDIBuilder: ((String?) -> Service)? = nil
			        ) {
			            self.name = name
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let name: @MainActor () -> String?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((String?) -> Service)?
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_configurationEvaluatesDefaultOnMainActor_whenExtensionsInstantiateInTreeIsMainActor() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				public enum Defaults {
				    public static var zone: String? = "UTC"
				}

				public struct Clock {
				    let zone: String?
				}

				@Instantiable
				extension Clock: Instantiable {
				    @MainActor public static func instantiate(zone: String? = Defaults.zone) -> Clock {
				        Clock(zone: zone)
				    }
				}
				""",
				"""
				@Instantiable(mockAttributes: "@MainActor", generateMock: true)
				public final class Parent: Instantiable {
				    public init(clock: Clock) {
				        self.clock = clock
				    }

				    @Instantiated let clock: Clock
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Parent+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Parent {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            clock: Clock.SafeDIMockConfiguration = .init()
			        ) {
			            self.clock = clock
			        }

			        let clock: Clock.SafeDIMockConfiguration
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Parent {
			        func __safeDI_clock() -> Clock {
			            return if let safeDIBuilder = safeDIOverrides.clock.safeDIBuilder { safeDIBuilder(safeDIOverrides.clock.zone()) } else { Clock.instantiate(zone: safeDIOverrides.clock.zone()) }
			        }
			        let clock: Clock = __safeDI_clock()
			        return Parent(clock: clock)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Clock {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            zone: @autoclosure @escaping @MainActor () -> String? = Defaults.zone,
			            _ safeDIBuilder: ((String?) -> Clock)? = nil
			        ) {
			            self.zone = zone
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let zone: @MainActor () -> String?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((String?) -> Clock)?
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_configurationEvaluatesEveryKindOfDefaultOnMainActor_whenTypeInTreeHasMainActorInitializer() async throws {
		// A value, a closure, an `@autoclosure` value and a `nil` default each become a closure of the actor, so that a
		// closure literal that reads the actor's state is formed on the actor too.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				public enum Defaults {
				    public static var count = 1
				    public static func log() {}
				}

				@Instantiable
				public final class Service: Instantiable {
				    @MainActor public init(
				        count: Int = Defaults.count,
				        onTap: @escaping () -> Void = { Defaults.log() },
				        retries: @autoclosure () -> Int = Defaults.count,
				        note: String? = nil
				    ) {}
				}
				""",
				"""
				@Instantiable(mockAttributes: "@MainActor", generateMock: true)
				public final class Parent: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
			],
			swiftFileContentByFilePath: [
				"MockCallSite.swift": """
				#if DEBUG
				@MainActor func mockParent() -> Parent {
				    Parent.mock(safeDIOverrides: .init(service: .init(count: 2, onTap: {}, retries: 3, note: "note")))
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Parent+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Parent {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: Service.SafeDIMockConfiguration = .init()
			        ) {
			            self.service = service
			        }

			        let service: Service.SafeDIMockConfiguration
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Parent {
			        func __safeDI_service() -> Service {
			            return if let safeDIBuilder = safeDIOverrides.service.safeDIBuilder { safeDIBuilder(safeDIOverrides.service.count(), safeDIOverrides.service.onTap(), safeDIOverrides.service.retries(), safeDIOverrides.service.note()) } else { Service(count: safeDIOverrides.service.count(), onTap: safeDIOverrides.service.onTap(), retries: safeDIOverrides.service.retries(), note: safeDIOverrides.service.note()) }
			        }
			        let service: Service = __safeDI_service()
			        return Parent(service: service)
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
			            count: @autoclosure @escaping @MainActor () -> Int = Defaults.count,
			            onTap: @autoclosure @escaping @MainActor () -> () -> Void = ({ Defaults.log() }),
			            retries: @autoclosure @escaping @MainActor () -> Int = Defaults.count,
			            note: @autoclosure @escaping @MainActor () -> String? = nil,
			            _ safeDIBuilder: ((Int, @escaping () -> Void, Int, String?) -> Service)? = nil
			        ) {
			            self.count = count
			            self.onTap = onTap
			            self.retries = retries
			            self.note = note
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let count: @MainActor () -> Int
			        let onTap: @MainActor () -> () -> Void
			        let retries: @MainActor () -> Int
			        let note: @MainActor () -> String?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((Int, @escaping () -> Void, Int, String?) -> Service)?
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_configurationEvaluatesDefaultOnMainActor_whenTypeInTreeAndMockedTypeAreDeclaredOnMainActor() async throws {
		// `Parent`'s mock is on the main actor through its type's declaration rather than `mockAttributes`, and
		// `Service`'s initializer through its type's.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				public enum Defaults {
				    public static var name: String? = "name"
				}

				@Instantiable
				@MainActor
				public final class Service: Instantiable {
				    public init(name: String? = Defaults.name) {}
				}
				""",
				"""
				@Instantiable(generateMock: true)
				@MainActor
				public final class Parent: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Parent+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Parent {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: Service.SafeDIMockConfiguration = .init()
			        ) {
			            self.service = service
			        }

			        let service: Service.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Parent {
			        func __safeDI_service() -> Service {
			            return if let safeDIBuilder = safeDIOverrides.service.safeDIBuilder { safeDIBuilder(safeDIOverrides.service.name()) } else { Service(name: safeDIOverrides.service.name()) }
			        }
			        let service: Service = __safeDI_service()
			        return Parent(service: service)
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
			            name: @autoclosure @escaping @MainActor () -> String? = Defaults.name,
			            _ safeDIBuilder: ((String?) -> Service)? = nil
			        ) {
			            self.name = name
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let name: @MainActor () -> String?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((String?) -> Service)?
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_nestedConfigurationEvaluatesDefaultOnMainActor_whenTypeTwoLevelsDownHasMainActorInitializer() async throws {
		// `Child`'s configuration is a field of `Service`'s, which is nonisolated, as is its own default.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				public enum Defaults {
				    public static var name: String? = "name"
				}

				@Instantiable
				public final class Child: Instantiable {
				    @MainActor public init(name: String? = Defaults.name) {}
				}
				""",
				"""
				@Instantiable(mockAttributes: "@MainActor", generateMock: true)
				public final class Parent: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable {
				    public init(child: Child, retries: Int = 3) {
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
			"Parent+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Parent {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: Service.SafeDIMockConfiguration = .init()
			        ) {
			            self.service = service
			        }

			        let service: Service.SafeDIMockConfiguration
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Parent {
			        func __safeDI_service() -> Service {
			            func __safeDI_child() -> Child {
			                return if let safeDIBuilder = safeDIOverrides.service.child.safeDIBuilder { safeDIBuilder(safeDIOverrides.service.child.name()) } else { Child(name: safeDIOverrides.service.child.name()) }
			            }
			            let child: Child = __safeDI_child()
			            return if let safeDIBuilder = safeDIOverrides.service.safeDIBuilder { safeDIBuilder(child, safeDIOverrides.service.retries) } else { Service(child: child, retries: safeDIOverrides.service.retries) }
			        }
			        let service: Service = __safeDI_service()
			        return Parent(service: service)
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
			            name: @autoclosure @escaping @MainActor () -> String? = Defaults.name,
			            _ safeDIBuilder: ((String?) -> Child)? = nil
			        ) {
			            self.name = name
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let name: @MainActor () -> String?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((String?) -> Child)?
			    }
			}

			extension Service {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            child: Child.SafeDIMockConfiguration = .init(),
			            retries: Int = 3,
			            _ safeDIBuilder: ((Child, Int) -> Service)? = nil
			        ) {
			            self.child = child
			            self.retries = retries
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let child: Child.SafeDIMockConfiguration
			        let retries: Int
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((Child, Int) -> Service)?
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_configurationEvaluatesDefaultOnMainActor_whenInstantiatorBuildsTypeWithMainActorInitializer() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				public enum Defaults {
				    public static var name: String? = "name"
				}

				@Instantiable
				public final class Service: Instantiable {
				    @MainActor public init(name: String? = Defaults.name) {}
				}
				""",
				"""
				@Instantiable(mockAttributes: "@MainActor", generateMock: true)
				public final class Parent: Instantiable {
				    public init(serviceBuilder: Instantiator<Service>) {
				        self.serviceBuilder = serviceBuilder
				    }

				    @Instantiated let serviceBuilder: Instantiator<Service>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Parent+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Parent {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            serviceBuilder: Service.SafeDIMockConfiguration = .init()
			        ) {
			            self.serviceBuilder = serviceBuilder
			        }

			        let serviceBuilder: Service.SafeDIMockConfiguration
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Parent {
			        func __safeDI_serviceBuilder() -> Service {
			            if let safeDIBuilder = safeDIOverrides.serviceBuilder.safeDIBuilder { safeDIBuilder(safeDIOverrides.serviceBuilder.name()) } else { Service(name: safeDIOverrides.serviceBuilder.name()) }
			        }
			        let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
			        return Parent(serviceBuilder: serviceBuilder)
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
			            name: @autoclosure @escaping @MainActor () -> String? = Defaults.name,
			            _ safeDIBuilder: ((String?) -> Service)? = nil
			        ) {
			            self.name = name
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let name: @MainActor () -> String?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((String?) -> Service)?
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_configurationStoresDefaultValue_whenTypeInTreeHasNonisolatedInitializerReadingNonisolatedState() async throws {
		// The control: `Service` is on the main actor, but its `nonisolated` initializer, whose default reads nonisolated
		// state, can be called anywhere, so its configuration keeps the value.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public enum Defaults {
				    public static let name: String? = "name"
				}

				@Instantiable
				@MainActor
				public final class Service: Instantiable {
				    nonisolated public init(name: String? = Defaults.name) {}
				}
				""",
				"""
				@Instantiable(mockAttributes: "@MainActor", generateMock: true)
				public final class Parent: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Parent+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Parent {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: Service.SafeDIMockConfiguration = .init()
			        ) {
			            self.service = service
			        }

			        let service: Service.SafeDIMockConfiguration
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Parent {
			        func __safeDI_service() -> Service {
			            return if let safeDIBuilder = safeDIOverrides.service.safeDIBuilder { safeDIBuilder(safeDIOverrides.service.name) } else { Service(name: safeDIOverrides.service.name) }
			        }
			        let service: Service = __safeDI_service()
			        return Parent(service: service)
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
			            name: String? = Defaults.name,
			            _ safeDIBuilder: ((String?) -> Service)? = nil
			        ) {
			            self.name = name
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let name: String?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((String?) -> Service)?
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_configurationStoresDefaultValue_whenTypeIsBuiltWithMainActorHandWrittenMockAndNonisolatedInitializer() async throws {
		// `Service`'s mock returns `ServiceProtocol`, so `Feed`'s mock builds its `ServiceProtocol` with the `@MainActor`
		// mock and `Inbox`'s nonisolated mock builds its `Service` with the nonisolated initializer, from one
		// configuration, which keeps the value, so that `Inbox`'s mock can read it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol ServiceProtocol {}

				@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
				public final class Service: Instantiable, ServiceProtocol {
				    public init(name: String? = nil) {}
				}

				@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true, customMockName: "customMock")
				extension Service {
				    @MainActor public static func customMock(name: String? = nil) -> ServiceProtocol {
				        Service(name: name)
				    }
				}
				""",
				"""
				@Instantiable(mockAttributes: "@MainActor", generateMock: true)
				public final class Feed: Instantiable {
				    public init(service: ServiceProtocol) {
				        self.service = service
				    }

				    @Instantiated let service: ServiceProtocol
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Inbox: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Feed+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Feed {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: Service.SafeDIMockConfiguration = .init()
			        ) {
			            self.service = service
			        }

			        let service: Service.SafeDIMockConfiguration
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Feed {
			        func __safeDI_service() -> ServiceProtocol {
			            return if let safeDIBuilder = safeDIOverrides.service.safeDIBuilder { safeDIBuilder(safeDIOverrides.service.name) } else { Service.customMock(name: safeDIOverrides.service.name) }
			        }
			        let service: ServiceProtocol = __safeDI_service()
			        return Feed(service: service)
			    }
			}
			#endif
			""",
			"Inbox+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Inbox {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: Service.SafeDIMockConfiguration = .init()
			        ) {
			            self.service = service
			        }

			        let service: Service.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Inbox {
			        func __safeDI_service() -> Service {
			            return if let safeDIBuilder = safeDIOverrides.service.safeDIBuilder { safeDIBuilder(safeDIOverrides.service.name) } else { Service(name: safeDIOverrides.service.name) }
			        }
			        let service: Service = __safeDI_service()
			        return Inbox(service: service)
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
			            name: String? = nil,
			            _ safeDIBuilder: ((String?) -> Service)? = nil
			        ) {
			            self.name = name
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let name: String?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((String?) -> Service)?
			    }
			}
			#endif

			""",
		])
	}

	// MARK: Tests – Public mocks

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_publicConfigurationEvaluatesDefaultsOnMainActor_whenTypeInPublicMocksTreeHasMainActorInitializer() async throws {
		// The optional default's provider is on the main actor, and the configuration's nonisolated initializer takes each
		// default as an autoclosure of the actor, which the mock calls. A nonisolated caller still passes a value.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				public enum Defaults {
				    public static var name: String? = "name"
				    public static var count = 1
				}

				@Instantiable
				public final class Service: Instantiable {
				    @MainActor public init(name: String? = Defaults.name, count: Int = Defaults.count) {}
				}
				""",
				"""
				@Instantiable(mockAttributes: "@MainActor", generateMock: .public)
				public final class Parent: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
			],
			swiftFileContentByFilePath: [
				"MockCallSite.swift": """
				#if DEBUG
				@MainActor func mockParent() -> Parent {
				    Parent.mock(safeDIOverrides: .init(service: .init(name: nil, count: 2)))
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Parent+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Parent {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            service: __safeDI_Service_MockConfiguration = .init()
			        ) {
			            self.service = service
			        }

			        public let service: __safeDI_Service_MockConfiguration
			    }

			    @MainActor public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Parent {
			        func __safeDI_service() -> Service {
			            return Service.__safeDI_init(name: safeDIOverrides.service.name(), count: safeDIOverrides.service.count(), safeDIBuilder: safeDIOverrides.service.safeDIBuilder)
			        }
			        let service: Service = __safeDI_service()
			        return Parent(service: service)
			    }
			}

			extension Parent {
			    public enum __safeDI_Parent_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Service` is constructed within the public mock trees of this module.
			nonisolated public struct __safeDI_Service_MockConfiguration {
			    public init(
			        name: @autoclosure @escaping @MainActor () -> String? = __safeDI_Service_mockDefault_name(),
			        count: @autoclosure @escaping @MainActor () -> Int? = nil,
			        _ safeDIBuilder: ((String?, Int) -> Service)? = nil
			    ) {
			        self.name = name
			        self.count = count
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// The default of `Service`’s `name` unless set.
			    public let name: @MainActor () -> String?
			    /// `nil` keeps the default of `Service`’s `count`.
			    public let count: @MainActor () -> Int?
			    /// Overrides how `Service` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((String?, Int) -> Service)?
			}

			extension Service {
			    @MainActor static func __safeDI_mockDefault_name() -> String? { Defaults.name }
			    @MainActor static func __safeDI_init(name: String?, count: Int?, safeDIBuilder: ((String?, Int) -> Service)?) -> Service {
			        let count = count ?? (Defaults.count)
			        return if let safeDIBuilder { safeDIBuilder(name, count) } else { Service(name: name, count: count) }
			    }
			}
			@usableFromInline @MainActor func __safeDI_Service_mockDefault_name() -> String? { Service.__safeDI_mockDefault_name() }
			#endif

			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_publicMockWhoseTreeHasMainActorInitializerCompilesForCallerInAnotherModule(integration: MultiModuleIntegration) async throws {
		// `Service`'s initializer is internal, so `Screen`'s mock in another module cannot build `Parent` inline and calls
		// `Parent`'s public mock, whose `SafeDIOverrides` holds `Service`'s configuration: its nonisolated initializer
		// evaluates no default, which `Parent`'s mock evaluates on the main actor.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Core",
					packageName: "core",
					swiftFileContentByFilePath: ["Parent.swift": """
					@MainActor
					public enum Defaults {
					    public static var name: String? = "name"
					}

					@Instantiable(mockAttributes: "@MainActor", generateMock: .public)
					public final class Parent: Instantiable {
					    public init(service: Service) {
					        self.service = service
					    }

					    @Instantiated let service: Service
					}

					@Instantiable
					public final class Service: Instantiable {
					    @MainActor init(name: String? = Defaults.name) {}
					}
					"""],
				),
				ModuleFixture(
					name: "App",
					packageName: "app",
					swiftFileContentByFilePath: ["Screen.swift": """
					import Core

					@Instantiable(mockAttributes: "@MainActor", generateMock: true)
					public final class Screen: Instantiable {
					    public init(parent: Parent) {
					        self.parent = parent
					    }

					    @Instantiated let parent: Parent
					}
					"""],
					dependencies: ["Core"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["Core"]?.generatedFiles == Self.parentFiles(integration: integration))
		#expect(output.modules["App"]?.generatedFiles == Self.screenFiles(integration: integration))
	}

	// MARK: Private

	/// What `Core` generates: `Parent`'s public mock, and the configuration of `Service`, whose initializer is on the main
	/// actor.
	private static func parentFiles(integration: MultiModuleIntegration) -> [String: String] {
		switch integration {
		case .moduleInfo:
			[
				"Core.swift": generatedFileHeader + """
				#if DEBUG
				extension Parent {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            service: __safeDI_Core_Service_MockConfiguration = .init()
				        ) {
				            self.service = service
				        }

				        public let service: __safeDI_Core_Service_MockConfiguration
				    }

				    @MainActor public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Parent {
				        func __safeDI_service() -> Service {
				            return Service.__safeDI_init(name: safeDIOverrides.service.name(), safeDIBuilder: safeDIOverrides.service.safeDIBuilder)
				        }
				        let service: Service = __safeDI_service()
				        return Parent(service: service)
				    }
				}

				extension Parent {
				    public enum __safeDI_Parent_mock_51799E6AA5E7B634 {}
				}
				#endif

				#if DEBUG
				/// Configuration for how `Service` is constructed within the public mock trees of module `Core`.
				nonisolated public struct __safeDI_Core_Service_MockConfiguration {
				    public init(
				        name: @autoclosure @escaping @MainActor () -> String? = __safeDI_Core_Service_mockDefault_name(),
				        _ safeDIBuilder: ((String?) -> Service)? = nil
				    ) {
				        self.name = name
				        self.safeDIBuilder = safeDIBuilder
				    }

				    /// The default of `Service`’s `name` unless set.
				    public let name: @MainActor () -> String?
				    /// Overrides how `Service` is constructed. Parameters match the type’s initializer or custom mock method.
				    public let safeDIBuilder: ((String?) -> Service)?
				}

				extension Service {
				    @MainActor static func __safeDI_mockDefault_name() -> String? { Defaults.name }
				    @MainActor static func __safeDI_init(name: String?, safeDIBuilder: ((String?) -> Service)?) -> Service {
				        if let safeDIBuilder { safeDIBuilder(name) } else { Service(name: name) }
				    }
				}
				@usableFromInline @MainActor func __safeDI_Core_Service_mockDefault_name() -> String? { Service.__safeDI_mockDefault_name() }
				#endif

				""",
			]
		case .swiftPackagePlugin:
			[
				"Parent+SafeDIMock.swift": generatedFileHeader + """
				#if DEBUG
				extension Parent {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            service: __safeDI_Core_Service_MockConfiguration = .init()
				        ) {
				            self.service = service
				        }

				        public let service: __safeDI_Core_Service_MockConfiguration
				    }

				    @MainActor public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Parent {
				        func __safeDI_service() -> Service {
				            return Service.__safeDI_init(name: safeDIOverrides.service.name(), safeDIBuilder: safeDIOverrides.service.safeDIBuilder)
				        }
				        let service: Service = __safeDI_service()
				        return Parent(service: service)
				    }
				}

				extension Parent {
				    public enum __safeDI_Parent_mock_51799E6AA5E7B634 {}
				}
				#endif
				""",
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if DEBUG
				/// Configuration for how `Service` is constructed within the public mock trees of module `Core`.
				nonisolated public struct __safeDI_Core_Service_MockConfiguration {
				    public init(
				        name: @autoclosure @escaping @MainActor () -> String? = __safeDI_Core_Service_mockDefault_name(),
				        _ safeDIBuilder: ((String?) -> Service)? = nil
				    ) {
				        self.name = name
				        self.safeDIBuilder = safeDIBuilder
				    }

				    /// The default of `Service`’s `name` unless set.
				    public let name: @MainActor () -> String?
				    /// Overrides how `Service` is constructed. Parameters match the type’s initializer or custom mock method.
				    public let safeDIBuilder: ((String?) -> Service)?
				}

				extension Service {
				    @MainActor static func __safeDI_mockDefault_name() -> String? { Defaults.name }
				    @MainActor static func __safeDI_init(name: String?, safeDIBuilder: ((String?) -> Service)?) -> Service {
				        if let safeDIBuilder { safeDIBuilder(name) } else { Service(name: name) }
				    }
				}
				@usableFromInline @MainActor func __safeDI_Core_Service_mockDefault_name() -> String? { Service.__safeDI_mockDefault_name() }
				#endif

				""",
			]
		}
	}

	private static func screenFiles(integration: MultiModuleIntegration) -> [String: String] {
		switch integration {
		case .moduleInfo:
			[
				"App.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif

				#if DEBUG
				extension Screen {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            parent: Parent.SafeDIOverrides = .init()
				        ) {
				            self.parent = parent
				        }

				        let parent: Parent.SafeDIOverrides
				    }

				    @MainActor static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        _ = Parent.__safeDI_Parent_mock_51799E6AA5E7B634.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				        let parent = Parent.mock(safeDIOverrides: safeDIOverrides.parent)
				        return Screen(parent: parent)
				    }
				}
				#endif
				""",
			]
		case .swiftPackagePlugin:
			[
				"Screen+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif

				#if DEBUG
				extension Screen {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            parent: Parent.SafeDIOverrides = .init()
				        ) {
				            self.parent = parent
				        }

				        let parent: Parent.SafeDIOverrides
				    }

				    @MainActor static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        _ = Parent.__safeDI_Parent_mock_51799E6AA5E7B634.self // If this line does not compile, add the SafeDI plugin to the target that declares Parent.
				        let parent = Parent.mock(safeDIOverrides: safeDIOverrides.parent)
				        return Screen(parent: parent)
				    }
				}
				#endif
				""",
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif


				""",
			]
		}
	}

	private var filesToDelete: [URL]
}
