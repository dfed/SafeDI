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

/// A mock that builds one type at two or more places, with that type's tree holding one shape a builder function shared
/// between the places must keep compiling: inherited actor isolation, a typealiased closure received only as an
/// optional, default-valued parameters, hand-written mocks, a concrete type built plain and erased, a `Sendable`
/// builder, a `LazilyInstantiated` instance, and aliases. Each test compiles the fixture with the code generated from
/// it, so a mock that shares one builder function per type changes only the expected text here.
struct SafeDIToolMockSharedBuilderTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – isolation

	/// `RootScreen` and `ChildScreen` are on the main actor through their superclass, which SafeDI cannot see, and
	/// `Coordinator`, built at two places between them, is not. A builder function for `Coordinator` compiles only where it
	/// has `RootScreen`'s isolation, because it builds `ChildScreen`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compiles_whenSharedTypeBuildsTypeIsolatedThroughItsSuperclass() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				open class Screen {
				    public init() {}
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class RootScreen: Screen, Instantiable {
				    public init(first: Coordinator, second: Coordinator) {
				        self.first = first
				        self.second = second
				        super.init()
				    }

				    @Instantiated let first: Coordinator
				    @Instantiated let second: Coordinator
				}
				""",
				"""
				@Instantiable
				public final class Coordinator: Instantiable {
				    public init(child: ChildScreen) {
				        self.child = child
				    }

				    @Instantiated let child: ChildScreen
				}
				""",
				"""
				@Instantiable
				public final class ChildScreen: Screen, Instantiable {
				    public override init() {
				        super.init()
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"RootScreen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension RootScreen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            first: Coordinator.SafeDIMockConfiguration = .init(),
			            second: Coordinator.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first,
			                second: second
			            )
			        }

			        var first: Coordinator.SafeDIMockConfiguration { __safeDI_storage.first }
			        var second: Coordinator.SafeDIMockConfiguration { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: Coordinator.SafeDIMockConfiguration,
			                second: Coordinator.SafeDIMockConfiguration
			            ) {
			                self.first = first
			                self.second = second
			            }

			            let first: Coordinator.SafeDIMockConfiguration
			            let second: Coordinator.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> RootScreen {
			        func __safeDI_first() -> Coordinator {
			            let child = if let safeDIBuilder = safeDIOverrides.first.child { safeDIBuilder() } else { ChildScreen() }
			            return if let safeDIBuilder = safeDIOverrides.first.safeDIBuilder { safeDIBuilder(child) } else { Coordinator(child: child) }
			        }
			        let first: Coordinator = __safeDI_first()
			        func __safeDI_second() -> Coordinator {
			            let child = if let safeDIBuilder = safeDIOverrides.second.child { safeDIBuilder() } else { ChildScreen() }
			            return if let safeDIBuilder = safeDIOverrides.second.safeDIBuilder { safeDIBuilder(child) } else { Coordinator(child: child) }
			        }
			        let second: Coordinator = __safeDI_second()
			        return RootScreen(first: first, second: second)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Coordinator {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            child: (() -> ChildScreen)? = nil,
			            _ safeDIBuilder: ((ChildScreen) -> Coordinator)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                child: child,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var child: (() -> ChildScreen)? { __safeDI_storage.child }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((ChildScreen) -> Coordinator)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                child: (() -> ChildScreen)?,
			                safeDIBuilder: ((ChildScreen) -> Coordinator)?
			            ) {
			                self.child = child
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let child: (() -> ChildScreen)?
			            let safeDIBuilder: ((ChildScreen) -> Coordinator)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	/// `Service` is on the main actor with a `nonisolated` initializer, built at two places by `Holder`, which is not.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compiles_whenSharedTypeBuildsMainActorTypeWithNonisolatedInitializer() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(first: Holder, second: Holder) {
				        self.first = first
				        self.second = second
				    }

				    @Instantiated let first: Holder
				    @Instantiated let second: Holder
				}
				""",
				"""
				@Instantiable
				public final class Holder: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
				"""
				@MainActor
				@Instantiable
				public final class Service: Instantiable {
				    public nonisolated init() {}
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
			    struct SafeDIOverrides {
			        init(
			            first: Holder.SafeDIMockConfiguration = .init(),
			            second: Holder.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first,
			                second: second
			            )
			        }

			        var first: Holder.SafeDIMockConfiguration { __safeDI_storage.first }
			        var second: Holder.SafeDIMockConfiguration { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: Holder.SafeDIMockConfiguration,
			                second: Holder.SafeDIMockConfiguration
			            ) {
			                self.first = first
			                self.second = second
			            }

			            let first: Holder.SafeDIMockConfiguration
			            let second: Holder.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_first() -> Holder {
			            let service = if let safeDIBuilder = safeDIOverrides.first.service { safeDIBuilder() } else { Service() }
			            return if let safeDIBuilder = safeDIOverrides.first.safeDIBuilder { safeDIBuilder(service) } else { Holder(service: service) }
			        }
			        let first: Holder = __safeDI_first()
			        func __safeDI_second() -> Holder {
			            let service = if let safeDIBuilder = safeDIOverrides.second.service { safeDIBuilder() } else { Service() }
			            return if let safeDIBuilder = safeDIOverrides.second.safeDIBuilder { safeDIBuilder(service) } else { Holder(service: service) }
			        }
			        let second: Holder = __safeDI_second()
			        return Root(first: first, second: second)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Holder {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            service: (() -> Service)? = nil,
			            _ safeDIBuilder: ((Service) -> Holder)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var service: (() -> Service)? { __safeDI_storage.service }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Service) -> Holder)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: (() -> Service)?,
			                safeDIBuilder: ((Service) -> Holder)?
			            ) {
			                self.service = service
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let service: (() -> Service)?
			            let safeDIBuilder: ((Service) -> Holder)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	/// In a module that defaults to the main actor, `Root` says it is on the main actor, and the types it builds say
	/// nothing.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compiles_whenSharedTypeIsBuiltInModuleThatDefaultsToMainActor() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(first: Holder, second: Holder) {
				        self.first = first
				        self.second = second
				    }

				    @Instantiated let first: Holder
				    @Instantiated let second: Holder
				}
				""",
				"""
				@Instantiable
				public final class Holder: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable {
				    public init() {}
				}
				""",
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
			            first: Holder.SafeDIMockConfiguration = .init(),
			            second: Holder.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first,
			                second: second
			            )
			        }

			        var first: Holder.SafeDIMockConfiguration { __safeDI_storage.first }
			        var second: Holder.SafeDIMockConfiguration { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: Holder.SafeDIMockConfiguration,
			                second: Holder.SafeDIMockConfiguration
			            ) {
			                self.first = first
			                self.second = second
			            }

			            let first: Holder.SafeDIMockConfiguration
			            let second: Holder.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_first() -> Holder {
			            let service = if let safeDIBuilder = safeDIOverrides.first.service { safeDIBuilder() } else { Service() }
			            return if let safeDIBuilder = safeDIOverrides.first.safeDIBuilder { safeDIBuilder(service) } else { Holder(service: service) }
			        }
			        let first: Holder = __safeDI_first()
			        func __safeDI_second() -> Holder {
			            let service = if let safeDIBuilder = safeDIOverrides.second.service { safeDIBuilder() } else { Service() }
			            return if let safeDIBuilder = safeDIOverrides.second.safeDIBuilder { safeDIBuilder(service) } else { Holder(service: service) }
			        }
			        let second: Holder = __safeDI_second()
			        return Root(first: first, second: second)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Holder {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            service: (() -> Service)? = nil,
			            _ safeDIBuilder: ((Service) -> Holder)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var service: (() -> Service)? { __safeDI_storage.service }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Service) -> Holder)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: (() -> Service)?,
			                safeDIBuilder: ((Service) -> Holder)?
			            ) {
			                self.service = service
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let service: (() -> Service)?
			            let safeDIBuilder: ((Service) -> Holder)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	// MARK: Tests – escaping typealias

	/// `Row`, built at two places, reads the forwarded closure only through `Badge`'s receive of `OnTap?`, which
	/// declares nothing `@escaping`. A builder function that takes the closure must still declare it `@escaping`, from
	/// what `Screen`'s own initializer declares.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_declaresClosureEscaping_whenSharedTypeReceivesTypealiasedClosureOnlyIfAvailable() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public typealias OnTap = () -> Void
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(onTap: @escaping OnTap, first: Row, second: Row) {
				        self.onTap = onTap
				        self.first = first
				        self.second = second
				    }

				    @Forwarded let onTap: OnTap
				    @Instantiated let first: Row
				    @Instantiated let second: Row
				}
				""",
				"""
				@Instantiable
				public final class Row: Instantiable {
				    public init(badge: Badge) {
				        self.badge = badge
				    }

				    @Instantiated let badge: Badge
				}
				""",
				"""
				@Instantiable
				public final class Badge: Instantiable {
				    public init(onTap: OnTap?) {
				        self.onTap = onTap
				    }

				    @Received(onlyIfAvailable: true) let onTap: OnTap?
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Row {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            badge: ((OnTap?) -> Badge)? = nil,
			            _ safeDIBuilder: ((Badge) -> Row)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                badge: badge,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var badge: ((OnTap?) -> Badge)? { __safeDI_storage.badge }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Badge) -> Row)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                badge: ((OnTap?) -> Badge)?,
			                safeDIBuilder: ((Badge) -> Row)?
			            ) {
			                self.badge = badge
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let badge: ((OnTap?) -> Badge)?
			            let safeDIBuilder: ((Badge) -> Row)?
			        }
			    }
			}
			#endif

			""",
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            first: Row.SafeDIMockConfiguration = .init(),
			            second: Row.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first,
			                second: second
			            )
			        }

			        var first: Row.SafeDIMockConfiguration { __safeDI_storage.first }
			        var second: Row.SafeDIMockConfiguration { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: Row.SafeDIMockConfiguration,
			                second: Row.SafeDIMockConfiguration
			            ) {
			                self.first = first
			                self.second = second
			            }

			            let first: Row.SafeDIMockConfiguration
			            let second: Row.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        onTap: @escaping OnTap,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_first() -> Row {
			            let badge = if let safeDIBuilder = safeDIOverrides.first.badge { safeDIBuilder(onTap) } else { Badge(onTap: onTap) }
			            return if let safeDIBuilder = safeDIOverrides.first.safeDIBuilder { safeDIBuilder(badge) } else { Row(badge: badge) }
			        }
			        let first: Row = __safeDI_first()
			        func __safeDI_second() -> Row {
			            let badge = if let safeDIBuilder = safeDIOverrides.second.badge { safeDIBuilder(onTap) } else { Badge(onTap: onTap) }
			            return if let safeDIBuilder = safeDIOverrides.second.safeDIBuilder { safeDIBuilder(badge) } else { Row(badge: badge) }
			        }
			        let second: Row = __safeDI_second()
			        return Screen(onTap: onTap, first: first, second: second)
			    }
			}
			#endif
			""",
		])
	}

	// MARK: Tests – default-valued parameters

	/// `Row`, built at two places, takes a plain default and an `@autoclosure` default, which each place's
	/// configuration supplies.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsEachPlacesDefaults_whenSharedTypeHasDefaultValuedParameters() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(first: Row, second: Row) {
				        self.first = first
				        self.second = second
				    }

				    @Instantiated let first: Row
				    @Instantiated let second: Row
				}
				""",
				"""
				@Instantiable
				public final class Row: Instantiable {
				    public init(service: Service, title: String = "Row", count: @autoclosure () -> Int = 0) {
				        self.service = service
				        self.title = title
				        self.count = count()
				    }

				    @Instantiated let service: Service
				    let title: String
				    let count: Int
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable {
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
			    struct SafeDIOverrides {
			        init(
			            first: Row.SafeDIMockConfiguration = .init(),
			            second: Row.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first,
			                second: second
			            )
			        }

			        var first: Row.SafeDIMockConfiguration { __safeDI_storage.first }
			        var second: Row.SafeDIMockConfiguration { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: Row.SafeDIMockConfiguration,
			                second: Row.SafeDIMockConfiguration
			            ) {
			                self.first = first
			                self.second = second
			            }

			            let first: Row.SafeDIMockConfiguration
			            let second: Row.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_first() -> Row {
			            let service = if let safeDIBuilder = safeDIOverrides.first.service { safeDIBuilder() } else { Service() }
			            return if let safeDIBuilder = safeDIOverrides.first.safeDIBuilder { safeDIBuilder(service, safeDIOverrides.first.title, safeDIOverrides.first.count()) } else { Row(service: service, title: safeDIOverrides.first.title, count: safeDIOverrides.first.count()) }
			        }
			        let first: Row = __safeDI_first()
			        func __safeDI_second() -> Row {
			            let service = if let safeDIBuilder = safeDIOverrides.second.service { safeDIBuilder() } else { Service() }
			            return if let safeDIBuilder = safeDIOverrides.second.safeDIBuilder { safeDIBuilder(service, safeDIOverrides.second.title, safeDIOverrides.second.count()) } else { Row(service: service, title: safeDIOverrides.second.title, count: safeDIOverrides.second.count()) }
			        }
			        let second: Row = __safeDI_second()
			        return Root(first: first, second: second)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Row {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            service: (() -> Service)? = nil,
			            title: String = "Row",
			            count: @autoclosure @escaping () -> Int = 0,
			            _ safeDIBuilder: ((Service, String, Int) -> Row)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service,
			                title: title,
			                count: count,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var service: (() -> Service)? { __safeDI_storage.service }
			        var title: String { __safeDI_storage.title }
			        var count: () -> Int { __safeDI_storage.count }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Service, String, Int) -> Row)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: (() -> Service)?,
			                title: String,
			                count: @escaping () -> Int,
			                safeDIBuilder: ((Service, String, Int) -> Row)?
			            ) {
			                self.service = service
			                self.title = title
			                self.count = count
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let service: (() -> Service)?
			            let title: String
			            let count: () -> Int
			            let safeDIBuilder: ((Service, String, Int) -> Row)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	// MARK: Tests – hand-written mocks

	/// `Row`, built at two places, builds `Leaf`, whose hand-written mock the generated mock calls.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_callsHandWrittenMock_whenSharedTypeBuildsTypeWithHandWrittenMock() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(first: Row, second: Row) {
				        self.first = first
				        self.second = second
				    }

				    @Instantiated let first: Row
				    @Instantiated let second: Row
				}
				""",
				"""
				@Instantiable
				public final class Row: Instantiable {
				    public init(leaf: Leaf) {
				        self.leaf = leaf
				    }

				    @Instantiated let leaf: Leaf
				}
				""",
				"""
				@Instantiable
				public final class Leaf: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    public static func mock(service: Service) -> Leaf {
				        Leaf(service: service)
				    }

				    @Instantiated let service: Service
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable {
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
			    struct SafeDIOverrides {
			        init(
			            first: Row.SafeDIMockConfiguration = .init(),
			            second: Row.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first,
			                second: second
			            )
			        }

			        var first: Row.SafeDIMockConfiguration { __safeDI_storage.first }
			        var second: Row.SafeDIMockConfiguration { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: Row.SafeDIMockConfiguration,
			                second: Row.SafeDIMockConfiguration
			            ) {
			                self.first = first
			                self.second = second
			            }

			            let first: Row.SafeDIMockConfiguration
			            let second: Row.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_first() -> Row {
			            func __safeDI_leaf() -> Leaf {
			                let service = if let safeDIBuilder = safeDIOverrides.first.leaf.service { safeDIBuilder() } else { Service() }
			                return if let safeDIBuilder = safeDIOverrides.first.leaf.safeDIBuilder { safeDIBuilder(service) } else { Leaf.mock(service: service) }
			            }
			            let leaf: Leaf = __safeDI_leaf()
			            return if let safeDIBuilder = safeDIOverrides.first.safeDIBuilder { safeDIBuilder(leaf) } else { Row(leaf: leaf) }
			        }
			        let first: Row = __safeDI_first()
			        func __safeDI_second() -> Row {
			            func __safeDI_leaf() -> Leaf {
			                let service = if let safeDIBuilder = safeDIOverrides.second.leaf.service { safeDIBuilder() } else { Service() }
			                return if let safeDIBuilder = safeDIOverrides.second.leaf.safeDIBuilder { safeDIBuilder(service) } else { Leaf.mock(service: service) }
			            }
			            let leaf: Leaf = __safeDI_leaf()
			            return if let safeDIBuilder = safeDIOverrides.second.safeDIBuilder { safeDIBuilder(leaf) } else { Row(leaf: leaf) }
			        }
			        let second: Row = __safeDI_second()
			        return Root(first: first, second: second)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Leaf {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            service: (() -> Service)? = nil,
			            _ safeDIBuilder: ((Service) -> Leaf)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var service: (() -> Service)? { __safeDI_storage.service }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Service) -> Leaf)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: (() -> Service)?,
			                safeDIBuilder: ((Service) -> Leaf)?
			            ) {
			                self.service = service
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let service: (() -> Service)?
			            let safeDIBuilder: ((Service) -> Leaf)?
			        }
			    }
			}

			extension Row {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            leaf: Leaf.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((Leaf) -> Row)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                leaf: leaf,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var leaf: Leaf.SafeDIMockConfiguration { __safeDI_storage.leaf }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Leaf) -> Row)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                leaf: Leaf.SafeDIMockConfiguration,
			                safeDIBuilder: ((Leaf) -> Row)?
			            ) {
			                self.leaf = leaf
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let leaf: Leaf.SafeDIMockConfiguration
			            let safeDIBuilder: ((Leaf) -> Row)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	/// `Row`, built at two places, has a hand-written mock itself, which the generated mock calls at each place.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_callsHandWrittenMockAtEachPlace_whenSharedTypeHasHandWrittenMock() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(first: Row, second: Row) {
				        self.first = first
				        self.second = second
				    }

				    @Instantiated let first: Row
				    @Instantiated let second: Row
				}
				""",
				"""
				@Instantiable
				public final class Row: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    public static func mock(service: Service) -> Row {
				        Row(service: service)
				    }

				    @Instantiated let service: Service
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable {
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
			    struct SafeDIOverrides {
			        init(
			            first: Row.SafeDIMockConfiguration = .init(),
			            second: Row.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first,
			                second: second
			            )
			        }

			        var first: Row.SafeDIMockConfiguration { __safeDI_storage.first }
			        var second: Row.SafeDIMockConfiguration { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: Row.SafeDIMockConfiguration,
			                second: Row.SafeDIMockConfiguration
			            ) {
			                self.first = first
			                self.second = second
			            }

			            let first: Row.SafeDIMockConfiguration
			            let second: Row.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_first() -> Row {
			            let service = if let safeDIBuilder = safeDIOverrides.first.service { safeDIBuilder() } else { Service() }
			            return if let safeDIBuilder = safeDIOverrides.first.safeDIBuilder { safeDIBuilder(service) } else { Row.mock(service: service) }
			        }
			        let first: Row = __safeDI_first()
			        func __safeDI_second() -> Row {
			            let service = if let safeDIBuilder = safeDIOverrides.second.service { safeDIBuilder() } else { Service() }
			            return if let safeDIBuilder = safeDIOverrides.second.safeDIBuilder { safeDIBuilder(service) } else { Row.mock(service: service) }
			        }
			        let second: Row = __safeDI_second()
			        return Root(first: first, second: second)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Row {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            service: (() -> Service)? = nil,
			            _ safeDIBuilder: ((Service) -> Row)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var service: (() -> Service)? { __safeDI_storage.service }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Service) -> Row)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: (() -> Service)?,
			                safeDIBuilder: ((Service) -> Row)?
			            ) {
			                self.service = service
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let service: (() -> Service)?
			            let safeDIBuilder: ((Service) -> Row)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	// MARK: Tests – erased types

	/// `DefaultService` is built once as itself and once erased to `AnyService`, so the two places return different
	/// types and their overrides take different closures.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_returnsEachPlacesType_whenTypeIsBuiltPlainAndErased() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol Service: AnyObject {}

				public final class AnyService {
				    public init(_ service: any Service) {
				        self.service = service
				    }

				    let service: any Service
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(defaultService: DefaultService, service: AnyService) {
				        self.defaultService = defaultService
				        self.service = service
				    }

				    @Instantiated let defaultService: DefaultService
				    @Instantiated(fulfilledByType: "DefaultService", erasedToConcreteExistential: true) let service: AnyService
				}
				""",
				"""
				@Instantiable
				public final class DefaultService: Service, Instantiable {
				    public init(client: Client) {
				        self.client = client
				    }

				    @Instantiated let client: Client
				}
				""",
				"""
				@Instantiable
				public final class Client: Instantiable {
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
			    struct SafeDIOverrides {
			        init(
			            defaultService: DefaultService.SafeDIMockConfiguration = .init(),
			            service: DefaultService.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                defaultService: defaultService,
			                service: service
			            )
			        }

			        var defaultService: DefaultService.SafeDIMockConfiguration { __safeDI_storage.defaultService }
			        var service: DefaultService.SafeDIMockConfiguration { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                defaultService: DefaultService.SafeDIMockConfiguration,
			                service: DefaultService.SafeDIMockConfiguration
			            ) {
			                self.defaultService = defaultService
			                self.service = service
			            }

			            let defaultService: DefaultService.SafeDIMockConfiguration
			            let service: DefaultService.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_defaultService() -> DefaultService {
			            let client = if let safeDIBuilder = safeDIOverrides.defaultService.client { safeDIBuilder() } else { Client() }
			            return if let safeDIBuilder = safeDIOverrides.defaultService.safeDIBuilder { safeDIBuilder(client) } else { DefaultService(client: client) }
			        }
			        let defaultService: DefaultService = __safeDI_defaultService()
			        func __safeDI_service() -> AnyService {
			            let client = if let safeDIBuilder = safeDIOverrides.service.client { safeDIBuilder() } else { Client() }
			            return if let safeDIBuilder = safeDIOverrides.service.safeDIBuilder { AnyService(safeDIBuilder(client)) } else { AnyService(DefaultService(client: client)) }
			        }
			        let service: AnyService = __safeDI_service()
			        return Root(defaultService: defaultService, service: service)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension DefaultService {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            client: (() -> Client)? = nil,
			            _ safeDIBuilder: ((Client) -> DefaultService)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                client: client,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var client: (() -> Client)? { __safeDI_storage.client }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Client) -> DefaultService)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                client: (() -> Client)?,
			                safeDIBuilder: ((Client) -> DefaultService)?
			            ) {
			                self.client = client
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let client: (() -> Client)?
			            let safeDIBuilder: ((Client) -> DefaultService)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	// MARK: Tests – Sendable

	/// `Row` is built once by value and once inside a `SendableInstantiator`'s `@Sendable` builder.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compiles_whenTypeIsBuiltInsideAndOutsideSendableBuilder() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(row: Row, rowBuilder: SendableInstantiator<Row>) {
				        self.row = row
				        self.rowBuilder = rowBuilder
				    }

				    @Instantiated let row: Row
				    @Instantiated let rowBuilder: SendableInstantiator<Row>
				}
				""",
				"""
				@Instantiable
				public final class Row: Instantiable, Sendable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable, Sendable {
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
			    struct SafeDIOverrides {
			        init(
			            row: Row.SafeDIMockConfiguration = .init(),
			            rowBuilder: Row.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                row: row,
			                rowBuilder: rowBuilder
			            )
			        }

			        var row: Row.SafeDIMockConfiguration { __safeDI_storage.row }
			        var rowBuilder: Row.SafeDIMockConfiguration { __safeDI_storage.rowBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                row: Row.SafeDIMockConfiguration,
			                rowBuilder: Row.SafeDIMockConfiguration
			            ) {
			                self.row = row
			                self.rowBuilder = rowBuilder
			            }

			            let row: Row.SafeDIMockConfiguration
			            let rowBuilder: Row.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_row() -> Row {
			            let service = if let safeDIBuilder = safeDIOverrides.row.service { safeDIBuilder() } else { Service() }
			            return if let safeDIBuilder = safeDIOverrides.row.safeDIBuilder { safeDIBuilder(service) } else { Row(service: service) }
			        }
			        let row: Row = __safeDI_row()
			        let __safeDI_rowBuilder__rowBuilder_service_safeDIBuilder = safeDIOverrides.rowBuilder.service
			        let __safeDI_rowBuilder__safeDIBuilder = safeDIOverrides.rowBuilder.safeDIBuilder
			        @Sendable nonisolated func __safeDI_rowBuilder() -> Row {
			            let service = if let safeDIBuilder = __safeDI_rowBuilder__rowBuilder_service_safeDIBuilder { safeDIBuilder() } else { Service() }
			            return if let safeDIBuilder = __safeDI_rowBuilder__safeDIBuilder { safeDIBuilder(service) } else { Row(service: service) }
			        }
			        let rowBuilder = SendableInstantiator<Row>(__safeDI_rowBuilder)
			        return Root(row: row, rowBuilder: rowBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Row {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            service: (@Sendable () -> Service)? = nil,
			            _ safeDIBuilder: (@Sendable (Service) -> Row)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var service: (@Sendable () -> Service)? { __safeDI_storage.service }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Service) -> Row)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                service: (@Sendable () -> Service)?,
			                safeDIBuilder: (@Sendable (Service) -> Row)?
			            ) {
			                self.service = service
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let service: (@Sendable () -> Service)?
			            let safeDIBuilder: (@Sendable (Service) -> Row)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	/// `Row`, built at two places, builds `Detail` through a `SendableInstantiator`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compiles_whenSharedTypeBuildsSendableInstantiator() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(first: Row, second: Row) {
				        self.first = first
				        self.second = second
				    }

				    @Instantiated let first: Row
				    @Instantiated let second: Row
				}
				""",
				"""
				@Instantiable
				public final class Row: Instantiable {
				    public init(detailBuilder: SendableInstantiator<Detail>) {
				        self.detailBuilder = detailBuilder
				    }

				    @Instantiated let detailBuilder: SendableInstantiator<Detail>
				}
				""",
				"""
				@Instantiable
				public final class Detail: Instantiable, Sendable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable, Sendable {
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
			    struct SafeDIOverrides {
			        init(
			            first: Row.SafeDIMockConfiguration = .init(),
			            second: Row.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first,
			                second: second
			            )
			        }

			        var first: Row.SafeDIMockConfiguration { __safeDI_storage.first }
			        var second: Row.SafeDIMockConfiguration { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: Row.SafeDIMockConfiguration,
			                second: Row.SafeDIMockConfiguration
			            ) {
			                self.first = first
			                self.second = second
			            }

			            let first: Row.SafeDIMockConfiguration
			            let second: Row.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_first() -> Row {
			            let __safeDI_detailBuilder__first_detailBuilder_service_safeDIBuilder = safeDIOverrides.first.detailBuilder.service
			            let __safeDI_detailBuilder__safeDIBuilder = safeDIOverrides.first.detailBuilder.safeDIBuilder
			            @Sendable nonisolated func __safeDI_detailBuilder() -> Detail {
			                let service = if let safeDIBuilder = __safeDI_detailBuilder__first_detailBuilder_service_safeDIBuilder { safeDIBuilder() } else { Service() }
			                return if let safeDIBuilder = __safeDI_detailBuilder__safeDIBuilder { safeDIBuilder(service) } else { Detail(service: service) }
			            }
			            let detailBuilder = SendableInstantiator<Detail>(__safeDI_detailBuilder)
			            return if let safeDIBuilder = safeDIOverrides.first.safeDIBuilder { safeDIBuilder(detailBuilder) } else { Row(detailBuilder: detailBuilder) }
			        }
			        let first: Row = __safeDI_first()
			        func __safeDI_second() -> Row {
			            let __safeDI_detailBuilder__second_detailBuilder_service_safeDIBuilder = safeDIOverrides.second.detailBuilder.service
			            let __safeDI_detailBuilder__safeDIBuilder = safeDIOverrides.second.detailBuilder.safeDIBuilder
			            @Sendable nonisolated func __safeDI_detailBuilder() -> Detail {
			                let service = if let safeDIBuilder = __safeDI_detailBuilder__second_detailBuilder_service_safeDIBuilder { safeDIBuilder() } else { Service() }
			                return if let safeDIBuilder = __safeDI_detailBuilder__safeDIBuilder { safeDIBuilder(service) } else { Detail(service: service) }
			            }
			            let detailBuilder = SendableInstantiator<Detail>(__safeDI_detailBuilder)
			            return if let safeDIBuilder = safeDIOverrides.second.safeDIBuilder { safeDIBuilder(detailBuilder) } else { Row(detailBuilder: detailBuilder) }
			        }
			        let second: Row = __safeDI_second()
			        return Root(first: first, second: second)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Detail {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            service: (@Sendable () -> Service)? = nil,
			            _ safeDIBuilder: (@Sendable (Service) -> Detail)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var service: (@Sendable () -> Service)? { __safeDI_storage.service }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Service) -> Detail)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                service: (@Sendable () -> Service)?,
			                safeDIBuilder: (@Sendable (Service) -> Detail)?
			            ) {
			                self.service = service
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let service: (@Sendable () -> Service)?
			            let safeDIBuilder: (@Sendable (Service) -> Detail)?
			        }
			    }
			}

			extension Row {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            detailBuilder: Detail.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((SendableInstantiator<Detail>) -> Row)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                detailBuilder: detailBuilder,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var detailBuilder: Detail.SafeDIMockConfiguration { __safeDI_storage.detailBuilder }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((SendableInstantiator<Detail>) -> Row)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                detailBuilder: Detail.SafeDIMockConfiguration,
			                safeDIBuilder: ((SendableInstantiator<Detail>) -> Row)?
			            ) {
			                self.detailBuilder = detailBuilder
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let detailBuilder: Detail.SafeDIMockConfiguration
			            let safeDIBuilder: ((SendableInstantiator<Detail>) -> Row)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	// MARK: Tests – lazy

	/// `Row`, built at two places, receives the instance of a `LazilyInstantiated` its parent declares, which is
	/// created at its first read.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesLazilyInstantiatedInstance_whenSharedTypeReceivesIt() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(service: LazilyInstantiated<Service>, first: Row, second: Row) {
				        self.service = service
				        self.first = first
				        self.second = second
				    }

				    @Instantiated let service: LazilyInstantiated<Service>
				    @Instantiated let first: Row
				    @Instantiated let second: Row
				}
				""",
				"""
				@Instantiable
				public final class Row: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Received let service: Service
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable {
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
			    struct SafeDIOverrides {
			        init(
			            service: (() -> Service)? = nil,
			            first: ((Service) -> Row)? = nil,
			            second: ((Service) -> Row)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service,
			                first: first,
			                second: second
			            )
			        }

			        var service: (() -> Service)? { __safeDI_storage.service }
			        var first: ((Service) -> Row)? { __safeDI_storage.first }
			        var second: ((Service) -> Row)? { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: (() -> Service)?,
			                first: ((Service) -> Row)?,
			                second: ((Service) -> Row)?
			            ) {
			                self.service = service
			                self.first = first
			                self.second = second
			            }

			            let service: (() -> Service)?
			            let first: ((Service) -> Row)?
			            let second: ((Service) -> Row)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_service() -> Service {
			            if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service() }
			        }
			        let service = LazilyInstantiated<Service>(__safeDI_service)
			        let first = if let safeDIBuilder = safeDIOverrides.first { safeDIBuilder(service.instance) } else { Row(service: service.instance) }
			        let second = if let safeDIBuilder = safeDIOverrides.second { safeDIBuilder(service.instance) } else { Row(service: service.instance) }
			        return Root(service: service, first: first, second: second)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	// MARK: Tests – aliases

	/// `Row`, built at two places, receives `service` under another label.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsAliasAtEachPlace_whenSharedTypeReceivesAlias() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(service: Service, first: Row, second: Row) {
				        self.service = service
				        self.first = first
				        self.second = second
				    }

				    @Instantiated let service: Service
				    @Instantiated let first: Row
				    @Instantiated let second: Row
				}
				""",
				"""
				@Instantiable
				public final class Row: Instantiable {
				    public init(renamedService: Service) {
				        self.renamedService = renamedService
				    }

				    @Received(fulfilledByDependencyNamed: "service", ofType: Service.self) let renamedService: Service
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable {
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
			    struct SafeDIOverrides {
			        init(
			            service: (() -> Service)? = nil,
			            first: ((Service) -> Row)? = nil,
			            second: ((Service) -> Row)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service,
			                first: first,
			                second: second
			            )
			        }

			        var service: (() -> Service)? { __safeDI_storage.service }
			        var first: ((Service) -> Row)? { __safeDI_storage.first }
			        var second: ((Service) -> Row)? { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: (() -> Service)?,
			                first: ((Service) -> Row)?,
			                second: ((Service) -> Row)?
			            ) {
			                self.service = service
			                self.first = first
			                self.second = second
			            }

			            let service: (() -> Service)?
			            let first: ((Service) -> Row)?
			            let second: ((Service) -> Row)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service() }
			        func __safeDI_first() -> Row {
			            #sourceLocation(file: "\(output.fixtures["Row.swift"])", line: 7)
			            let renamedService: Service = service
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.first { safeDIBuilder(renamedService) } else { Row(renamedService: renamedService) }
			        }
			        let first: Row = __safeDI_first()
			        func __safeDI_second() -> Row {
			            #sourceLocation(file: "\(output.fixtures["Row.swift"])", line: 7)
			            let renamedService: Service = service
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.second { safeDIBuilder(renamedService) } else { Row(renamedService: renamedService) }
			        }
			        let second: Row = __safeDI_second()
			        return Root(service: service, first: first, second: second)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	/// `Row` is built at two places, one beneath `Holder`, which declares `service`, and one beside it, where nothing
	/// does, so its alias only if available is a value at one place and `nil` at the other.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesValueAndNil_whenSharedTypeReceivesOnlyIfAvailableAliasThatOnePlaceLacks() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(holder: Holder, row: Row) {
				        self.holder = holder
				        self.row = row
				    }

				    @Instantiated let holder: Holder
				    @Instantiated let row: Row
				}
				""",
				"""
				@Instantiable
				public final class Holder: Instantiable {
				    public init(service: Service, row: Row) {
				        self.service = service
				        self.row = row
				    }

				    @Instantiated let service: Service
				    @Instantiated let row: Row
				}
				""",
				"""
				@Instantiable
				public final class Row: Instantiable {
				    public init(renamedService: Service?) {
				        self.renamedService = renamedService
				    }

				    @Received(fulfilledByDependencyNamed: "service", ofType: Service.self, onlyIfAvailable: true) let renamedService: Service?
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable {
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
			    struct SafeDIOverrides {
			        init(
			            holder: Holder.SafeDIMockConfiguration = .init(),
			            row: ((Service?) -> Row)? = nil,
			            service: Service? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                holder: holder,
			                row: row
			            )
			            self.service = service
			        }

			        var holder: Holder.SafeDIMockConfiguration { __safeDI_storage.holder }
			        var row: ((Service?) -> Row)? { __safeDI_storage.row }
			        let service: Service?

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                holder: Holder.SafeDIMockConfiguration,
			                row: ((Service?) -> Row)?
			            ) {
			                self.holder = holder
			                self.row = row
			            }

			            let holder: Holder.SafeDIMockConfiguration
			            let row: ((Service?) -> Row)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let service: Service? = safeDIOverrides.service
			        func __safeDI_holder() -> Holder {
			            let service = if let safeDIBuilder = safeDIOverrides.holder.service { safeDIBuilder() } else { Service() }
			            func __safeDI_row() -> Row {
			                #sourceLocation(file: "\(output.fixtures["Row.swift"])", line: 7)
			                let renamedService: Service? = service
			                #sourceLocation()
			                return if let safeDIBuilder = safeDIOverrides.holder.row { safeDIBuilder(renamedService) } else { Row(renamedService: renamedService) }
			            }
			            let row: Row = __safeDI_row()
			            return if let safeDIBuilder = safeDIOverrides.holder.safeDIBuilder { safeDIBuilder(service, row) } else { Holder(service: service, row: row) }
			        }
			        let holder: Holder = __safeDI_holder()
			        func __safeDI_row() -> Row {
			            #sourceLocation(file: "\(output.fixtures["Row.swift"])", line: 7)
			            let renamedService: Service? = service
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.row { safeDIBuilder(renamedService) } else { Row(renamedService: renamedService) }
			        }
			        let row: Row = __safeDI_row()
			        return Root(holder: holder, row: row)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Holder {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            service: (() -> Service)? = nil,
			            row: ((Service?) -> Row)? = nil,
			            _ safeDIBuilder: ((Service, Row) -> Holder)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service,
			                row: row,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var service: (() -> Service)? { __safeDI_storage.service }
			        var row: ((Service?) -> Row)? { __safeDI_storage.row }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Service, Row) -> Holder)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: (() -> Service)?,
			                row: ((Service?) -> Row)?,
			                safeDIBuilder: ((Service, Row) -> Holder)?
			            ) {
			                self.service = service
			                self.row = row
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let service: (() -> Service)?
			            let row: ((Service?) -> Row)?
			            let safeDIBuilder: ((Service, Row) -> Holder)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
