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

/// When several types in a mock's tree create a dependency the mock cannot build, `mock()` takes one value and hands it
/// to each, which its documentation says at that parameter: the types that create the dependency, and how to give one
/// its own instance.
struct SafeDIToolMockSharedParameterDocumentationTests: ~Copyable {
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
	mutating func mock_documentsParameterWithTheTypesThatCreateIt_whenTwoTypesCreateDependencyMockCannotBuild() async throws {
		// `Zebra` and `Apple` each create a `userService` the mock cannot build, so `mock()` takes one value, hands it to both,
		// and says so, listing them as `Screen` declares them rather than by name.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol UserService {}
				public struct AnyUserService: UserService {
				    public init(_ service: some UserService) {}
				}
				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(zebra: Zebra, apple: Apple) { self.zebra = zebra; self.apple = apple }
				    @Instantiated let zebra: Zebra
				    @Instantiated let apple: Apple
				}
				""",
				"""
				@Instantiable
				public struct Zebra: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
				"""
				@Instantiable
				public struct Apple: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            zebra: ((AnyUserService) -> Zebra)? = nil,
		            apple: ((AnyUserService) -> Apple)? = nil
		        ) {
		            self.zebra = zebra
		            self.apple = apple
		        }

		        let zebra: ((AnyUserService) -> Zebra)?
		        let apple: ((AnyUserService) -> Apple)?
		    }

		    /// - Parameter userService: Passed to every type that creates this dependency:
		    ///   `Zebra.userService` and `Apple.userService`. The app creates one for each.
		    ///   To give one its own, override that type in `safeDIOverrides`, or declare a `mockOnly` fake.
		    static func mock(
		        userService: AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let zebra = if let safeDIBuilder = safeDIOverrides.zebra { safeDIBuilder(userService) } else { Zebra(userService: userService) }
		        let apple = if let safeDIBuilder = safeDIOverrides.apple { safeDIBuilder(userService) } else { Apple(userService: userService) }
		        return Screen(zebra: zebra, apple: apple)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_listsCreatingTypesInDeclarationOrder_whenSixTypesCreateDependencyMockCannotBuild() async throws {
		// Six types whose names sort apart from their declaration order, so listing them in any other order fails.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol UserService {}
				public struct AnyUserService: UserService {
				    public init(_ service: some UserService) {}
				}
				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(mango: Mango, apple: Apple, zebra: Zebra, kiwi: Kiwi, banana: Banana, lime: Lime) { self.mango = mango; self.apple = apple; self.zebra = zebra; self.kiwi = kiwi; self.banana = banana; self.lime = lime }
				    @Instantiated let mango: Mango
				    @Instantiated let apple: Apple
				    @Instantiated let zebra: Zebra
				    @Instantiated let kiwi: Kiwi
				    @Instantiated let banana: Banana
				    @Instantiated let lime: Lime
				}
				""",
				"""
				@Instantiable
				public struct Mango: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
				"""
				@Instantiable
				public struct Apple: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
				"""
				@Instantiable
				public struct Zebra: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
				"""
				@Instantiable
				public struct Kiwi: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
				"""
				@Instantiable
				public struct Banana: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
				"""
				@Instantiable
				public struct Lime: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            mango: ((AnyUserService) -> Mango)? = nil,
		            apple: ((AnyUserService) -> Apple)? = nil,
		            zebra: ((AnyUserService) -> Zebra)? = nil,
		            kiwi: ((AnyUserService) -> Kiwi)? = nil,
		            banana: ((AnyUserService) -> Banana)? = nil,
		            lime: ((AnyUserService) -> Lime)? = nil
		        ) {
		            self.mango = mango
		            self.apple = apple
		            self.zebra = zebra
		            self.kiwi = kiwi
		            self.banana = banana
		            self.lime = lime
		        }

		        let mango: ((AnyUserService) -> Mango)?
		        let apple: ((AnyUserService) -> Apple)?
		        let zebra: ((AnyUserService) -> Zebra)?
		        let kiwi: ((AnyUserService) -> Kiwi)?
		        let banana: ((AnyUserService) -> Banana)?
		        let lime: ((AnyUserService) -> Lime)?
		    }

		    /// - Parameter userService: Passed to every type that creates this dependency:
		    ///   `Mango.userService`, `Apple.userService`, `Zebra.userService`, `Kiwi.userService`, `Banana.userService`, and `Lime.userService`. The app creates one for each.
		    ///   To give one its own, override that type in `safeDIOverrides`, or declare a `mockOnly` fake.
		    static func mock(
		        userService: AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let mango = if let safeDIBuilder = safeDIOverrides.mango { safeDIBuilder(userService) } else { Mango(userService: userService) }
		        let apple = if let safeDIBuilder = safeDIOverrides.apple { safeDIBuilder(userService) } else { Apple(userService: userService) }
		        let zebra = if let safeDIBuilder = safeDIOverrides.zebra { safeDIBuilder(userService) } else { Zebra(userService: userService) }
		        let kiwi = if let safeDIBuilder = safeDIOverrides.kiwi { safeDIBuilder(userService) } else { Kiwi(userService: userService) }
		        let banana = if let safeDIBuilder = safeDIOverrides.banana { safeDIBuilder(userService) } else { Banana(userService: userService) }
		        let lime = if let safeDIBuilder = safeDIOverrides.lime { safeDIBuilder(userService) } else { Lime(userService: userService) }
		        return Screen(mango: mango, apple: apple, zebra: zebra, kiwi: kiwi, banana: banana, lime: lime)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_listsMockedTypeThenTreeDepthFirst_whenMockedTypeAndNestedTypesCreateDependencyMockCannotBuild() async throws {
		// The mocked type comes first, and a type `Zebra` builds comes before `Zebra`'s sibling.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol UserService {}
				public struct AnyUserService: UserService {
				    public init(_ service: some UserService) {}
				}
				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(userService: AnyUserService, zebra: Zebra, apple: Apple) { self.userService = userService; self.zebra = zebra; self.apple = apple }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				    @Instantiated let zebra: Zebra
				    @Instantiated let apple: Apple
				}
				""",
				"""
				@Instantiable
				public struct Zebra: Instantiable {
				    public init(deep: Deep, userService: AnyUserService) { self.deep = deep; self.userService = userService }
				    @Instantiated let deep: Deep
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
				"""
				@Instantiable
				public struct Deep: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
				"""
				@Instantiable
				public struct Apple: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            zebra: Zebra.SafeDIMockConfiguration = .init(),
		            apple: ((AnyUserService) -> Apple)? = nil
		        ) {
		            self.zebra = zebra
		            self.apple = apple
		        }

		        let zebra: Zebra.SafeDIMockConfiguration
		        let apple: ((AnyUserService) -> Apple)?
		    }

		    /// - Parameter userService: Passed to every type that creates this dependency:
		    ///   `Screen.userService`, `Zebra.userService`, `Deep.userService`, and `Apple.userService`. The app creates one for each.
		    ///   To give one its own, override that type in `safeDIOverrides`, or declare a `mockOnly` fake.
		    static func mock(
		        userService: AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_zebra() -> Zebra {
		            let deep = if let safeDIBuilder = safeDIOverrides.zebra.deep { safeDIBuilder(userService) } else { Deep(userService: userService) }
		            return if let safeDIBuilder = safeDIOverrides.zebra.safeDIBuilder { safeDIBuilder(deep, userService) } else { Zebra(deep: deep, userService: userService) }
		        }
		        let zebra: Zebra = __safeDI_zebra()
		        let apple = if let safeDIBuilder = safeDIOverrides.apple { safeDIBuilder(userService) } else { Apple(userService: userService) }
		        return Screen(userService: userService, zebra: zebra, apple: apple)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_listsCreatingTypesInDeclarationOrder_whenTreeBuildsTypeDeclaredLaterFirst() async throws {
		// `Zebra` receives `apple`, so `apple` is built first, and `Screen` still declares `zebra` first.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol UserService {}
				public struct AnyUserService: UserService {
				    public init(_ service: some UserService) {}
				}
				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(zebra: Zebra, apple: Apple) { self.zebra = zebra; self.apple = apple }
				    @Instantiated let zebra: Zebra
				    @Instantiated let apple: Apple
				}
				""",
				"""
				@Instantiable
				public struct Zebra: Instantiable {
				    public init(apple: Apple, userService: AnyUserService) { self.apple = apple; self.userService = userService }
				    @Received let apple: Apple
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
				"""
				@Instantiable
				public struct Apple: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            apple: ((AnyUserService) -> Apple)? = nil,
		            zebra: ((Apple, AnyUserService) -> Zebra)? = nil
		        ) {
		            self.apple = apple
		            self.zebra = zebra
		        }

		        let apple: ((AnyUserService) -> Apple)?
		        let zebra: ((Apple, AnyUserService) -> Zebra)?
		    }

		    /// - Parameter userService: Passed to every type that creates this dependency:
		    ///   `Zebra.userService` and `Apple.userService`. The app creates one for each.
		    ///   To give one its own, override that type in `safeDIOverrides`, or declare a `mockOnly` fake.
		    static func mock(
		        userService: AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let apple = if let safeDIBuilder = safeDIOverrides.apple { safeDIBuilder(userService) } else { Apple(userService: userService) }
		        let zebra = if let safeDIBuilder = safeDIOverrides.zebra { safeDIBuilder(apple, userService) } else { Zebra(apple: apple, userService: userService) }
		        return Screen(zebra: zebra, apple: apple)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_listsTypeOnce_whenTypeCreatesDependencyMockCannotBuildInTwoPlaces() async throws {
		// `Profile` is built beneath both `Zebra` and `Apple`: it is one type that creates the dependency, listed once beside `Settings`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol UserService {}
				public struct AnyUserService: UserService {
				    public init(_ service: some UserService) {}
				}
				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(zebra: Zebra, apple: Apple, settings: Settings) { self.zebra = zebra; self.apple = apple; self.settings = settings }
				    @Instantiated let zebra: Zebra
				    @Instantiated let apple: Apple
				    @Instantiated let settings: Settings
				}
				""",
				"""
				@Instantiable
				public struct Zebra: Instantiable {
				    public init(profile: Profile) { self.profile = profile }
				    @Instantiated let profile: Profile
				}
				""",
				"""
				@Instantiable
				public struct Apple: Instantiable {
				    public init(profile: Profile) { self.profile = profile }
				    @Instantiated let profile: Profile
				}
				""",
				"""
				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
				"""
				@Instantiable
				public struct Settings: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            zebra: Zebra.SafeDIMockConfiguration = .init(),
		            apple: Apple.SafeDIMockConfiguration = .init(),
		            settings: ((AnyUserService) -> Settings)? = nil
		        ) {
		            self.zebra = zebra
		            self.apple = apple
		            self.settings = settings
		        }

		        let zebra: Zebra.SafeDIMockConfiguration
		        let apple: Apple.SafeDIMockConfiguration
		        let settings: ((AnyUserService) -> Settings)?
		    }

		    /// - Parameter userService: Passed to every type that creates this dependency:
		    ///   `Profile.userService` and `Settings.userService`. The app creates one for each.
		    ///   To give one its own, override that type in `safeDIOverrides`, or declare a `mockOnly` fake.
		    static func mock(
		        userService: AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_zebra() -> Zebra {
		            let profile = if let safeDIBuilder = safeDIOverrides.zebra.profile { safeDIBuilder(userService) } else { Profile(userService: userService) }
		            return if let safeDIBuilder = safeDIOverrides.zebra.safeDIBuilder { safeDIBuilder(profile) } else { Zebra(profile: profile) }
		        }
		        let zebra: Zebra = __safeDI_zebra()
		        func __safeDI_apple() -> Apple {
		            let profile = if let safeDIBuilder = safeDIOverrides.apple.profile { safeDIBuilder(userService) } else { Profile(userService: userService) }
		            return if let safeDIBuilder = safeDIOverrides.apple.safeDIBuilder { safeDIBuilder(profile) } else { Apple(profile: profile) }
		        }
		        let apple: Apple = __safeDI_apple()
		        let settings = if let safeDIBuilder = safeDIOverrides.settings { safeDIBuilder(userService) } else { Settings(userService: userService) }
		        return Screen(zebra: zebra, apple: apple, settings: settings)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_omitsDocumentation_whenOnlyOneTypeCreatesDependencyMockCannotBuildInTwoPlaces() async throws {
		// `Profile` is built beneath both `Zebra` and `Apple`, and is the only type that creates the dependency.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol UserService {}
				public struct AnyUserService: UserService {
				    public init(_ service: some UserService) {}
				}
				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(zebra: Zebra, apple: Apple) { self.zebra = zebra; self.apple = apple }
				    @Instantiated let zebra: Zebra
				    @Instantiated let apple: Apple
				}
				""",
				"""
				@Instantiable
				public struct Zebra: Instantiable {
				    public init(profile: Profile) { self.profile = profile }
				    @Instantiated let profile: Profile
				}
				""",
				"""
				@Instantiable
				public struct Apple: Instantiable {
				    public init(profile: Profile) { self.profile = profile }
				    @Instantiated let profile: Profile
				}
				""",
				"""
				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            zebra: Zebra.SafeDIMockConfiguration = .init(),
		            apple: Apple.SafeDIMockConfiguration = .init()
		        ) {
		            self.zebra = zebra
		            self.apple = apple
		        }

		        let zebra: Zebra.SafeDIMockConfiguration
		        let apple: Apple.SafeDIMockConfiguration
		    }

		    static func mock(
		        userService: AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_zebra() -> Zebra {
		            let profile = if let safeDIBuilder = safeDIOverrides.zebra.profile { safeDIBuilder(userService) } else { Profile(userService: userService) }
		            return if let safeDIBuilder = safeDIOverrides.zebra.safeDIBuilder { safeDIBuilder(profile) } else { Zebra(profile: profile) }
		        }
		        let zebra: Zebra = __safeDI_zebra()
		        func __safeDI_apple() -> Apple {
		            let profile = if let safeDIBuilder = safeDIOverrides.apple.profile { safeDIBuilder(userService) } else { Profile(userService: userService) }
		            return if let safeDIBuilder = safeDIOverrides.apple.safeDIBuilder { safeDIBuilder(profile) } else { Apple(profile: profile) }
		        }
		        let apple: Apple = __safeDI_apple()
		        return Screen(zebra: zebra, apple: apple)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_documentsOnlyParametersSeveralTypesCreate_whenAnotherParameterIsCreatedOnce() async throws {
		// `userService` and `analytics` are each created twice and documented; `logger` is created once and is not.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol UserService {}
				public struct AnyUserService: UserService {
				    public init(_ service: some UserService) {}
				}
				public struct AnyAnalytics {
				    public init(_ value: some Any) {}
				}
				public struct AnyLogger {
				    public init(_ value: some Any) {}
				}
				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(zebra: Zebra, apple: Apple) { self.zebra = zebra; self.apple = apple }
				    @Instantiated let zebra: Zebra
				    @Instantiated let apple: Apple
				}
				""",
				"""
				@Instantiable
				public struct Zebra: Instantiable {
				    public init(userService: AnyUserService, analytics: AnyAnalytics) { self.userService = userService; self.analytics = analytics }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				    @Instantiated(fulfilledByType: "DefaultAnalytics", erasedToConcreteExistential: true) let analytics: AnyAnalytics
				}
				""",
				"""
				@Instantiable
				public struct Apple: Instantiable {
				    public init(userService: AnyUserService, logger: AnyLogger, analytics: AnyAnalytics) { self.userService = userService; self.logger = logger; self.analytics = analytics }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				    @Instantiated(fulfilledByType: "DefaultLogger", erasedToConcreteExistential: true) let logger: AnyLogger
				    @Instantiated(fulfilledByType: "DefaultAnalytics", erasedToConcreteExistential: true) let analytics: AnyAnalytics
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            zebra: ((AnyUserService, AnyAnalytics) -> Zebra)? = nil,
		            apple: ((AnyUserService, AnyLogger, AnyAnalytics) -> Apple)? = nil
		        ) {
		            self.zebra = zebra
		            self.apple = apple
		        }

		        let zebra: ((AnyUserService, AnyAnalytics) -> Zebra)?
		        let apple: ((AnyUserService, AnyLogger, AnyAnalytics) -> Apple)?
		    }

		    /// - Parameter userService: Passed to every type that creates this dependency:
		    ///   `Zebra.userService` and `Apple.userService`. The app creates one for each.
		    ///   To give one its own, override that type in `safeDIOverrides`, or declare a `mockOnly` fake.
		    /// - Parameter analytics: Passed to every type that creates this dependency:
		    ///   `Zebra.analytics` and `Apple.analytics`. The app creates one for each.
		    ///   To give one its own, override that type in `safeDIOverrides`, or declare a `mockOnly` fake.
		    static func mock(
		        userService: AnyUserService,
		        analytics: AnyAnalytics,
		        logger: AnyLogger,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let zebra = if let safeDIBuilder = safeDIOverrides.zebra { safeDIBuilder(userService, analytics) } else { Zebra(userService: userService, analytics: analytics) }
		        let apple = if let safeDIBuilder = safeDIOverrides.apple { safeDIBuilder(userService, logger, analytics) } else { Apple(userService: userService, logger: logger, analytics: analytics) }
		        return Screen(zebra: zebra, apple: apple)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_omitsDocumentation_whenSeveralTypesCreateDependencyMockCannotBuildAndParameterIsSendableAutoclosure() async throws {
		// A type beneath a `Sendable` wrapper makes the parameter a `@Sendable` autoclosure, which each type calls for its own
		// value, so nothing is shared.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol UserService {}
				public struct AnyUserService: UserService, Sendable {
				    public init(_ service: some UserService) {}
				}
				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(zebraBuilder: SendableInstantiator<Zebra>, apple: Apple) { self.zebraBuilder = zebraBuilder; self.apple = apple }
				    @Instantiated let zebraBuilder: SendableInstantiator<Zebra>
				    @Instantiated let apple: Apple
				}
				""",
				"""
				@Instantiable
				public struct Zebra: Instantiable, Sendable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
				"""
				@Instantiable
				public struct Apple: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            zebraBuilder: (@Sendable (AnyUserService) -> Zebra)? = nil,
		            apple: ((AnyUserService) -> Apple)? = nil
		        ) {
		            self.zebraBuilder = zebraBuilder
		            self.apple = apple
		        }

		        let zebraBuilder: (@Sendable (AnyUserService) -> Zebra)?
		        let apple: ((AnyUserService) -> Apple)?
		    }

		    static func mock(
		        userService: @autoclosure @escaping @Sendable () -> AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_userService = userService
		        let __safeDI_zebraBuilder__safeDIBuilder = safeDIOverrides.zebraBuilder
		        @Sendable func __safeDI_zebraBuilder() -> Zebra {
		            let userService = __safeDI_userService()
		            return if let safeDIBuilder = __safeDI_zebraBuilder__safeDIBuilder { safeDIBuilder(userService) } else { Zebra(userService: userService) }
		        }
		        let zebraBuilder = SendableInstantiator<Zebra>(__safeDI_zebraBuilder)
		        func __safeDI_apple() -> Apple {
		            let userService = __safeDI_userService()
		            return if let safeDIBuilder = safeDIOverrides.apple { safeDIBuilder(userService) } else { Apple(userService: userService) }
		        }
		        let apple: Apple = __safeDI_apple()
		        return Screen(zebraBuilder: zebraBuilder, apple: apple)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsKeywordLabelWithoutBackticks_whenSeveralTypesCreateDependencyMockCannotBuildUnderKeywordLabel() async throws {
		// Swift's documentation parser reads a parameter's name as plain text, and a code span cannot hold a backtick.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol UserService {}
				public struct AnyUserService: UserService {
				    public init(_ service: some UserService) {}
				}
				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(zebra: Zebra, apple: Apple) { self.zebra = zebra; self.apple = apple }
				    @Instantiated let zebra: Zebra
				    @Instantiated let apple: Apple
				}
				""",
				"""
				@Instantiable
				public struct Zebra: Instantiable {
				    public init(`class`: AnyUserService) { self.class = `class` }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let `class`: AnyUserService
				}
				""",
				"""
				@Instantiable
				public struct Apple: Instantiable {
				    public init(`class`: AnyUserService) { self.class = `class` }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let `class`: AnyUserService
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            zebra: ((AnyUserService) -> Zebra)? = nil,
		            apple: ((AnyUserService) -> Apple)? = nil
		        ) {
		            self.zebra = zebra
		            self.apple = apple
		        }

		        let zebra: ((AnyUserService) -> Zebra)?
		        let apple: ((AnyUserService) -> Apple)?
		    }

		    /// - Parameter class: Passed to every type that creates this dependency:
		    ///   `Zebra.class` and `Apple.class`. The app creates one for each.
		    ///   To give one its own, override that type in `safeDIOverrides`, or declare a `mockOnly` fake.
		    static func mock(
		        `class`: AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let zebra = if let safeDIBuilder = safeDIOverrides.zebra { safeDIBuilder(`class`) } else { Zebra(class: `class`) }
		        let apple = if let safeDIBuilder = safeDIOverrides.apple { safeDIBuilder(`class`) } else { Apple(class: `class`) }
		        return Screen(zebra: zebra, apple: apple)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_namesParameterAsSignatureDoes_whenParameterSeveralTypesCreateIsNamedApart() async throws {
		// The mocked type forwards a `userService` of another type, so the parameter is named apart, and the documentation
		// names the parameter as the signature does and each property as its type declares it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol UserService {}
				public struct AnyUserService: UserService {
				    public init(_ service: some UserService) {}
				}
				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(userService: String, zebra: Zebra, apple: Apple) { self.userService = userService; self.zebra = zebra; self.apple = apple }
				    @Forwarded let userService: String
				    @Instantiated let zebra: Zebra
				    @Instantiated let apple: Apple
				}
				""",
				"""
				@Instantiable
				public struct Zebra: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
				"""
				@Instantiable
				public struct Apple: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            zebra: ((AnyUserService) -> Zebra)? = nil,
		            apple: ((AnyUserService) -> Apple)? = nil
		        ) {
		            self.zebra = zebra
		            self.apple = apple
		        }

		        let zebra: ((AnyUserService) -> Zebra)?
		        let apple: ((AnyUserService) -> Apple)?
		    }

		    /// - Parameter userService_AnyUserService: Passed to every type that creates this dependency:
		    ///   `Zebra.userService` and `Apple.userService`. The app creates one for each.
		    ///   To give one its own, override that type in `safeDIOverrides`, or declare a `mockOnly` fake.
		    static func mock(
		        userService: String,
		        userService_AnyUserService: AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let zebra = if let safeDIBuilder = safeDIOverrides.zebra { safeDIBuilder(userService_AnyUserService) } else { Zebra(userService: userService_AnyUserService) }
		        let apple = if let safeDIBuilder = safeDIOverrides.apple { safeDIBuilder(userService_AnyUserService) } else { Apple(userService: userService_AnyUserService) }
		        return Screen(userService: userService, zebra: zebra, apple: apple)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_documentsParameter_whenSeveralTypesLazilyInstantiateDependencyMockCannotBuild() async throws {
		// Two types that each lazily instantiate a dependency share the one wrapper `mock()` takes.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public struct Engine {}
				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(zebra: Zebra, apple: Apple) { self.zebra = zebra; self.apple = apple }
				    @Instantiated let zebra: Zebra
				    @Instantiated let apple: Apple
				}
				""",
				"""
				@Instantiable
				public struct Zebra: Instantiable {
				    public init(engine: LazilyInstantiated<Engine>) { self.engine = engine }
				    @Instantiated let engine: LazilyInstantiated<Engine>
				}
				""",
				"""
				@Instantiable
				public struct Apple: Instantiable {
				    public init(engine: LazilyInstantiated<Engine>) { self.engine = engine }
				    @Instantiated let engine: LazilyInstantiated<Engine>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            zebra: ((LazilyInstantiated<Engine>) -> Zebra)? = nil,
		            apple: ((LazilyInstantiated<Engine>) -> Apple)? = nil
		        ) {
		            self.zebra = zebra
		            self.apple = apple
		        }

		        let zebra: ((LazilyInstantiated<Engine>) -> Zebra)?
		        let apple: ((LazilyInstantiated<Engine>) -> Apple)?
		    }

		    /// - Parameter engine: Passed to every type that creates this dependency:
		    ///   `Zebra.engine` and `Apple.engine`. The app creates one for each.
		    ///   To give one its own, override that type in `safeDIOverrides`, or declare a `mockOnly` fake.
		    static func mock(
		        engine: LazilyInstantiated<Engine>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let zebra = if let safeDIBuilder = safeDIOverrides.zebra { safeDIBuilder(engine) } else { Zebra(engine: engine) }
		        let apple = if let safeDIBuilder = safeDIOverrides.apple { safeDIBuilder(engine) } else { Apple(engine: engine) }
		        return Screen(zebra: zebra, apple: apple)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_qualifiesCreatingTypes_whenNestedTypesCreateDependencyMockCannotBuild() async throws {
		// A nested type is named as a caller names it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol UserService {}
				public struct AnyUserService: UserService {
				    public init(_ service: some UserService) {}
				}
				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(zebra: Feature.Zebra, apple: Feature.Apple) { self.zebra = zebra; self.apple = apple }
				    @Instantiated let zebra: Feature.Zebra
				    @Instantiated let apple: Feature.Apple
				}
				""",
				"""
				public enum Feature {
				    @Instantiable
				    public struct Zebra: Instantiable {
				        public init(userService: AnyUserService) { self.userService = userService }
				        @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				    }

				    @Instantiable
				    public struct Apple: Instantiable {
				        public init(userService: AnyUserService) { self.userService = userService }
				        @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            zebra: ((AnyUserService) -> Feature.Zebra)? = nil,
		            apple: ((AnyUserService) -> Feature.Apple)? = nil
		        ) {
		            self.zebra = zebra
		            self.apple = apple
		        }

		        let zebra: ((AnyUserService) -> Feature.Zebra)?
		        let apple: ((AnyUserService) -> Feature.Apple)?
		    }

		    /// - Parameter userService: Passed to every type that creates this dependency:
		    ///   `Feature.Zebra.userService` and `Feature.Apple.userService`. The app creates one for each.
		    ///   To give one its own, override that type in `safeDIOverrides`, or declare a `mockOnly` fake.
		    static func mock(
		        userService: AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let zebra = if let safeDIBuilder = safeDIOverrides.zebra { safeDIBuilder(userService) } else { Feature.Zebra(userService: userService) }
		        let apple = if let safeDIBuilder = safeDIOverrides.apple { safeDIBuilder(userService) } else { Feature.Apple(userService: userService) }
		        return Screen(zebra: zebra, apple: apple)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsOneFakeForEachTypeAndTakesNoParameter_whenMockOnlyFakeFulfillsDependencySeveralTypesCreate() async throws {
		// The fake the documentation points at: the parameter goes away, each type that creates the dependency gets its own
		// fake, and each can be overridden at its place in the tree.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol UserService {}
				public struct AnyUserService: UserService {
				    public init(_ service: some UserService) {}
				}
				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(zebra: Zebra, apple: Apple) { self.zebra = zebra; self.apple = apple }
				    @Instantiated let zebra: Zebra
				    @Instantiated let apple: Apple
				}
				""",
				"""
				@Instantiable
				public struct Zebra: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
				"""
				@Instantiable
				public struct Apple: Instantiable {
				    public init(userService: AnyUserService) { self.userService = userService }
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
				"""
				@Instantiable(fulfillingAdditionalTypes: [AnyUserService.self], mockOnly: true)
				public struct FakeUserService: UserService {
				    public static func mock() -> FakeUserService { FakeUserService() }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            zebra: Zebra.SafeDIMockConfiguration = .init(),
		            apple: Apple.SafeDIMockConfiguration = .init()
		        ) {
		            self.zebra = zebra
		            self.apple = apple
		        }

		        let zebra: Zebra.SafeDIMockConfiguration
		        let apple: Apple.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_zebra() -> Zebra {
		            let userService = if let safeDIBuilder = safeDIOverrides.zebra.userService { safeDIBuilder() } else { AnyUserService(FakeUserService.mock()) }
		            return if let safeDIBuilder = safeDIOverrides.zebra.safeDIBuilder { safeDIBuilder(userService) } else { Zebra(userService: userService) }
		        }
		        let zebra: Zebra = __safeDI_zebra()
		        func __safeDI_apple() -> Apple {
		            let userService = if let safeDIBuilder = safeDIOverrides.apple.userService { safeDIBuilder() } else { AnyUserService(FakeUserService.mock()) }
		            return if let safeDIBuilder = safeDIOverrides.apple.safeDIBuilder { safeDIBuilder(userService) } else { Apple(userService: userService) }
		        }
		        let apple: Apple = __safeDI_apple()
		        return Screen(zebra: zebra, apple: apple)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func publicMock_documentsParameterOnEachTier_whenSeveralTypesCreateDependencyMockCannotBuild() async throws {
		// A public mock takes a builder for each site of a type nothing fulfills, which shares nothing; a dependency of a
		// type only hand-written code could build, such as an array, is still one value. A public mock declares a `mock()`
		// for each access level its parameters need, and a caller reads the one it can see.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				struct Token {}

				@Instantiable(generateMock: .public)
				public struct Screen: Instantiable {
				    init(zebra: Zebra, apple: Apple, token: Token?) { self.zebra = zebra; self.apple = apple; self.token = token }
				    @Instantiated let zebra: Zebra
				    @Instantiated let apple: Apple
				    @Received(onlyIfAvailable: true) let token: Token?
				}
				""",
				"""
				@Instantiable
				public struct Zebra: Instantiable {
				    public init(tags: [String]) { self.tags = tags }
				    @Instantiated let tags: [String]
				}
				""",
				"""
				@Instantiable
				public struct Apple: Instantiable {
				    public init(tags: [String]) { self.tags = tags }
				    @Instantiated let tags: [String]
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            zebra: (([String]) -> Zebra)? = nil,
		            apple: (([String]) -> Apple)? = nil
		        ) {
		            self.zebra = zebra
		            self.apple = apple
		        }

		        public let zebra: (([String]) -> Zebra)?
		        public let apple: (([String]) -> Apple)?
		    }

		    /// - Parameter tags: Passed to every type that creates this dependency:
		    ///   `Zebra.tags` and `Apple.tags`. The app creates one for each.
		    ///   To give one its own, override that type in `safeDIOverrides`, or declare a `mockOnly` fake.
		    public static func mock(
		        tags: [String],
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        Screen.mock(tags: tags, token: nil, safeDIOverrides: safeDIOverrides)
		    }

		    /// - Parameter tags: Passed to every type that creates this dependency:
		    ///   `Zebra.tags` and `Apple.tags`. The app creates one for each.
		    ///   To give one its own, override that type in `safeDIOverrides`, or declare a `mockOnly` fake.
		    static func mock(
		        tags: [String],
		        token: Token? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let zebra = if let safeDIBuilder = safeDIOverrides.zebra { safeDIBuilder(tags) } else { Zebra(tags: tags) }
		        let apple = if let safeDIBuilder = safeDIOverrides.apple { safeDIBuilder(tags) } else { Apple(tags: tags) }
		        return Screen(zebra: zebra, apple: apple, token: token)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_045FF2CD9665F376 {}
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
