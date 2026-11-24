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

	// MARK: Tests – places handed one another’s values

	/// One loop of builders (A receives B's builder, B receives A's) built beneath two parents, each with a token of
	/// its own. Each parent's loop wraps its builder functions again by name inside the loop's functions.
	///
	/// From the review that tried to break shared builder functions: the probe reports which token, identifier, clock,
	/// session or override each place was handed, and the expected lines are what each place is handed today.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsEachParentsLoopItsOwnTokenAndOverrides_whenLoopOfBuildersIsBuiltBeneathTwoParents() async throws {
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(isRoot: true, generateMock: true)
			public final class Root: Instantiable {
				public init(left: Left, right: Right) {
					self.left = left
					self.right = right
				}

				@Instantiated let left: Left
				@Instantiated let right: Right
			}

			@Instantiable
			public final class Left: Instantiable {
				public init(token: Token, aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
					self.token = token
					self.aBuilder = aBuilder
					self.bBuilder = bBuilder
				}

				@Instantiated let token: Token
				@Instantiated let aBuilder: Instantiator<A>
				@Instantiated let bBuilder: Instantiator<B>
			}

			@Instantiable
			public final class Right: Instantiable {
				public init(token: Token, aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
					self.token = token
					self.aBuilder = aBuilder
					self.bBuilder = bBuilder
				}

				@Instantiated let token: Token
				@Instantiated let aBuilder: Instantiator<A>
				@Instantiated let bBuilder: Instantiator<B>
			}

			@Instantiable
			public final class A: Instantiable {
				public init(bBuilder: Instantiator<B>) {
					self.bBuilder = bBuilder
				}

				@Received let bBuilder: Instantiator<B>
				var note = ""
			}

			@Instantiable
			public final class B: Instantiable {
				public init(aBuilder: Instantiator<A>, token: Token) {
					self.aBuilder = aBuilder
					self.token = token
				}

				@Received let aBuilder: Instantiator<A>
				@Received let token: Token
				var note = ""
			}

			@Instantiable
			public final class Token: Instantiable {
				public init() {}
			}
			""",
		]
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: fixtureFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_left() -> Left {
			            let token = Token()
			            func __safeDI_aBuilder() -> A {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return A(bBuilder: bBuilder)
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            func __safeDI_bBuilder() -> B {
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                return B(aBuilder: aBuilder, token: token)
			            }
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return Left(token: token, aBuilder: aBuilder, bBuilder: bBuilder)
			        }
			        let left: Left = __safeDI_left()
			        func __safeDI_right() -> Right {
			            let token = Token()
			            func __safeDI_aBuilder() -> A {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return A(bBuilder: bBuilder)
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            func __safeDI_bBuilder() -> B {
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                return B(aBuilder: aBuilder, token: token)
			            }
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return Right(token: token, aBuilder: aBuilder, bBuilder: bBuilder)
			        }
			        let right: Right = __safeDI_right()
			        self.init(left: left, right: right)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            left: Left.SafeDIMockConfiguration = .init(),
			            right: Right.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                left: left,
			                right: right
			            )
			        }

			        var left: Left.SafeDIMockConfiguration { __safeDI_storage.left }
			        var right: Right.SafeDIMockConfiguration { __safeDI_storage.right }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                left: Left.SafeDIMockConfiguration,
			                right: Right.SafeDIMockConfiguration
			            ) {
			                self.left = left
			                self.right = right
			            }

			            let left: Left.SafeDIMockConfiguration
			            let right: Right.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_left() -> Left {
			            let token = if let safeDIBuilder = safeDIOverrides.left.token { safeDIBuilder() } else { Token() }
			            func __safeDI_aBuilder() -> A {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return if let safeDIBuilder = safeDIOverrides.left.aBuilder { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			            }
			            func __safeDI_bBuilder() -> B {
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                return if let safeDIBuilder = safeDIOverrides.left.bBuilder { safeDIBuilder(aBuilder, token) } else { B(aBuilder: aBuilder, token: token) }
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.left.safeDIBuilder { safeDIBuilder(token, aBuilder, bBuilder) } else { Left(token: token, aBuilder: aBuilder, bBuilder: bBuilder) }
			        }
			        let left: Left = __safeDI_left()
			        func __safeDI_right() -> Right {
			            let token = if let safeDIBuilder = safeDIOverrides.right.token { safeDIBuilder() } else { Token() }
			            func __safeDI_aBuilder() -> A {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return if let safeDIBuilder = safeDIOverrides.right.aBuilder { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			            }
			            func __safeDI_bBuilder() -> B {
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                return if let safeDIBuilder = safeDIOverrides.right.bBuilder { safeDIBuilder(aBuilder, token) } else { B(aBuilder: aBuilder, token: token) }
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.right.safeDIBuilder { safeDIBuilder(token, aBuilder, bBuilder) } else { Right(token: token, aBuilder: aBuilder, bBuilder: bBuilder) }
			        }
			        let right: Right = __safeDI_right()
			        return Root(left: left, right: right)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Left {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            token: (() -> Token)? = nil,
			            aBuilder: ((Instantiator<B>) -> A)? = nil,
			            bBuilder: ((Instantiator<A>, Token) -> B)? = nil,
			            _ safeDIBuilder: ((Token, Instantiator<A>, Instantiator<B>) -> Left)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                token: token,
			                aBuilder: aBuilder,
			                bBuilder: bBuilder,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var token: (() -> Token)? { __safeDI_storage.token }
			        var aBuilder: ((Instantiator<B>) -> A)? { __safeDI_storage.aBuilder }
			        var bBuilder: ((Instantiator<A>, Token) -> B)? { __safeDI_storage.bBuilder }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Token, Instantiator<A>, Instantiator<B>) -> Left)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                token: (() -> Token)?,
			                aBuilder: ((Instantiator<B>) -> A)?,
			                bBuilder: ((Instantiator<A>, Token) -> B)?,
			                safeDIBuilder: ((Token, Instantiator<A>, Instantiator<B>) -> Left)?
			            ) {
			                self.token = token
			                self.aBuilder = aBuilder
			                self.bBuilder = bBuilder
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let token: (() -> Token)?
			            let aBuilder: ((Instantiator<B>) -> A)?
			            let bBuilder: ((Instantiator<A>, Token) -> B)?
			            let safeDIBuilder: ((Token, Instantiator<A>, Instantiator<B>) -> Left)?
			        }
			    }
			}

			extension Right {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            token: (() -> Token)? = nil,
			            aBuilder: ((Instantiator<B>) -> A)? = nil,
			            bBuilder: ((Instantiator<A>, Token) -> B)? = nil,
			            _ safeDIBuilder: ((Token, Instantiator<A>, Instantiator<B>) -> Right)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                token: token,
			                aBuilder: aBuilder,
			                bBuilder: bBuilder,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var token: (() -> Token)? { __safeDI_storage.token }
			        var aBuilder: ((Instantiator<B>) -> A)? { __safeDI_storage.aBuilder }
			        var bBuilder: ((Instantiator<A>, Token) -> B)? { __safeDI_storage.bBuilder }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Token, Instantiator<A>, Instantiator<B>) -> Right)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                token: (() -> Token)?,
			                aBuilder: ((Instantiator<B>) -> A)?,
			                bBuilder: ((Instantiator<A>, Token) -> B)?,
			                safeDIBuilder: ((Token, Instantiator<A>, Instantiator<B>) -> Right)?
			            ) {
			                self.token = token
			                self.aBuilder = aBuilder
			                self.bBuilder = bBuilder
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let token: (() -> Token)?
			            let aBuilder: ((Instantiator<B>) -> A)?
			            let bBuilder: ((Instantiator<A>, Token) -> B)?
			            let safeDIBuilder: ((Token, Instantiator<A>, Instantiator<B>) -> Right)?
			        }
			    }
			}
			#endif

			""",
		])
		let path = try DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles))
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [
				DifferentialValueProbe(
					name: "what each place was handed",
					expression: #"""
					{ () -> [String] in
						var lines = [String]()
						func report(_ name: String, _ value: some Any) { lines.append("\(name): \(value)") }

						let root = Root.mock()
						let leftB = root.left.aBuilder.instantiate().bBuilder.instantiate()
						let rightB = root.right.aBuilder.instantiate().bBuilder.instantiate()
						report("the two parents hold tokens of their own", root.left.token !== root.right.token)
						report("left's B, built by left's A, reads left's token", leftB.token === root.left.token)
						report("right's B, built by right's A, reads right's token", rightB.token === root.right.token)
						report("right's B on the second lap reads right's token", rightB.aBuilder.instantiate().bBuilder.instantiate().token === root.right.token)
						report("right's B built directly reads right's token", root.right.bBuilder.instantiate().token === root.right.token)
						report("left's B on the second lap reads left's token", leftB.aBuilder.instantiate().bBuilder.instantiate().token === root.left.token)

						let marked = Root.mock(safeDIOverrides: .init(
							left: .init(bBuilder: { aBuilder, token in
								let b = B(aBuilder: aBuilder, token: token)
								b.note = "left's B override"
								return b
							}),
							right: .init(aBuilder: { bBuilder in
								let a = A(bBuilder: bBuilder)
								a.note = "right's A override"
								return a
							}),
						))
						report("left's B built directly", marked.left.bBuilder.instantiate().note)
						report("left's B built by left's A", marked.left.aBuilder.instantiate().bBuilder.instantiate().note)
						report("left's A", marked.left.aBuilder.instantiate().note)
						report("left's A built by left's B", marked.left.bBuilder.instantiate().aBuilder.instantiate().note)
						report("right's B built directly", marked.right.bBuilder.instantiate().note)
						report("right's B built by right's A", marked.right.aBuilder.instantiate().bBuilder.instantiate().note)
						report("right's A", marked.right.aBuilder.instantiate().note)
						report("right's A built by right's B", marked.right.bBuilder.instantiate().aBuilder.instantiate().note)

						let production = Root()
						let productionRightB = production.right.aBuilder.instantiate().bBuilder.instantiate()
						report("production: left's B, built by left's A, reads left's token", production.left.aBuilder.instantiate().bBuilder.instantiate().token === production.left.token)
						report("production: right's B, built by right's A, reads right's token", productionRightB.token === production.right.token)
						report("production: right's B on the second lap reads right's token", productionRightB.aBuilder.instantiate().bBuilder.instantiate().token === production.right.token)
						return lines
					}()
					"""#,
					knownRightExpression: #"""
					[
						"the two parents hold tokens of their own: true",
						"left's B, built by left's A, reads left's token: true",
						"right's B, built by right's A, reads right's token: true",
						"right's B on the second lap reads right's token: true",
						"right's B built directly reads right's token: true",
						"left's B on the second lap reads left's token: true",
						"left's B built directly: left's B override",
						"left's B built by left's A: left's B override",
						"left's A: ",
						"left's A built by left's B: ",
						"right's B built directly: ",
						"right's B built by right's A: ",
						"right's A: right's A override",
						"right's A built by right's B: right's A override",
						"production: left's B, built by left's A, reads left's token: true",
						"production: right's B, built by right's A, reads right's token: true",
						"production: right's B on the second lap reads right's token: true",
					]
					"""#,
				),
			],
			filesToDelete: &filesToDelete,
		)
	}

	/// A cycle of two types the root enters at both: A builds B lazily and B builds A lazily. Beneath `aBuilder` the
	/// cycle closes on A's function, beneath `bBuilder` on B's, so each lap is handed the overrides of the entry it
	/// started from.
	///
	/// From the review that tried to break shared builder functions: the probe reports which token, identifier, clock,
	/// session or override each place was handed, and the expected lines are what each place is handed today.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsOverridesOfEntryEachLapStartedFrom_whenRootEntersCycleAtBothTypes() async throws {
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(isRoot: true, generateMock: true)
			public final class Root: Instantiable {
				public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
					self.aBuilder = aBuilder
					self.bBuilder = bBuilder
				}

				@Instantiated let aBuilder: Instantiator<A>
				@Instantiated let bBuilder: Instantiator<B>
			}

			@Instantiable
			public final class A: Instantiable {
				public init(bBuilder: Instantiator<B>, leaf: Leaf) {
					self.bBuilder = bBuilder
					self.leaf = leaf
				}

				@Instantiated let bBuilder: Instantiator<B>
				@Instantiated let leaf: Leaf
			}

			@Instantiable
			public final class B: Instantiable {
				public init(aBuilder: Instantiator<A>, leaf: Leaf) {
					self.aBuilder = aBuilder
					self.leaf = leaf
				}

				@Instantiated let aBuilder: Instantiator<A>
				@Instantiated let leaf: Leaf
			}

			@Instantiable
			public final class Leaf: Instantiable {
				public init(name: String = "built") {
					self.name = name
				}

				let name: String
			}
			""",
		]
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: fixtureFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            let leaf = Leaf()
			            return A(bBuilder: bBuilder, leaf: leaf)
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let leaf = Leaf()
			            return B(aBuilder: aBuilder, leaf: leaf)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: A.SafeDIMockConfiguration = .init(),
			            bBuilder: B.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                aBuilder: aBuilder,
			                bBuilder: bBuilder
			            )
			        }

			        var aBuilder: A.SafeDIMockConfiguration { __safeDI_storage.aBuilder }
			        var bBuilder: B.SafeDIMockConfiguration { __safeDI_storage.bBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                aBuilder: A.SafeDIMockConfiguration,
			                bBuilder: B.SafeDIMockConfiguration
			            ) {
			                self.aBuilder = aBuilder
			                self.bBuilder = bBuilder
			            }

			            let aBuilder: A.SafeDIMockConfiguration
			            let bBuilder: B.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_aBuilder() -> A {
			            func __safeDI_bBuilder() -> B {
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                func __safeDI_leaf() -> Leaf {
			                    return if let safeDIBuilder = safeDIOverrides.aBuilder.bBuilder.leaf.safeDIBuilder { safeDIBuilder(safeDIOverrides.aBuilder.bBuilder.leaf.name) } else { Leaf(name: safeDIOverrides.aBuilder.bBuilder.leaf.name) }
			                }
			                let leaf: Leaf = __safeDI_leaf()
			                return if let safeDIBuilder = safeDIOverrides.aBuilder.bBuilder.safeDIBuilder { safeDIBuilder(aBuilder, leaf) } else { B(aBuilder: aBuilder, leaf: leaf) }
			            }
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            func __safeDI_leaf() -> Leaf {
			                return if let safeDIBuilder = safeDIOverrides.aBuilder.leaf.safeDIBuilder { safeDIBuilder(safeDIOverrides.aBuilder.leaf.name) } else { Leaf(name: safeDIOverrides.aBuilder.leaf.name) }
			            }
			            let leaf: Leaf = __safeDI_leaf()
			            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(bBuilder, leaf) } else { A(bBuilder: bBuilder, leaf: leaf) }
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        func __safeDI_bBuilder() -> B {
			            func __safeDI_aBuilder() -> A {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                func __safeDI_leaf() -> Leaf {
			                    return Leaf()
			                }
			                let leaf: Leaf = __safeDI_leaf()
			                return A(bBuilder: bBuilder, leaf: leaf)
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            func __safeDI_leaf() -> Leaf {
			                return if let safeDIBuilder = safeDIOverrides.bBuilder.leaf.safeDIBuilder { safeDIBuilder(safeDIOverrides.bBuilder.leaf.name) } else { Leaf(name: safeDIOverrides.bBuilder.leaf.name) }
			            }
			            let leaf: Leaf = __safeDI_leaf()
			            return if let safeDIBuilder = safeDIOverrides.bBuilder.safeDIBuilder { safeDIBuilder(aBuilder, leaf) } else { B(aBuilder: aBuilder, leaf: leaf) }
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return Root(aBuilder: aBuilder, bBuilder: bBuilder)
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
			            name: String = "built",
			            _ safeDIBuilder: ((String) -> Leaf)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                name: name,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var name: String { __safeDI_storage.name }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((String) -> Leaf)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                name: String,
			                safeDIBuilder: ((String) -> Leaf)?
			            ) {
			                self.name = name
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let name: String
			            let safeDIBuilder: ((String) -> Leaf)?
			        }
			    }
			}

			extension B {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            leaf: Leaf.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((Instantiator<A>, Leaf) -> B)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                leaf: leaf,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var leaf: Leaf.SafeDIMockConfiguration { __safeDI_storage.leaf }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Instantiator<A>, Leaf) -> B)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                leaf: Leaf.SafeDIMockConfiguration,
			                safeDIBuilder: ((Instantiator<A>, Leaf) -> B)?
			            ) {
			                self.leaf = leaf
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let leaf: Leaf.SafeDIMockConfiguration
			            let safeDIBuilder: ((Instantiator<A>, Leaf) -> B)?
			        }
			    }
			}

			extension A {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            bBuilder: B.SafeDIMockConfiguration = .init(),
			            leaf: Leaf.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((Instantiator<B>, Leaf) -> A)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                bBuilder: bBuilder,
			                leaf: leaf,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var bBuilder: B.SafeDIMockConfiguration { __safeDI_storage.bBuilder }
			        var leaf: Leaf.SafeDIMockConfiguration { __safeDI_storage.leaf }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Instantiator<B>, Leaf) -> A)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                bBuilder: B.SafeDIMockConfiguration,
			                leaf: Leaf.SafeDIMockConfiguration,
			                safeDIBuilder: ((Instantiator<B>, Leaf) -> A)?
			            ) {
			                self.bBuilder = bBuilder
			                self.leaf = leaf
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let bBuilder: B.SafeDIMockConfiguration
			            let leaf: Leaf.SafeDIMockConfiguration
			            let safeDIBuilder: ((Instantiator<B>, Leaf) -> A)?
			        }
			    }
			}
			#endif

			""",
		])
		let path = try DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles))
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [
				DifferentialValueProbe(
					name: "what each place was handed",
					expression: #"""
					{ () -> [String] in
						var lines = [String]()
						func report(_ name: String, _ value: some Any) { lines.append("\(name): \(value)") }

						let root = Root.mock(safeDIOverrides: .init(
							aBuilder: .init(bBuilder: .init(leaf: .init(name: "B beneath A's entry")), leaf: .init(name: "A's entry")),
							bBuilder: .init(leaf: .init(name: "B's entry")),
						))
						let a = root.aBuilder.instantiate()
						report("entered at A, lap 1, A's leaf", a.leaf.name)
						let aB = a.bBuilder.instantiate()
						report("entered at A, lap 1, B's leaf", aB.leaf.name)
						let aBA = aB.aBuilder.instantiate()
						report("entered at A, lap 2, A's leaf", aBA.leaf.name)
						let aBAB = aBA.bBuilder.instantiate()
						report("entered at A, lap 2, B's leaf", aBAB.leaf.name)
						report("entered at A, lap 3, A's leaf", aBAB.aBuilder.instantiate().leaf.name)
						let b = root.bBuilder.instantiate()
						report("entered at B, lap 1, B's leaf", b.leaf.name)
						let bA = b.aBuilder.instantiate()
						report("entered at B, lap 1, A's leaf", bA.leaf.name)
						let bAB = bA.bBuilder.instantiate()
						report("entered at B, lap 2, B's leaf", bAB.leaf.name)
						let bABA = bAB.aBuilder.instantiate()
						report("entered at B, lap 2, A's leaf", bABA.leaf.name)
						report("entered at B, lap 3, B's leaf", bABA.bBuilder.instantiate().leaf.name)
						return lines
					}()
					"""#,
					knownRightExpression: #"""
					[
						"entered at A, lap 1, A's leaf: A's entry",
						"entered at A, lap 1, B's leaf: B beneath A's entry",
						"entered at A, lap 2, A's leaf: A's entry",
						"entered at A, lap 2, B's leaf: B beneath A's entry",
						"entered at A, lap 3, A's leaf: A's entry",
						"entered at B, lap 1, B's leaf: B's entry",
						"entered at B, lap 1, A's leaf: built",
						"entered at B, lap 2, B's leaf: B's entry",
						"entered at B, lap 2, A's leaf: built",
						"entered at B, lap 3, B's leaf: B's entry",
					]
					"""#,
				),
			],
			filesToDelete: &filesToDelete,
		)
	}

	/// Two cycles, each built beneath two parents that hold a token and overrides of their own: A builds B lazily and B
	/// builds A lazily; and a node that forwards an id builds a reader of the id and, lazily, the next node.
	///
	/// From the review that tried to break shared builder functions: the probe reports which token, identifier, clock,
	/// session or override each place was handed, and the expected lines are what each place is handed today.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsEachParentsCyclesItsOwnTokenIdAndOverrides_whenCyclesAreBuiltBeneathTwoParents() async throws {
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(isRoot: true, generateMock: true)
			public final class Root: Instantiable {
				public init(left: Left, right: Right) {
					self.left = left
					self.right = right
				}

				@Instantiated let left: Left
				@Instantiated let right: Right
			}

			@Instantiable
			public final class Left: Instantiable {
				public init(token: Token, aBuilder: Instantiator<A>, nodeBuilder: Instantiator<Node>) {
					self.token = token
					self.aBuilder = aBuilder
					self.nodeBuilder = nodeBuilder
				}

				@Instantiated let token: Token
				@Instantiated let aBuilder: Instantiator<A>
				@Instantiated let nodeBuilder: Instantiator<Node>
			}

			@Instantiable
			public final class Right: Instantiable {
				public init(token: Token, aBuilder: Instantiator<A>, nodeBuilder: Instantiator<Node>) {
					self.token = token
					self.aBuilder = aBuilder
					self.nodeBuilder = nodeBuilder
				}

				@Instantiated let token: Token
				@Instantiated let aBuilder: Instantiator<A>
				@Instantiated let nodeBuilder: Instantiator<Node>
			}

			@Instantiable
			public final class A: Instantiable {
				public init(bBuilder: Instantiator<B>, leaf: Leaf) {
					self.bBuilder = bBuilder
					self.leaf = leaf
				}

				@Instantiated let bBuilder: Instantiator<B>
				@Instantiated let leaf: Leaf
			}

			@Instantiable
			public final class B: Instantiable {
				public init(aBuilder: Instantiator<A>, leaf: Leaf) {
					self.aBuilder = aBuilder
					self.leaf = leaf
				}

				@Instantiated let aBuilder: Instantiator<A>
				@Instantiated let leaf: Leaf
			}

			@Instantiable
			public final class Leaf: Instantiable {
				public init(token: Token, name: String = "built") {
					self.token = token
					self.name = name
				}

				@Received let token: Token
				let name: String
			}

			@Instantiable
			public final class Node: Instantiable {
				public init(id: ID, reader: Reader, nodeBuilder: Instantiator<Node>) {
					self.id = id
					self.reader = reader
					self.nodeBuilder = nodeBuilder
				}

				@Forwarded let id: ID
				@Instantiated let reader: Reader
				@Instantiated let nodeBuilder: Instantiator<Node>
			}

			@Instantiable
			public final class Reader: Instantiable {
				public init(id: ID, token: Token, name: String = "built") {
					self.id = id
					self.token = token
					self.name = name
				}

				@Received let id: ID
				@Received let token: Token
				let name: String
			}

			@Instantiable
			public final class Token: Instantiable {
				public init() {}
			}

			@Instantiable
			public final class ID: Instantiable {
				public init() {}
			}
			""",
		]
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: fixtureFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder(token: Token) -> A {
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(token: token)
			            }
			            let leaf = Leaf(token: token)
			            return A(bBuilder: bBuilder, leaf: leaf)
			        }
			        func __safeDI_bBuilder(token: Token) -> B {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(token: token)
			            }
			            let leaf = Leaf(token: token)
			            return B(aBuilder: aBuilder, leaf: leaf)
			        }
			        func __safeDI_nodeBuilder(id: ID, token: Token) -> Node {
			            let reader = Reader(id: id, token: token)
			            let nodeBuilder = Instantiator<Node> {
			                __safeDI_nodeBuilder(id: $0, token: token)
			            }
			            return Node(id: id, reader: reader, nodeBuilder: nodeBuilder)
			        }
			        func __safeDI_left() -> Left {
			            let token = Token()
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(token: token)
			            }
			            let nodeBuilder = Instantiator<Node> {
			                __safeDI_nodeBuilder(id: $0, token: token)
			            }
			            return Left(token: token, aBuilder: aBuilder, nodeBuilder: nodeBuilder)
			        }
			        let left: Left = __safeDI_left()
			        func __safeDI_right() -> Right {
			            let token = Token()
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(token: token)
			            }
			            let nodeBuilder = Instantiator<Node> {
			                __safeDI_nodeBuilder(id: $0, token: token)
			            }
			            return Right(token: token, aBuilder: aBuilder, nodeBuilder: nodeBuilder)
			        }
			        let right: Right = __safeDI_right()
			        self.init(left: left, right: right)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            left: Left.SafeDIMockConfiguration = .init(),
			            right: Right.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                left: left,
			                right: right
			            )
			        }

			        var left: Left.SafeDIMockConfiguration { __safeDI_storage.left }
			        var right: Right.SafeDIMockConfiguration { __safeDI_storage.right }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                left: Left.SafeDIMockConfiguration,
			                right: Right.SafeDIMockConfiguration
			            ) {
			                self.left = left
			                self.right = right
			            }

			            let left: Left.SafeDIMockConfiguration
			            let right: Right.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_left() -> Left {
			            let token = if let safeDIBuilder = safeDIOverrides.left.token { safeDIBuilder() } else { Token() }
			            func __safeDI_aBuilder() -> A {
			                func __safeDI_bBuilder() -> B {
			                    let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                    func __safeDI_leaf() -> Leaf {
			                        return if let safeDIBuilder = safeDIOverrides.left.aBuilder.bBuilder.leaf.safeDIBuilder { safeDIBuilder(token, safeDIOverrides.left.aBuilder.bBuilder.leaf.name) } else { Leaf(token: token, name: safeDIOverrides.left.aBuilder.bBuilder.leaf.name) }
			                    }
			                    let leaf: Leaf = __safeDI_leaf()
			                    return if let safeDIBuilder = safeDIOverrides.left.aBuilder.bBuilder.safeDIBuilder { safeDIBuilder(aBuilder, leaf) } else { B(aBuilder: aBuilder, leaf: leaf) }
			                }
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                func __safeDI_leaf() -> Leaf {
			                    return if let safeDIBuilder = safeDIOverrides.left.aBuilder.leaf.safeDIBuilder { safeDIBuilder(token, safeDIOverrides.left.aBuilder.leaf.name) } else { Leaf(token: token, name: safeDIOverrides.left.aBuilder.leaf.name) }
			                }
			                let leaf: Leaf = __safeDI_leaf()
			                return if let safeDIBuilder = safeDIOverrides.left.aBuilder.safeDIBuilder { safeDIBuilder(bBuilder, leaf) } else { A(bBuilder: bBuilder, leaf: leaf) }
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            func __safeDI_nodeBuilder(id: ID) -> Node {
			                func __safeDI_reader() -> Reader {
			                    return if let safeDIBuilder = safeDIOverrides.left.nodeBuilder.reader.safeDIBuilder { safeDIBuilder(id, token, safeDIOverrides.left.nodeBuilder.reader.name) } else { Reader(id: id, token: token, name: safeDIOverrides.left.nodeBuilder.reader.name) }
			                }
			                let reader: Reader = __safeDI_reader()
			                let nodeBuilder = Instantiator<Node> {
			                    __safeDI_nodeBuilder(id: $0)
			                }
			                return if let safeDIBuilder = safeDIOverrides.left.nodeBuilder.safeDIBuilder { safeDIBuilder(id, reader, nodeBuilder) } else { Node(id: id, reader: reader, nodeBuilder: nodeBuilder) }
			            }
			            let nodeBuilder = Instantiator<Node> {
			                __safeDI_nodeBuilder(id: $0)
			            }
			            return if let safeDIBuilder = safeDIOverrides.left.safeDIBuilder { safeDIBuilder(token, aBuilder, nodeBuilder) } else { Left(token: token, aBuilder: aBuilder, nodeBuilder: nodeBuilder) }
			        }
			        let left: Left = __safeDI_left()
			        func __safeDI_right() -> Right {
			            let token = if let safeDIBuilder = safeDIOverrides.right.token { safeDIBuilder() } else { Token() }
			            func __safeDI_aBuilder() -> A {
			                func __safeDI_bBuilder() -> B {
			                    let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                    func __safeDI_leaf() -> Leaf {
			                        return if let safeDIBuilder = safeDIOverrides.right.aBuilder.bBuilder.leaf.safeDIBuilder { safeDIBuilder(token, safeDIOverrides.right.aBuilder.bBuilder.leaf.name) } else { Leaf(token: token, name: safeDIOverrides.right.aBuilder.bBuilder.leaf.name) }
			                    }
			                    let leaf: Leaf = __safeDI_leaf()
			                    return if let safeDIBuilder = safeDIOverrides.right.aBuilder.bBuilder.safeDIBuilder { safeDIBuilder(aBuilder, leaf) } else { B(aBuilder: aBuilder, leaf: leaf) }
			                }
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                func __safeDI_leaf() -> Leaf {
			                    return if let safeDIBuilder = safeDIOverrides.right.aBuilder.leaf.safeDIBuilder { safeDIBuilder(token, safeDIOverrides.right.aBuilder.leaf.name) } else { Leaf(token: token, name: safeDIOverrides.right.aBuilder.leaf.name) }
			                }
			                let leaf: Leaf = __safeDI_leaf()
			                return if let safeDIBuilder = safeDIOverrides.right.aBuilder.safeDIBuilder { safeDIBuilder(bBuilder, leaf) } else { A(bBuilder: bBuilder, leaf: leaf) }
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            func __safeDI_nodeBuilder(id: ID) -> Node {
			                func __safeDI_reader() -> Reader {
			                    return if let safeDIBuilder = safeDIOverrides.right.nodeBuilder.reader.safeDIBuilder { safeDIBuilder(id, token, safeDIOverrides.right.nodeBuilder.reader.name) } else { Reader(id: id, token: token, name: safeDIOverrides.right.nodeBuilder.reader.name) }
			                }
			                let reader: Reader = __safeDI_reader()
			                let nodeBuilder = Instantiator<Node> {
			                    __safeDI_nodeBuilder(id: $0)
			                }
			                return if let safeDIBuilder = safeDIOverrides.right.nodeBuilder.safeDIBuilder { safeDIBuilder(id, reader, nodeBuilder) } else { Node(id: id, reader: reader, nodeBuilder: nodeBuilder) }
			            }
			            let nodeBuilder = Instantiator<Node> {
			                __safeDI_nodeBuilder(id: $0)
			            }
			            return if let safeDIBuilder = safeDIOverrides.right.safeDIBuilder { safeDIBuilder(token, aBuilder, nodeBuilder) } else { Right(token: token, aBuilder: aBuilder, nodeBuilder: nodeBuilder) }
			        }
			        let right: Right = __safeDI_right()
			        return Root(left: left, right: right)
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
			            name: String = "built",
			            _ safeDIBuilder: ((Token, String) -> Leaf)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                name: name,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var name: String { __safeDI_storage.name }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Token, String) -> Leaf)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                name: String,
			                safeDIBuilder: ((Token, String) -> Leaf)?
			            ) {
			                self.name = name
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let name: String
			            let safeDIBuilder: ((Token, String) -> Leaf)?
			        }
			    }
			}

			extension B {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            leaf: Leaf.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((Instantiator<A>, Leaf) -> B)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                leaf: leaf,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var leaf: Leaf.SafeDIMockConfiguration { __safeDI_storage.leaf }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Instantiator<A>, Leaf) -> B)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                leaf: Leaf.SafeDIMockConfiguration,
			                safeDIBuilder: ((Instantiator<A>, Leaf) -> B)?
			            ) {
			                self.leaf = leaf
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let leaf: Leaf.SafeDIMockConfiguration
			            let safeDIBuilder: ((Instantiator<A>, Leaf) -> B)?
			        }
			    }
			}

			extension A {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            bBuilder: B.SafeDIMockConfiguration = .init(),
			            leaf: Leaf.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((Instantiator<B>, Leaf) -> A)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                bBuilder: bBuilder,
			                leaf: leaf,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var bBuilder: B.SafeDIMockConfiguration { __safeDI_storage.bBuilder }
			        var leaf: Leaf.SafeDIMockConfiguration { __safeDI_storage.leaf }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Instantiator<B>, Leaf) -> A)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                bBuilder: B.SafeDIMockConfiguration,
			                leaf: Leaf.SafeDIMockConfiguration,
			                safeDIBuilder: ((Instantiator<B>, Leaf) -> A)?
			            ) {
			                self.bBuilder = bBuilder
			                self.leaf = leaf
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let bBuilder: B.SafeDIMockConfiguration
			            let leaf: Leaf.SafeDIMockConfiguration
			            let safeDIBuilder: ((Instantiator<B>, Leaf) -> A)?
			        }
			    }
			}

			extension Reader {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            name: String = "built",
			            _ safeDIBuilder: ((ID, Token, String) -> Reader)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                name: name,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var name: String { __safeDI_storage.name }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((ID, Token, String) -> Reader)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                name: String,
			                safeDIBuilder: ((ID, Token, String) -> Reader)?
			            ) {
			                self.name = name
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let name: String
			            let safeDIBuilder: ((ID, Token, String) -> Reader)?
			        }
			    }
			}

			extension Node {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            reader: Reader.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((ID, Reader, Instantiator<Node>) -> Node)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                reader: reader,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var reader: Reader.SafeDIMockConfiguration { __safeDI_storage.reader }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((ID, Reader, Instantiator<Node>) -> Node)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                reader: Reader.SafeDIMockConfiguration,
			                safeDIBuilder: ((ID, Reader, Instantiator<Node>) -> Node)?
			            ) {
			                self.reader = reader
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let reader: Reader.SafeDIMockConfiguration
			            let safeDIBuilder: ((ID, Reader, Instantiator<Node>) -> Node)?
			        }
			    }
			}

			extension Left {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            token: (() -> Token)? = nil,
			            aBuilder: A.SafeDIMockConfiguration = .init(),
			            nodeBuilder: Node.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((Token, Instantiator<A>, Instantiator<Node>) -> Left)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                token: token,
			                aBuilder: aBuilder,
			                nodeBuilder: nodeBuilder,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var token: (() -> Token)? { __safeDI_storage.token }
			        var aBuilder: A.SafeDIMockConfiguration { __safeDI_storage.aBuilder }
			        var nodeBuilder: Node.SafeDIMockConfiguration { __safeDI_storage.nodeBuilder }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Token, Instantiator<A>, Instantiator<Node>) -> Left)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                token: (() -> Token)?,
			                aBuilder: A.SafeDIMockConfiguration,
			                nodeBuilder: Node.SafeDIMockConfiguration,
			                safeDIBuilder: ((Token, Instantiator<A>, Instantiator<Node>) -> Left)?
			            ) {
			                self.token = token
			                self.aBuilder = aBuilder
			                self.nodeBuilder = nodeBuilder
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let token: (() -> Token)?
			            let aBuilder: A.SafeDIMockConfiguration
			            let nodeBuilder: Node.SafeDIMockConfiguration
			            let safeDIBuilder: ((Token, Instantiator<A>, Instantiator<Node>) -> Left)?
			        }
			    }
			}

			extension Right {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            token: (() -> Token)? = nil,
			            aBuilder: A.SafeDIMockConfiguration = .init(),
			            nodeBuilder: Node.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((Token, Instantiator<A>, Instantiator<Node>) -> Right)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                token: token,
			                aBuilder: aBuilder,
			                nodeBuilder: nodeBuilder,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var token: (() -> Token)? { __safeDI_storage.token }
			        var aBuilder: A.SafeDIMockConfiguration { __safeDI_storage.aBuilder }
			        var nodeBuilder: Node.SafeDIMockConfiguration { __safeDI_storage.nodeBuilder }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Token, Instantiator<A>, Instantiator<Node>) -> Right)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                token: (() -> Token)?,
			                aBuilder: A.SafeDIMockConfiguration,
			                nodeBuilder: Node.SafeDIMockConfiguration,
			                safeDIBuilder: ((Token, Instantiator<A>, Instantiator<Node>) -> Right)?
			            ) {
			                self.token = token
			                self.aBuilder = aBuilder
			                self.nodeBuilder = nodeBuilder
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let token: (() -> Token)?
			            let aBuilder: A.SafeDIMockConfiguration
			            let nodeBuilder: Node.SafeDIMockConfiguration
			            let safeDIBuilder: ((Token, Instantiator<A>, Instantiator<Node>) -> Right)?
			        }
			    }
			}
			#endif

			""",
		])
		let path = try DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles))
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [
				DifferentialValueProbe(
					name: "what each place was handed",
					expression: #"""
					{ () -> [String] in
						var lines = [String]()
						func report(_ name: String, _ value: some Any) { lines.append("\(name): \(value)") }

						let root = Root.mock(safeDIOverrides: .init(
							left: .init(
								aBuilder: .init(bBuilder: .init(leaf: .init(name: "left B")), leaf: .init(name: "left A")),
								nodeBuilder: .init(reader: .init(name: "left reader")),
							),
							right: .init(
								aBuilder: .init(leaf: .init(name: "right A")),
							),
						))
						for (side, token, aBuilder, nodeBuilder) in [("left", root.left.token, root.left.aBuilder, root.left.nodeBuilder), ("right", root.right.token, root.right.aBuilder, root.right.nodeBuilder)] {
							let a1 = aBuilder.instantiate()
							let b1 = a1.bBuilder.instantiate()
							let a2 = b1.aBuilder.instantiate()
							let b2 = a2.bBuilder.instantiate()
							report("\(side): leaves by lap (A, B, A, B)", [a1.leaf.name, b1.leaf.name, a2.leaf.name, b2.leaf.name])
							report("\(side): every lap's leaf reads \(side)'s token", [a1.leaf, b1.leaf, a2.leaf, b2.leaf].allSatisfy { $0.token === token })
							let ids = [ID(), ID(), ID()]
							let node1 = nodeBuilder.instantiate(ids[0])
							let node2 = node1.nodeBuilder.instantiate(ids[1])
							let node3 = node2.nodeBuilder.instantiate(ids[2])
							report("\(side): each lap's reader reads the id its node was forwarded", node1.reader.id === ids[0] && node2.reader.id === ids[1] && node3.reader.id === ids[2])
							report("\(side): each lap's reader reads \(side)'s token", [node1, node2, node3].allSatisfy { $0.reader.token === token })
							report("\(side): readers by lap", [node1.reader.name, node2.reader.name, node3.reader.name])
						}
						return lines
					}()
					"""#,
					knownRightExpression: #"""
					[
						"left: leaves by lap (A, B, A, B): [\"left A\", \"left B\", \"left A\", \"left B\"]",
						"left: every lap's leaf reads left's token: true",
						"left: each lap's reader reads the id its node was forwarded: true",
						"left: each lap's reader reads left's token: true",
						"left: readers by lap: [\"left reader\", \"left reader\", \"left reader\"]",
						"right: leaves by lap (A, B, A, B): [\"right A\", \"built\", \"right A\", \"built\"]",
						"right: every lap's leaf reads right's token: true",
						"right: each lap's reader reads the id its node was forwarded: true",
						"right: each lap's reader reads right's token: true",
						"right: readers by lap: [\"built\", \"built\", \"built\"]",
					]
					"""#,
				),
			],
			filesToDelete: &filesToDelete,
		)
	}

	/// One type built three times: twice by value under two labels and once through an instantiator, each with a leaf
	/// of its own to override, and each beneath a parent that declares a token of its own.
	///
	/// From the review that tried to break shared builder functions: the probe reports which token, identifier, clock,
	/// session or override each place was handed, and the expected lines are what each place is handed today.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsEachPlaceItsOwnTokenAndOverride_whenTypeIsBuiltUnderTwoLabelsAndByInstantiator() async throws {
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(isRoot: true, generateMock: true)
			public final class Root: Instantiable {
				public init(first: Holder, second: Holder, token: Token, thirdBuilder: Instantiator<Mid>) {
					self.first = first
					self.second = second
					self.token = token
					self.thirdBuilder = thirdBuilder
				}

				@Instantiated let first: Holder
				@Instantiated let second: Holder
				@Instantiated let token: Token
				@Instantiated let thirdBuilder: Instantiator<Mid>
			}

			@Instantiable
			public final class Holder: Instantiable {
				public init(token: Token, mid: Mid) {
					self.token = token
					self.mid = mid
				}

				@Instantiated let token: Token
				@Instantiated let mid: Mid
			}

			@Instantiable
			public final class Mid: Instantiable {
				public init(leaf: Leaf, token: Token) {
					self.leaf = leaf
					self.token = token
				}

				@Instantiated let leaf: Leaf
				@Received let token: Token
			}

			@Instantiable
			public final class Leaf: Instantiable {
				public init(token: Token, name: String = "built") {
					self.token = token
					self.name = name
				}

				@Received let token: Token
				let name: String
			}

			@Instantiable
			public final class Token: Instantiable {
				public init() {}
			}
			""",
		]
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: fixtureFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_first() -> Holder {
			            let token = Token()
			            let mid: Mid = __safeDI_mid(token: token)
			            return Holder(token: token, mid: mid)
			        }
			        func __safeDI_mid(token: Token) -> Mid {
			            let leaf = Leaf(token: token)
			            return Mid(leaf: leaf, token: token)
			        }
			        let first: Holder = __safeDI_first()
			        let second: Holder = __safeDI_first()
			        let token = Token()
			        let thirdBuilder = Instantiator<Mid> {
			            __safeDI_mid(token: token)
			        }
			        self.init(first: first, second: second, token: token, thirdBuilder: thirdBuilder)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            first: Holder.SafeDIMockConfiguration = .init(),
			            second: Holder.SafeDIMockConfiguration = .init(),
			            token: (() -> Token)? = nil,
			            thirdBuilder: Mid.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first,
			                second: second,
			                token: token,
			                thirdBuilder: thirdBuilder
			            )
			        }

			        var first: Holder.SafeDIMockConfiguration { __safeDI_storage.first }
			        var second: Holder.SafeDIMockConfiguration { __safeDI_storage.second }
			        var token: (() -> Token)? { __safeDI_storage.token }
			        var thirdBuilder: Mid.SafeDIMockConfiguration { __safeDI_storage.thirdBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: Holder.SafeDIMockConfiguration,
			                second: Holder.SafeDIMockConfiguration,
			                token: (() -> Token)?,
			                thirdBuilder: Mid.SafeDIMockConfiguration
			            ) {
			                self.first = first
			                self.second = second
			                self.token = token
			                self.thirdBuilder = thirdBuilder
			            }

			            let first: Holder.SafeDIMockConfiguration
			            let second: Holder.SafeDIMockConfiguration
			            let token: (() -> Token)?
			            let thirdBuilder: Mid.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_first() -> Holder {
			            let token = if let safeDIBuilder = safeDIOverrides.first.token { safeDIBuilder() } else { Token() }
			            func __safeDI_mid() -> Mid {
			                func __safeDI_leaf() -> Leaf {
			                    return if let safeDIBuilder = safeDIOverrides.first.mid.leaf.safeDIBuilder { safeDIBuilder(token, safeDIOverrides.first.mid.leaf.name) } else { Leaf(token: token, name: safeDIOverrides.first.mid.leaf.name) }
			                }
			                let leaf: Leaf = __safeDI_leaf()
			                return if let safeDIBuilder = safeDIOverrides.first.mid.safeDIBuilder { safeDIBuilder(leaf, token) } else { Mid(leaf: leaf, token: token) }
			            }
			            let mid: Mid = __safeDI_mid()
			            return if let safeDIBuilder = safeDIOverrides.first.safeDIBuilder { safeDIBuilder(token, mid) } else { Holder(token: token, mid: mid) }
			        }
			        let first: Holder = __safeDI_first()
			        func __safeDI_second() -> Holder {
			            let token = if let safeDIBuilder = safeDIOverrides.second.token { safeDIBuilder() } else { Token() }
			            func __safeDI_mid() -> Mid {
			                func __safeDI_leaf() -> Leaf {
			                    return if let safeDIBuilder = safeDIOverrides.second.mid.leaf.safeDIBuilder { safeDIBuilder(token, safeDIOverrides.second.mid.leaf.name) } else { Leaf(token: token, name: safeDIOverrides.second.mid.leaf.name) }
			                }
			                let leaf: Leaf = __safeDI_leaf()
			                return if let safeDIBuilder = safeDIOverrides.second.mid.safeDIBuilder { safeDIBuilder(leaf, token) } else { Mid(leaf: leaf, token: token) }
			            }
			            let mid: Mid = __safeDI_mid()
			            return if let safeDIBuilder = safeDIOverrides.second.safeDIBuilder { safeDIBuilder(token, mid) } else { Holder(token: token, mid: mid) }
			        }
			        let second: Holder = __safeDI_second()
			        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
			        func __safeDI_thirdBuilder() -> Mid {
			            func __safeDI_leaf() -> Leaf {
			                return if let safeDIBuilder = safeDIOverrides.thirdBuilder.leaf.safeDIBuilder { safeDIBuilder(token, safeDIOverrides.thirdBuilder.leaf.name) } else { Leaf(token: token, name: safeDIOverrides.thirdBuilder.leaf.name) }
			            }
			            let leaf: Leaf = __safeDI_leaf()
			            return if let safeDIBuilder = safeDIOverrides.thirdBuilder.safeDIBuilder { safeDIBuilder(leaf, token) } else { Mid(leaf: leaf, token: token) }
			        }
			        let thirdBuilder = Instantiator<Mid>(__safeDI_thirdBuilder)
			        return Root(first: first, second: second, token: token, thirdBuilder: thirdBuilder)
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
			            name: String = "built",
			            _ safeDIBuilder: ((Token, String) -> Leaf)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                name: name,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var name: String { __safeDI_storage.name }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Token, String) -> Leaf)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                name: String,
			                safeDIBuilder: ((Token, String) -> Leaf)?
			            ) {
			                self.name = name
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let name: String
			            let safeDIBuilder: ((Token, String) -> Leaf)?
			        }
			    }
			}

			extension Mid {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            leaf: Leaf.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((Leaf, Token) -> Mid)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                leaf: leaf,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var leaf: Leaf.SafeDIMockConfiguration { __safeDI_storage.leaf }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Leaf, Token) -> Mid)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                leaf: Leaf.SafeDIMockConfiguration,
			                safeDIBuilder: ((Leaf, Token) -> Mid)?
			            ) {
			                self.leaf = leaf
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let leaf: Leaf.SafeDIMockConfiguration
			            let safeDIBuilder: ((Leaf, Token) -> Mid)?
			        }
			    }
			}

			extension Holder {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            token: (() -> Token)? = nil,
			            mid: Mid.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((Token, Mid) -> Holder)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                token: token,
			                mid: mid,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var token: (() -> Token)? { __safeDI_storage.token }
			        var mid: Mid.SafeDIMockConfiguration { __safeDI_storage.mid }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Token, Mid) -> Holder)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                token: (() -> Token)?,
			                mid: Mid.SafeDIMockConfiguration,
			                safeDIBuilder: ((Token, Mid) -> Holder)?
			            ) {
			                self.token = token
			                self.mid = mid
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let token: (() -> Token)?
			            let mid: Mid.SafeDIMockConfiguration
			            let safeDIBuilder: ((Token, Mid) -> Holder)?
			        }
			    }
			}
			#endif

			""",
		])
		let path = try DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles))
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [
				DifferentialValueProbe(
					name: "what each place was handed",
					expression: #"""
					{ () -> [String] in
						var lines = [String]()
						func report(_ name: String, _ value: some Any) { lines.append("\(name): \(value)") }

						let root = Root.mock(safeDIOverrides: .init(
							first: .init(mid: .init(leaf: .init(name: "first's leaf"))),
							thirdBuilder: .init(leaf: .init(name: "third's leaf")),
						))
						let third = root.thirdBuilder.instantiate()
						report("first's leaf", root.first.mid.leaf.name)
						report("second's leaf", root.second.mid.leaf.name)
						report("third's leaf", third.leaf.name)
						report("three tokens", root.first.token !== root.second.token && root.first.token !== root.token && root.second.token !== root.token)
						report("first's mid reads first's token", root.first.mid.token === root.first.token)
						report("first's leaf reads first's token", root.first.mid.leaf.token === root.first.token)
						report("second's mid reads second's token", root.second.mid.token === root.second.token)
						report("second's leaf reads second's token", root.second.mid.leaf.token === root.second.token)
						report("third's mid reads the root's token", third.token === root.token)
						report("third's leaf reads the root's token", third.leaf.token === root.token)

						let other = Root.mock(safeDIOverrides: .init(
							second: .init(mid: .init({ leaf, token in Mid(leaf: Leaf(token: token, name: "second's mid override"), token: token) })),
						))
						report("first's leaf, second overridden", other.first.mid.leaf.name)
						report("second's leaf, second overridden", other.second.mid.leaf.name)
						report("third's leaf, second overridden", other.thirdBuilder.instantiate().leaf.name)

						let production = Root()
						let productionThird = production.thirdBuilder.instantiate()
						report("production: first's mid and leaf read first's token", production.first.mid.token === production.first.token && production.first.mid.leaf.token === production.first.token)
						report("production: second's mid and leaf read second's token", production.second.mid.token === production.second.token && production.second.mid.leaf.token === production.second.token)
						report("production: third's mid and leaf read the root's token", productionThird.token === production.token && productionThird.leaf.token === production.token)
						return lines
					}()
					"""#,
					knownRightExpression: #"""
					[
						"first's leaf: first's leaf",
						"second's leaf: built",
						"third's leaf: third's leaf",
						"three tokens: true",
						"first's mid reads first's token: true",
						"first's leaf reads first's token: true",
						"second's mid reads second's token: true",
						"second's leaf reads second's token: true",
						"third's mid reads the root's token: true",
						"third's leaf reads the root's token: true",
						"first's leaf, second overridden: built",
						"second's leaf, second overridden: second's mid override",
						"third's leaf, second overridden: built",
						"production: first's mid and leaf read first's token: true",
						"production: second's mid and leaf read second's token: true",
						"production: third's mid and leaf read the root's token: true",
					]
					"""#,
				),
			],
			filesToDelete: &filesToDelete,
		)
	}

	/// One reader of `id` built in three places: beneath a builder that forwards an `id`, beneath another type that
	/// forwards an `id`, and beneath the root, where `id` is a value the mock is passed.
	///
	/// From the review that tried to break shared builder functions: the probe reports which token, identifier, clock,
	/// session or override each place was handed, and the expected lines are what each place is handed today.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsEachReaderTheNearestID_whenReaderIsBuiltBeneathForwardedIDsAndBesideRootValue() async throws {
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(isRoot: true, generateMock: true)
			public final class Root: Instantiable {
				public init(id: ID, reader: Reader, pageBuilder: Instantiator<Page>, sheetBuilder: Instantiator<Sheet>) {
					self.id = id
					self.reader = reader
					self.pageBuilder = pageBuilder
					self.sheetBuilder = sheetBuilder
				}

				@Instantiated let id: ID
				@Instantiated let reader: Reader
				@Instantiated let pageBuilder: Instantiator<Page>
				@Instantiated let sheetBuilder: Instantiator<Sheet>
			}

			@Instantiable
			public final class Page: Instantiable {
				public init(id: ID, reader: Reader) {
					self.id = id
					self.reader = reader
				}

				@Forwarded let id: ID
				@Instantiated let reader: Reader
			}

			@Instantiable
			public final class Sheet: Instantiable {
				public init(id: ID, reader: Reader, pageBuilder: Instantiator<Page>) {
					self.id = id
					self.reader = reader
					self.pageBuilder = pageBuilder
				}

				@Forwarded let id: ID
				@Instantiated let reader: Reader
				@Instantiated let pageBuilder: Instantiator<Page>
			}

			@Instantiable
			public final class Reader: Instantiable {
				public init(id: ID, inner: Inner) {
					self.id = id
					self.inner = inner
				}

				@Received let id: ID
				@Instantiated let inner: Inner
			}

			@Instantiable
			public final class Inner: Instantiable {
				public init(id: ID) {
					self.id = id
				}

				@Received let id: ID
			}

			@Instantiable
			public final class ID: Instantiable {
				public init() {}
			}
			""",
		]
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: fixtureFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let id = ID()
			        func __safeDI_reader(id: ID) -> Reader {
			            let inner = Inner(id: id)
			            return Reader(id: id, inner: inner)
			        }
			        let reader: Reader = __safeDI_reader(id: id)
			        func __safeDI_pageBuilder(id: ID) -> Page {
			            let reader: Reader = __safeDI_reader(id: id)
			            return Page(id: id, reader: reader)
			        }
			        let pageBuilder = Instantiator<Page> {
			            __safeDI_pageBuilder(id: $0)
			        }
			        func __safeDI_sheetBuilder(id: ID) -> Sheet {
			            let reader: Reader = __safeDI_reader(id: id)
			            let pageBuilder = Instantiator<Page> {
			                __safeDI_pageBuilder(id: $0)
			            }
			            return Sheet(id: id, reader: reader, pageBuilder: pageBuilder)
			        }
			        let sheetBuilder = Instantiator<Sheet> {
			            __safeDI_sheetBuilder(id: $0)
			        }
			        self.init(id: id, reader: reader, pageBuilder: pageBuilder, sheetBuilder: sheetBuilder)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            id: (() -> ID)? = nil,
			            reader: Reader.SafeDIMockConfiguration = .init(),
			            pageBuilder: Page.SafeDIMockConfiguration = .init(),
			            sheetBuilder: Sheet.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                id: id,
			                reader: reader,
			                pageBuilder: pageBuilder,
			                sheetBuilder: sheetBuilder
			            )
			        }

			        var id: (() -> ID)? { __safeDI_storage.id }
			        var reader: Reader.SafeDIMockConfiguration { __safeDI_storage.reader }
			        var pageBuilder: Page.SafeDIMockConfiguration { __safeDI_storage.pageBuilder }
			        var sheetBuilder: Sheet.SafeDIMockConfiguration { __safeDI_storage.sheetBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                id: (() -> ID)?,
			                reader: Reader.SafeDIMockConfiguration,
			                pageBuilder: Page.SafeDIMockConfiguration,
			                sheetBuilder: Sheet.SafeDIMockConfiguration
			            ) {
			                self.id = id
			                self.reader = reader
			                self.pageBuilder = pageBuilder
			                self.sheetBuilder = sheetBuilder
			            }

			            let id: (() -> ID)?
			            let reader: Reader.SafeDIMockConfiguration
			            let pageBuilder: Page.SafeDIMockConfiguration
			            let sheetBuilder: Sheet.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let id = if let safeDIBuilder = safeDIOverrides.id { safeDIBuilder() } else { ID() }
			        func __safeDI_reader() -> Reader {
			            let inner = if let safeDIBuilder = safeDIOverrides.reader.inner { safeDIBuilder(id) } else { Inner(id: id) }
			            return if let safeDIBuilder = safeDIOverrides.reader.safeDIBuilder { safeDIBuilder(id, inner) } else { Reader(id: id, inner: inner) }
			        }
			        let reader: Reader = __safeDI_reader()
			        func __safeDI_pageBuilder(id: ID) -> Page {
			            func __safeDI_reader() -> Reader {
			                let inner = if let safeDIBuilder = safeDIOverrides.pageBuilder.reader.inner { safeDIBuilder(id) } else { Inner(id: id) }
			                return if let safeDIBuilder = safeDIOverrides.pageBuilder.reader.safeDIBuilder { safeDIBuilder(id, inner) } else { Reader(id: id, inner: inner) }
			            }
			            let reader: Reader = __safeDI_reader()
			            return if let safeDIBuilder = safeDIOverrides.pageBuilder.safeDIBuilder { safeDIBuilder(id, reader) } else { Page(id: id, reader: reader) }
			        }
			        let pageBuilder = Instantiator<Page> {
			            __safeDI_pageBuilder(id: $0)
			        }
			        func __safeDI_sheetBuilder(id: ID) -> Sheet {
			            func __safeDI_reader() -> Reader {
			                let inner = if let safeDIBuilder = safeDIOverrides.sheetBuilder.reader.inner { safeDIBuilder(id) } else { Inner(id: id) }
			                return if let safeDIBuilder = safeDIOverrides.sheetBuilder.reader.safeDIBuilder { safeDIBuilder(id, inner) } else { Reader(id: id, inner: inner) }
			            }
			            let reader: Reader = __safeDI_reader()
			            func __safeDI_pageBuilder(id: ID) -> Page {
			                func __safeDI_reader() -> Reader {
			                    let inner = if let safeDIBuilder = safeDIOverrides.sheetBuilder.pageBuilder.reader.inner { safeDIBuilder(id) } else { Inner(id: id) }
			                    return if let safeDIBuilder = safeDIOverrides.sheetBuilder.pageBuilder.reader.safeDIBuilder { safeDIBuilder(id, inner) } else { Reader(id: id, inner: inner) }
			                }
			                let reader: Reader = __safeDI_reader()
			                return if let safeDIBuilder = safeDIOverrides.sheetBuilder.pageBuilder.safeDIBuilder { safeDIBuilder(id, reader) } else { Page(id: id, reader: reader) }
			            }
			            let pageBuilder = Instantiator<Page> {
			                __safeDI_pageBuilder(id: $0)
			            }
			            return if let safeDIBuilder = safeDIOverrides.sheetBuilder.safeDIBuilder { safeDIBuilder(id, reader, pageBuilder) } else { Sheet(id: id, reader: reader, pageBuilder: pageBuilder) }
			        }
			        let sheetBuilder = Instantiator<Sheet> {
			            __safeDI_sheetBuilder(id: $0)
			        }
			        return Root(id: id, reader: reader, pageBuilder: pageBuilder, sheetBuilder: sheetBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Reader {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            inner: ((ID) -> Inner)? = nil,
			            _ safeDIBuilder: ((ID, Inner) -> Reader)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                inner: inner,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var inner: ((ID) -> Inner)? { __safeDI_storage.inner }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((ID, Inner) -> Reader)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                inner: ((ID) -> Inner)?,
			                safeDIBuilder: ((ID, Inner) -> Reader)?
			            ) {
			                self.inner = inner
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let inner: ((ID) -> Inner)?
			            let safeDIBuilder: ((ID, Inner) -> Reader)?
			        }
			    }
			}

			extension Page {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            reader: Reader.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((ID, Reader) -> Page)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                reader: reader,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var reader: Reader.SafeDIMockConfiguration { __safeDI_storage.reader }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((ID, Reader) -> Page)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                reader: Reader.SafeDIMockConfiguration,
			                safeDIBuilder: ((ID, Reader) -> Page)?
			            ) {
			                self.reader = reader
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let reader: Reader.SafeDIMockConfiguration
			            let safeDIBuilder: ((ID, Reader) -> Page)?
			        }
			    }
			}

			extension Sheet {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            reader: Reader.SafeDIMockConfiguration = .init(),
			            pageBuilder: Page.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((ID, Reader, Instantiator<Page>) -> Sheet)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                reader: reader,
			                pageBuilder: pageBuilder,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var reader: Reader.SafeDIMockConfiguration { __safeDI_storage.reader }
			        var pageBuilder: Page.SafeDIMockConfiguration { __safeDI_storage.pageBuilder }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((ID, Reader, Instantiator<Page>) -> Sheet)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                reader: Reader.SafeDIMockConfiguration,
			                pageBuilder: Page.SafeDIMockConfiguration,
			                safeDIBuilder: ((ID, Reader, Instantiator<Page>) -> Sheet)?
			            ) {
			                self.reader = reader
			                self.pageBuilder = pageBuilder
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let reader: Reader.SafeDIMockConfiguration
			            let pageBuilder: Page.SafeDIMockConfiguration
			            let safeDIBuilder: ((ID, Reader, Instantiator<Page>) -> Sheet)?
			        }
			    }
			}
			#endif

			""",
		])
		let path = try DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles))
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [
				DifferentialValueProbe(
					name: "what each place was handed",
					expression: #"""
					{ () -> [String] in
						var lines = [String]()
						func report(_ name: String, _ value: some Any) { lines.append("\(name): \(value)") }

						let root = Root.mock()
						let pageID = ID()
						let sheetID = ID()
						let nestedPageID = ID()
						let page = root.pageBuilder.instantiate(pageID)
						let sheet = root.sheetBuilder.instantiate(sheetID)
						let nestedPage = sheet.pageBuilder.instantiate(nestedPageID)
						report("the root's reader reads the root's id", root.reader.id === root.id && root.reader.inner.id === root.id)
						report("the page's reader reads the id the page was forwarded", page.reader.id === pageID && page.reader.inner.id === pageID)
						report("the sheet's reader reads the id the sheet was forwarded", sheet.reader.id === sheetID && sheet.reader.inner.id === sheetID)
						report("the sheet's page's reader reads the id that page was forwarded", nestedPage.reader.id === nestedPageID && nestedPage.reader.inner.id === nestedPageID)

						let marked = Root.mock(safeDIOverrides: .init(
							sheetBuilder: .init(pageBuilder: .init(reader: .init(inner: { id in
								lines.append("the sheet's page's inner override was handed the id that page was forwarded: \(id === nestedPageID)")
								return Inner(id: id)
							}))),
						))
						_ = marked.reader
						_ = marked.pageBuilder.instantiate(pageID)
						let markedSheet = marked.sheetBuilder.instantiate(sheetID)
						lines.append("only the sheet's page calls the override, once:")
						_ = markedSheet.pageBuilder.instantiate(nestedPageID)

						let production = Root()
						let productionSheet = production.sheetBuilder.instantiate(sheetID)
						let productionNestedPage = productionSheet.pageBuilder.instantiate(nestedPageID)
						report("production: the root's reader reads the root's id", production.reader.id === production.id && production.reader.inner.id === production.id)
						report("production: the sheet's reader reads the id the sheet was forwarded", productionSheet.reader.id === sheetID && productionSheet.reader.inner.id === sheetID)
						report("production: the sheet's page's reader reads the id that page was forwarded", productionNestedPage.reader.id === nestedPageID && productionNestedPage.reader.inner.id === nestedPageID)
						return lines
					}()
					"""#,
					knownRightExpression: #"""
					[
						"the root's reader reads the root's id: true",
						"the page's reader reads the id the page was forwarded: true",
						"the sheet's reader reads the id the sheet was forwarded: true",
						"the sheet's page's reader reads the id that page was forwarded: true",
						"only the sheet's page calls the override, once:",
						"the sheet's page's inner override was handed the id that page was forwarded: true",
						"production: the root's reader reads the root's id: true",
						"production: the sheet's reader reads the id the sheet was forwarded: true",
						"production: the sheet's page's reader reads the id that page was forwarded: true",
					]
					"""#,
				),
			],
			filesToDelete: &filesToDelete,
		)
	}

	/// One type built inside two `@Sendable` builders and once in plain code, each place with overrides of its own, and
	/// a value the mock cannot build that each construction creates afresh.
	///
	/// From the review that tried to break shared builder functions: the probe reports which token, identifier, clock,
	/// session or override each place was handed, and the expected lines are what each place is handed today.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsEachPlaceItsOwnOverridesAndClock_whenTypeIsBuiltInsideTwoSendableBuildersAndInPlainCode() async throws {
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable, Sendable {
				public init(firstBuilder: SendableInstantiator<Screen>, secondBuilder: SendableInstantiator<Screen>, plain: Screen) {
					self.firstBuilder = firstBuilder
					self.secondBuilder = secondBuilder
					self.plain = plain
				}

				@Instantiated let firstBuilder: SendableInstantiator<Screen>
				@Instantiated let secondBuilder: SendableInstantiator<Screen>
				@Instantiated let plain: Screen
			}

			@Instantiable
			public final class Screen: Instantiable, Sendable {
				public init(header: Header, clock: Clock) {
					self.header = header
					self.clock = clock
				}

				@Instantiated let header: Header
				@Instantiated let clock: Clock
			}

			@Instantiable
			public final class Header: Instantiable, Sendable {
				public init(clock: Clock, name: String = "built") {
					self.clock = clock
					self.name = name
				}

				@Received let clock: Clock
				let name: String
			}

			public protocol Clock: AnyObject, Sendable {}

			public final class SystemClock: Clock {
				public init() {}
			}
			""",
		]
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: fixtureFiles,
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
			            firstBuilder: Screen.SafeDIMockConfiguration = .init(),
			            secondBuilder: Screen.SafeDIMockConfiguration = .init(),
			            plain: Screen.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                firstBuilder: firstBuilder,
			                secondBuilder: secondBuilder,
			                plain: plain
			            )
			        }

			        var firstBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.firstBuilder }
			        var secondBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.secondBuilder }
			        var plain: Screen.SafeDIMockConfiguration { __safeDI_storage.plain }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                firstBuilder: Screen.SafeDIMockConfiguration,
			                secondBuilder: Screen.SafeDIMockConfiguration,
			                plain: Screen.SafeDIMockConfiguration
			            ) {
			                self.firstBuilder = firstBuilder
			                self.secondBuilder = secondBuilder
			                self.plain = plain
			            }

			            let firstBuilder: Screen.SafeDIMockConfiguration
			            let secondBuilder: Screen.SafeDIMockConfiguration
			            let plain: Screen.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        clock: @autoclosure @escaping @Sendable () -> Clock,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_clock = clock
			        let __safeDI_firstBuilder__firstBuilder_header_safeDIBuilder = safeDIOverrides.firstBuilder.header.safeDIBuilder
			        let __safeDI_firstBuilder__firstBuilder_header_name = safeDIOverrides.firstBuilder.header.name
			        let __safeDI_firstBuilder__safeDIBuilder = safeDIOverrides.firstBuilder.safeDIBuilder
			        @Sendable nonisolated func __safeDI_firstBuilder() -> Screen {
			            let clock = __safeDI_clock()
			            func __safeDI_header() -> Header {
			                return if let safeDIBuilder = __safeDI_firstBuilder__firstBuilder_header_safeDIBuilder { safeDIBuilder(clock, __safeDI_firstBuilder__firstBuilder_header_name()) } else { Header(clock: clock, name: __safeDI_firstBuilder__firstBuilder_header_name()) }
			            }
			            let header: Header = __safeDI_header()
			            return if let safeDIBuilder = __safeDI_firstBuilder__safeDIBuilder { safeDIBuilder(header, clock) } else { Screen(header: header, clock: clock) }
			        }
			        let firstBuilder = SendableInstantiator<Screen>(__safeDI_firstBuilder)
			        let __safeDI_secondBuilder__secondBuilder_header_safeDIBuilder = safeDIOverrides.secondBuilder.header.safeDIBuilder
			        let __safeDI_secondBuilder__secondBuilder_header_name = safeDIOverrides.secondBuilder.header.name
			        let __safeDI_secondBuilder__safeDIBuilder = safeDIOverrides.secondBuilder.safeDIBuilder
			        @Sendable nonisolated func __safeDI_secondBuilder() -> Screen {
			            let clock = __safeDI_clock()
			            func __safeDI_header() -> Header {
			                return if let safeDIBuilder = __safeDI_secondBuilder__secondBuilder_header_safeDIBuilder { safeDIBuilder(clock, __safeDI_secondBuilder__secondBuilder_header_name()) } else { Header(clock: clock, name: __safeDI_secondBuilder__secondBuilder_header_name()) }
			            }
			            let header: Header = __safeDI_header()
			            return if let safeDIBuilder = __safeDI_secondBuilder__safeDIBuilder { safeDIBuilder(header, clock) } else { Screen(header: header, clock: clock) }
			        }
			        let secondBuilder = SendableInstantiator<Screen>(__safeDI_secondBuilder)
			        func __safeDI_plain() -> Screen {
			            let clock = __safeDI_clock()
			            func __safeDI_header() -> Header {
			                return if let safeDIBuilder = safeDIOverrides.plain.header.safeDIBuilder { safeDIBuilder(clock, safeDIOverrides.plain.header.name()) } else { Header(clock: clock, name: safeDIOverrides.plain.header.name()) }
			            }
			            let header: Header = __safeDI_header()
			            return if let safeDIBuilder = safeDIOverrides.plain.safeDIBuilder { safeDIBuilder(header, clock) } else { Screen(header: header, clock: clock) }
			        }
			        let plain: Screen = __safeDI_plain()
			        return Root(firstBuilder: firstBuilder, secondBuilder: secondBuilder, plain: plain)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Header {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            name: @autoclosure @escaping @Sendable () -> String = "built",
			            _ safeDIBuilder: (@Sendable (Clock, String) -> Header)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                name: name,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var name: @Sendable () -> String { __safeDI_storage.name }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Clock, String) -> Header)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                name: @escaping @Sendable () -> String,
			                safeDIBuilder: (@Sendable (Clock, String) -> Header)?
			            ) {
			                self.name = name
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let name: @Sendable () -> String
			            let safeDIBuilder: (@Sendable (Clock, String) -> Header)?
			        }
			    }
			}

			extension Screen {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            header: Header.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: (@Sendable (Header, Clock) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                header: header,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var header: Header.SafeDIMockConfiguration { __safeDI_storage.header }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: (@Sendable (Header, Clock) -> Screen)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                header: Header.SafeDIMockConfiguration,
			                safeDIBuilder: (@Sendable (Header, Clock) -> Screen)?
			            ) {
			                self.header = header
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let header: Header.SafeDIMockConfiguration
			            let safeDIBuilder: (@Sendable (Header, Clock) -> Screen)?
			        }
			    }
			}
			#endif

			""",
		])
		let path = try DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles))
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [
				DifferentialValueProbe(
					name: "what each place was handed",
					expression: #"""
					{ () -> [String] in
						var lines = [String]()
						func report(_ name: String, _ value: some Any) { lines.append("\(name): \(value)") }

						let root = Root.mock(
							clock: SystemClock(),
							safeDIOverrides: .init(
								firstBuilder: .init(header: .init(name: "first's header")),
								secondBuilder: .init({ header, clock in Screen(header: Header(clock: clock, name: "second's screen override"), clock: clock) }),
								plain: .init(header: .init { clock, _ in Header(clock: clock, name: "plain's header override") }),
							),
						)
						let first = root.firstBuilder.instantiate()
						let firstAgain = root.firstBuilder.instantiate()
						let second = root.secondBuilder.instantiate()
						report("first's header", first.header.name)
						report("second's header", second.header.name)
						report("plain's header", root.plain.header.name)
						report("each construction creates its own clock", first.clock !== firstAgain.clock && first.clock !== second.clock && first.clock !== root.plain.clock)
						report("a screen and its header share the screen's clock", first.clock === first.header.clock && firstAgain.clock === firstAgain.header.clock && second.clock === second.header.clock && root.plain.clock === root.plain.header.clock)
						return lines
					}()
					"""#,
					knownRightExpression: #"""
					[
						"first's header: first's header",
						"second's header: second's screen override",
						"plain's header: plain's header override",
						"each construction creates its own clock: true",
						"a screen and its header share the screen's clock: true",
					]
					"""#,
				),
			],
			filesToDelete: &filesToDelete,
		)
	}

	// MARK: Tests – generated size

	/// Layers of four screens, each building a model and, through instantiators, the three screens of the next layer
	/// whose index in their layer differs from its own; every screen and the home that builds the first layer are mocked.
	/// A mock of it builds one builder function per path from its type to a screen, so today its lines grow with three to
	/// the power of its depth. The mocks are thousands of lines long, so their line count stands in for them: a mock that
	/// writes one builder function per type in it writes far fewer, and one that stops doing so writes this many again.
	@Test(arguments: [
		(layerCount: 3, generatedLineCount: 2_136),
		(layerCount: 4, generatedLineCount: 4_460),
		(layerCount: 5, generatedLineCount: 10_564),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_writesPinnedLineCount_whenEveryScreenOfLayeredScreensIsMocked(layerCount: Int, generatedLineCount: Int) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.layeredScreens(layerCount: layerCount),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles.count == layerCount * 4 + 1)
		#expect(Self.lineCount(of: output) == generatedLineCount)
	}

	/// Screens that each forward an `id`, receive the root's `service`, and build, through instantiators, the next three
	/// screens around a ring, so every screen's tree builds itself again: the shape of issue #646, with every screen
	/// mocked. The mocks are thousands of lines long, so their line count stands in for them.
	@Test(arguments: [
		(screenCount: 4, generatedLineCount: 2_733),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_writesPinnedLineCount_whenEveryScreenOfRingOfScreensIsMocked(screenCount: Int, generatedLineCount: Int) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.ringOfScreens(screenCount: screenCount),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles.count == screenCount)
		#expect(Self.lineCount(of: output) == generatedLineCount)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The lines of every file `output` generated.
	private static func lineCount(of output: TestOutput) -> Int {
		(output.generatedFiles ?? [:]).values.reduce(0) { $0 + $1.split(separator: "\n", omittingEmptySubsequences: false).count }
	}

	private static func declaration(of name: String, attributes: String, properties: [(attribute: String, label: String, type: String)]) -> String {
		var lines = ["@Instantiable\(attributes)", "public final class \(name): Instantiable {"]
		lines.append("    public init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {")
		lines.append(contentsOf: properties.map { "        self.\($0.label) = \($0.label)" })
		lines.append("    }")
		lines.append("")
		lines.append(contentsOf: properties.map { "    @\($0.attribute) let \($0.label): \($0.type)" })
		lines.append("}")
		return lines.joined(separator: "\n")
	}

	/// `Home` builds the four screens of the first of `layerCount` layers through instantiators; each screen forwards an
	/// `id`, receives `service`, builds its model, and builds the three screens of the next layer whose index in their
	/// layer differs from its own. The last layer's models receive nothing more.
	private static func layeredScreens(layerCount: Int) -> [String] {
		var files = [String]()
		files.append(declaration(of: "Home", attributes: "(generateMock: true)", properties: [(attribute: "Instantiated", label: "service", type: "Service")] + (0..<4).map {
			(attribute: "Instantiated", label: "screen\($0)Builder", type: "Instantiator<Screen\($0)>")
		}))
		files.append(declaration(of: "Service", attributes: "", properties: []))
		for layer in 0..<layerCount {
			for position in 0..<4 {
				let index = layer * 4 + position
				var properties = [
					(attribute: "Forwarded", label: "id", type: "Int"),
					(attribute: "Received", label: "service", type: "Service"),
					(attribute: "Instantiated", label: "model\(index)", type: "Model\(index)"),
				]
				if layer + 1 < layerCount {
					properties.append(contentsOf: (0..<4).filter { $0 != position }.map {
						(attribute: "Instantiated", label: "screen\((layer + 1) * 4 + $0)Builder", type: "Instantiator<Screen\((layer + 1) * 4 + $0)>")
					})
				}
				files.append(
					declaration(of: "Screen\(index)", attributes: "(generateMock: true)", properties: properties)
						+ "\n\n"
						+ declaration(of: "Model\(index)", attributes: "", properties: [
							(attribute: "Received", label: "id", type: "Int"),
							(attribute: "Received", label: "service", type: "Service"),
						]),
				)
			}
		}
		return files
	}

	/// `screenCount` screens, each forwarding an `id`, receiving `service`, and building the next three screens around
	/// the ring through instantiators. `Service` is built by the mock of each screen, which receives it.
	private static func ringOfScreens(screenCount: Int) -> [String] {
		var files = [declaration(of: "Service", attributes: "", properties: [])]
		for index in 0..<screenCount {
			files.append(declaration(of: "Screen\(index)", attributes: "(generateMock: true)", properties: [
				(attribute: "Forwarded", label: "id", type: "Int"),
				(attribute: "Received", label: "service", type: "Service"),
			] + (1...3).map {
				(attribute: "Instantiated", label: "screen\((index + $0) % screenCount)Builder", type: "Instantiator<Screen\((index + $0) % screenCount)>")
			}))
		}
		return files
	}
}
