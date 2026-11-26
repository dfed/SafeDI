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
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// A public mock whose tree builds a type with children at several places lays its body out by type key
/// (`ScopeGenerator.lowerMockRootWithTree(of:context:)`): each type is built by one function, handed the module-level
/// configuration of the place it builds, so the body grows with the types rather than with the paths.
struct SafeDIToolPublicMockTypeKeyLayoutTests: ~Copyable {
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
	mutating func generate_buildsEachTypeInOneFunction_whenPublicMockBuildsTypeWithChildrenBeneathTwoParents() async throws {
		// `Screen` is built beneath `First` and `Second`: one `__safeDI_screen` builds it, handed the configuration of the
		// place that calls it, and calls `Screen.__safeDI_init` with that configuration's default and `safeDIBuilder`.
		// `Model` receives `token`, which the mock promotes: its binding still reads the caller's value first.
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Types.swift": """
			import SafeDI

			@Instantiable(generateMock: .public)
			public final class Root: Instantiable {
			    public init(first: First, second: Second) {
			        self.first = first
			        self.second = second
			    }

			    @Instantiated let first: First
			    @Instantiated let second: Second
			}

			@Instantiable
			public final class First: Instantiable {
			    public init(screen: Instantiator<Screen>) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Instantiator<Screen>
			}

			@Instantiable
			public final class Second: Instantiable {
			    public init(screen: Instantiator<Screen>) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Instantiator<Screen>
			}

			@Instantiable
			public final class Screen: Instantiable {
			    public init(model: Model, title: String = "Screen") {
			        self.model = model
			        self.title = title
			    }

			    @Instantiated let model: Model
			    let title: String
			}

			@Instantiable
			public final class Model: Instantiable {
			    public init(token: Token) {
			        self.token = token
			    }

			    @Received let token: Token
			}

			@Instantiable
			public final class Token: Instantiable {
			    public init() {}
			}
			"""]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            token: (() -> Token)? = nil,
			            first: __safeDI_Feature_First_MockConfiguration = .init(),
			            second: __safeDI_Feature_Second_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                token: token,
			                first: first,
			                second: second
			            )
			        }

			        public var token: (() -> Token)? { __safeDI_storage.token }
			        public var first: __safeDI_Feature_First_MockConfiguration { __safeDI_storage.first }
			        public var second: __safeDI_Feature_Second_MockConfiguration { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                token: (() -> Token)?,
			                first: __safeDI_Feature_First_MockConfiguration,
			                second: __safeDI_Feature_Second_MockConfiguration
			            ) {
			                self.token = token
			                self.first = first
			                self.second = second
			            }

			            let token: (() -> Token)?
			            let first: __safeDI_Feature_First_MockConfiguration
			            let second: __safeDI_Feature_Second_MockConfiguration
			        }
			    }

			    public static func mock(
			        token: Token? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        Root.__safeDI_mock(token: token, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        token: Token? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let token = if let token { token } else if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
			        func __safeDI_screen(__safeDI_Screen_configuration: __safeDI_Feature_Screen_MockConfiguration) -> Screen {
			            let model = if let safeDIBuilder = __safeDI_Screen_configuration.model { safeDIBuilder(token) } else { Model(token: token) }
			            return Screen.__safeDI_init(model: model, title: __safeDI_Screen_configuration.title, safeDIBuilder: __safeDI_Screen_configuration.safeDIBuilder)
			        }
			        func __safeDI_first(__safeDI_First_configuration: __safeDI_Feature_First_MockConfiguration) -> First {
			            let screen = Instantiator<Screen> {
			                __safeDI_screen(__safeDI_Screen_configuration: __safeDI_First_configuration.screen)
			            }
			            return First.__safeDI_init(screen: screen, safeDIBuilder: __safeDI_First_configuration.safeDIBuilder)
			        }
			        let first: First = __safeDI_first(__safeDI_First_configuration: safeDIOverrides.first)
			        func __safeDI_second(__safeDI_Second_configuration: __safeDI_Feature_Second_MockConfiguration) -> Second {
			            let screen = Instantiator<Screen> {
			                __safeDI_screen(__safeDI_Screen_configuration: __safeDI_Second_configuration.screen)
			            }
			            return Second.__safeDI_init(screen: screen, safeDIBuilder: __safeDI_Second_configuration.safeDIBuilder)
			        }
			        let second: Second = __safeDI_second(__safeDI_Second_configuration: safeDIOverrides.second)
			        return Root(first: first, second: second)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_C51D6EADDA480E49 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Screen` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Screen_MockConfiguration {
			    public init(
			        model: ((Token) -> Model)? = nil,
			        title: String? = nil,
			        _ safeDIBuilder: ((Model, String) -> Screen)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            model: model,
			            title: title,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var model: ((Token) -> Model)? { __safeDI_storage.model }
			    /// `nil` keeps the default of `Screen`’s `title`.
			    public var title: String? { __safeDI_storage.title }
			    /// Overrides how `Screen` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Model, String) -> Screen)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            model: ((Token) -> Model)?,
			            title: String?,
			            safeDIBuilder: ((Model, String) -> Screen)?
			        ) {
			            self.model = model
			            self.title = title
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let model: ((Token) -> Model)?
			        let title: String?
			        let safeDIBuilder: ((Model, String) -> Screen)?
			    }
			}

			extension Screen {
			    static func __safeDI_init(model: Model, title: String?, safeDIBuilder: ((Model, String) -> Screen)?) -> Screen {
			        let title = title ?? ("Screen")
			        return if let safeDIBuilder { safeDIBuilder(model, title) } else { Screen(model: model, title: title) }
			    }
			}

			/// Configuration for how `First` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_First_MockConfiguration {
			    public init(
			        screen: __safeDI_Feature_Screen_MockConfiguration = .init(),
			        _ safeDIBuilder: ((Instantiator<Screen>) -> First)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            screen: screen,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var screen: __safeDI_Feature_Screen_MockConfiguration { __safeDI_storage.screen }
			    /// Overrides how `First` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Instantiator<Screen>) -> First)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            screen: __safeDI_Feature_Screen_MockConfiguration,
			            safeDIBuilder: ((Instantiator<Screen>) -> First)?
			        ) {
			            self.screen = screen
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let screen: __safeDI_Feature_Screen_MockConfiguration
			        let safeDIBuilder: ((Instantiator<Screen>) -> First)?
			    }
			}

			extension First {
			    static func __safeDI_init(screen: Instantiator<Screen>, safeDIBuilder: ((Instantiator<Screen>) -> First)?) -> First {
			        if let safeDIBuilder { safeDIBuilder(screen) } else { First(screen: screen) }
			    }
			}

			/// Configuration for how `Second` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Second_MockConfiguration {
			    public init(
			        screen: __safeDI_Feature_Screen_MockConfiguration = .init(),
			        _ safeDIBuilder: ((Instantiator<Screen>) -> Second)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            screen: screen,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var screen: __safeDI_Feature_Screen_MockConfiguration { __safeDI_storage.screen }
			    /// Overrides how `Second` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Instantiator<Screen>) -> Second)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            screen: __safeDI_Feature_Screen_MockConfiguration,
			            safeDIBuilder: ((Instantiator<Screen>) -> Second)?
			        ) {
			            self.screen = screen
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let screen: __safeDI_Feature_Screen_MockConfiguration
			        let safeDIBuilder: ((Instantiator<Screen>) -> Second)?
			    }
			}

			extension Second {
			    static func __safeDI_init(screen: Instantiator<Screen>, safeDIBuilder: ((Instantiator<Screen>) -> Second)?) -> Second {
			        if let safeDIBuilder { safeDIBuilder(screen) } else { Second(screen: screen) }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsWalkedBody_whenPublicMockPromotesWrapperBeneathTypeBuiltBeneathTwoParents() async throws {
		// `Model` receives `tokenBuilder`, which the mock promotes. A promoted wrapper reads its caller's wrapper where the
		// wrapper is made, outside the builder function no record says, so the root keeps the walked body.
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Types.swift": """
			import SafeDI

			@Instantiable(generateMock: .public)
			public final class Root: Instantiable {
			    public init(first: First, second: Second) {
			        self.first = first
			        self.second = second
			    }

			    @Instantiated let first: First
			    @Instantiated let second: Second
			}

			@Instantiable
			public final class First: Instantiable {
			    public init(screen: Instantiator<Screen>) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Instantiator<Screen>
			}

			@Instantiable
			public final class Second: Instantiable {
			    public init(screen: Instantiator<Screen>) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Instantiator<Screen>
			}

			@Instantiable
			public final class Screen: Instantiable {
			    public init(model: Model) {
			        self.model = model
			    }

			    @Instantiated let model: Model
			}

			@Instantiable
			public final class Model: Instantiable {
			    public init(tokenBuilder: Instantiator<Token>) {
			        self.tokenBuilder = tokenBuilder
			    }

			    @Received let tokenBuilder: Instantiator<Token>
			}

			@Instantiable
			public final class Token: Instantiable {
			    public init() {}
			}
			"""]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            tokenBuilder: (() -> Token)? = nil,
			            first: __safeDI_Feature_First_MockConfiguration = .init(),
			            second: __safeDI_Feature_Second_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                tokenBuilder: tokenBuilder,
			                first: first,
			                second: second
			            )
			        }

			        public var tokenBuilder: (() -> Token)? { __safeDI_storage.tokenBuilder }
			        public var first: __safeDI_Feature_First_MockConfiguration { __safeDI_storage.first }
			        public var second: __safeDI_Feature_Second_MockConfiguration { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                tokenBuilder: (() -> Token)?,
			                first: __safeDI_Feature_First_MockConfiguration,
			                second: __safeDI_Feature_Second_MockConfiguration
			            ) {
			                self.tokenBuilder = tokenBuilder
			                self.first = first
			                self.second = second
			            }

			            let tokenBuilder: (() -> Token)?
			            let first: __safeDI_Feature_First_MockConfiguration
			            let second: __safeDI_Feature_Second_MockConfiguration
			        }
			    }

			    public static func mock(
			        tokenBuilder: Instantiator<Token>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        Root.__safeDI_mock(tokenBuilder: tokenBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        tokenBuilder: Instantiator<Token>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_tokenBuilder() -> Token {
			            if let safeDIBuilder = safeDIOverrides.tokenBuilder { safeDIBuilder() } else { Token() }
			        }
			        let tokenBuilder = if let tokenBuilder { tokenBuilder } else { Instantiator<Token>(__safeDI_tokenBuilder) }
			        func __safeDI_first() -> First {
			            func __safeDI_screen() -> Screen {
			                let model = if let safeDIBuilder = safeDIOverrides.first.screen.model { safeDIBuilder(tokenBuilder) } else { Model(tokenBuilder: tokenBuilder) }
			                return Screen.__safeDI_init(model: model, safeDIBuilder: safeDIOverrides.first.screen.safeDIBuilder)
			            }
			            let screen = Instantiator<Screen>(__safeDI_screen)
			            return First.__safeDI_init(screen: screen, safeDIBuilder: safeDIOverrides.first.safeDIBuilder)
			        }
			        let first: First = __safeDI_first()
			        func __safeDI_second() -> Second {
			            func __safeDI_screen() -> Screen {
			                let model = if let safeDIBuilder = safeDIOverrides.second.screen.model { safeDIBuilder(tokenBuilder) } else { Model(tokenBuilder: tokenBuilder) }
			                return Screen.__safeDI_init(model: model, safeDIBuilder: safeDIOverrides.second.screen.safeDIBuilder)
			            }
			            let screen = Instantiator<Screen>(__safeDI_screen)
			            return Second.__safeDI_init(screen: screen, safeDIBuilder: safeDIOverrides.second.safeDIBuilder)
			        }
			        let second: Second = __safeDI_second()
			        return Root(first: first, second: second)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_ACBF93F2E483D678 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Screen` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Screen_MockConfiguration {
			    public init(
			        model: ((Instantiator<Token>) -> Model)? = nil,
			        _ safeDIBuilder: ((Model) -> Screen)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            model: model,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var model: ((Instantiator<Token>) -> Model)? { __safeDI_storage.model }
			    /// Overrides how `Screen` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Model) -> Screen)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            model: ((Instantiator<Token>) -> Model)?,
			            safeDIBuilder: ((Model) -> Screen)?
			        ) {
			            self.model = model
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let model: ((Instantiator<Token>) -> Model)?
			        let safeDIBuilder: ((Model) -> Screen)?
			    }
			}

			extension Screen {
			    static func __safeDI_init(model: Model, safeDIBuilder: ((Model) -> Screen)?) -> Screen {
			        if let safeDIBuilder { safeDIBuilder(model) } else { Screen(model: model) }
			    }
			}

			/// Configuration for how `First` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_First_MockConfiguration {
			    public init(
			        screen: __safeDI_Feature_Screen_MockConfiguration = .init(),
			        _ safeDIBuilder: ((Instantiator<Screen>) -> First)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            screen: screen,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var screen: __safeDI_Feature_Screen_MockConfiguration { __safeDI_storage.screen }
			    /// Overrides how `First` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Instantiator<Screen>) -> First)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            screen: __safeDI_Feature_Screen_MockConfiguration,
			            safeDIBuilder: ((Instantiator<Screen>) -> First)?
			        ) {
			            self.screen = screen
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let screen: __safeDI_Feature_Screen_MockConfiguration
			        let safeDIBuilder: ((Instantiator<Screen>) -> First)?
			    }
			}

			extension First {
			    static func __safeDI_init(screen: Instantiator<Screen>, safeDIBuilder: ((Instantiator<Screen>) -> First)?) -> First {
			        if let safeDIBuilder { safeDIBuilder(screen) } else { First(screen: screen) }
			    }
			}

			/// Configuration for how `Second` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Second_MockConfiguration {
			    public init(
			        screen: __safeDI_Feature_Screen_MockConfiguration = .init(),
			        _ safeDIBuilder: ((Instantiator<Screen>) -> Second)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            screen: screen,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var screen: __safeDI_Feature_Screen_MockConfiguration { __safeDI_storage.screen }
			    /// Overrides how `Second` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Instantiator<Screen>) -> Second)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            screen: __safeDI_Feature_Screen_MockConfiguration,
			            safeDIBuilder: ((Instantiator<Screen>) -> Second)?
			        ) {
			            self.screen = screen
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let screen: __safeDI_Feature_Screen_MockConfiguration
			        let safeDIBuilder: ((Instantiator<Screen>) -> Second)?
			    }
			}

			extension Second {
			    static func __safeDI_init(screen: Instantiator<Screen>, safeDIBuilder: ((Instantiator<Screen>) -> Second)?) -> Second {
			        if let safeDIBuilder { safeDIBuilder(screen) } else { Second(screen: screen) }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_triesPassedValueBeforeBuildingItsChildren_whenPublicMockPromotesTypeWithChildBeneathTypeBuiltBeneathTwoParents() async throws {
		// `Model` receives `token`, which the mock promotes, and `Token` instantiates `clock`. The body tries the caller's
		// `token` where it calls `__safeDI_token`, so a passed value builds no `Clock`.
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Types.swift": """
			import SafeDI

			@Instantiable(generateMock: .public)
			public final class Root: Instantiable {
			    public init(first: First, second: Second) {
			        self.first = first
			        self.second = second
			    }

			    @Instantiated let first: First
			    @Instantiated let second: Second
			}

			@Instantiable
			public final class First: Instantiable {
			    public init(screen: Instantiator<Screen>) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Instantiator<Screen>
			}

			@Instantiable
			public final class Second: Instantiable {
			    public init(screen: Instantiator<Screen>) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Instantiator<Screen>
			}

			@Instantiable
			public final class Screen: Instantiable {
			    public init(model: Model) {
			        self.model = model
			    }

			    @Instantiated let model: Model
			}

			@Instantiable
			public final class Model: Instantiable {
			    public init(token: Token) {
			        self.token = token
			    }

			    @Received let token: Token
			}

			@Instantiable
			public final class Token: Instantiable {
			    public init(clock: Clock) {
			        self.clock = clock
			    }

			    @Instantiated let clock: Clock
			}

			@Instantiable
			public final class Clock: Instantiable {
			    public init() {}
			}
			"""]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            token: __safeDI_Feature_Token_MockConfiguration = .init(),
			            first: __safeDI_Feature_First_MockConfiguration = .init(),
			            second: __safeDI_Feature_Second_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                token: token,
			                first: first,
			                second: second
			            )
			        }

			        public var token: __safeDI_Feature_Token_MockConfiguration { __safeDI_storage.token }
			        public var first: __safeDI_Feature_First_MockConfiguration { __safeDI_storage.first }
			        public var second: __safeDI_Feature_Second_MockConfiguration { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                token: __safeDI_Feature_Token_MockConfiguration,
			                first: __safeDI_Feature_First_MockConfiguration,
			                second: __safeDI_Feature_Second_MockConfiguration
			            ) {
			                self.token = token
			                self.first = first
			                self.second = second
			            }

			            let token: __safeDI_Feature_Token_MockConfiguration
			            let first: __safeDI_Feature_First_MockConfiguration
			            let second: __safeDI_Feature_Second_MockConfiguration
			        }
			    }

			    public static func mock(
			        token: Token? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        Root.__safeDI_mock(token: token, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        token: Token? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_token(__safeDI_Token_configuration: __safeDI_Feature_Token_MockConfiguration) -> Token {
			            let clock = if let safeDIBuilder = __safeDI_Token_configuration.clock { safeDIBuilder() } else { Clock() }
			            return Token.__safeDI_init(clock: clock, safeDIBuilder: __safeDI_Token_configuration.safeDIBuilder)
			        }
			        let token: Token = if let token { token } else { __safeDI_token(__safeDI_Token_configuration: safeDIOverrides.token) }
			        func __safeDI_screen(__safeDI_Screen_configuration: __safeDI_Feature_Screen_MockConfiguration) -> Screen {
			            let model = if let safeDIBuilder = __safeDI_Screen_configuration.model { safeDIBuilder(token) } else { Model(token: token) }
			            return Screen.__safeDI_init(model: model, safeDIBuilder: __safeDI_Screen_configuration.safeDIBuilder)
			        }
			        func __safeDI_first(__safeDI_First_configuration: __safeDI_Feature_First_MockConfiguration) -> First {
			            let screen = Instantiator<Screen> {
			                __safeDI_screen(__safeDI_Screen_configuration: __safeDI_First_configuration.screen)
			            }
			            return First.__safeDI_init(screen: screen, safeDIBuilder: __safeDI_First_configuration.safeDIBuilder)
			        }
			        let first: First = __safeDI_first(__safeDI_First_configuration: safeDIOverrides.first)
			        func __safeDI_second(__safeDI_Second_configuration: __safeDI_Feature_Second_MockConfiguration) -> Second {
			            let screen = Instantiator<Screen> {
			                __safeDI_screen(__safeDI_Screen_configuration: __safeDI_Second_configuration.screen)
			            }
			            return Second.__safeDI_init(screen: screen, safeDIBuilder: __safeDI_Second_configuration.safeDIBuilder)
			        }
			        let second: Second = __safeDI_second(__safeDI_Second_configuration: safeDIOverrides.second)
			        return Root(first: first, second: second)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_C51D6EADDA480E49 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Token` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Token_MockConfiguration {
			    public init(
			        clock: (() -> Clock)? = nil,
			        _ safeDIBuilder: ((Clock) -> Token)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            clock: clock,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var clock: (() -> Clock)? { __safeDI_storage.clock }
			    /// Overrides how `Token` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Clock) -> Token)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            clock: (() -> Clock)?,
			            safeDIBuilder: ((Clock) -> Token)?
			        ) {
			            self.clock = clock
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let clock: (() -> Clock)?
			        let safeDIBuilder: ((Clock) -> Token)?
			    }
			}

			extension Token {
			    static func __safeDI_init(clock: Clock, safeDIBuilder: ((Clock) -> Token)?) -> Token {
			        if let safeDIBuilder { safeDIBuilder(clock) } else { Token(clock: clock) }
			    }
			}

			/// Configuration for how `Screen` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Screen_MockConfiguration {
			    public init(
			        model: ((Token) -> Model)? = nil,
			        _ safeDIBuilder: ((Model) -> Screen)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            model: model,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var model: ((Token) -> Model)? { __safeDI_storage.model }
			    /// Overrides how `Screen` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Model) -> Screen)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            model: ((Token) -> Model)?,
			            safeDIBuilder: ((Model) -> Screen)?
			        ) {
			            self.model = model
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let model: ((Token) -> Model)?
			        let safeDIBuilder: ((Model) -> Screen)?
			    }
			}

			extension Screen {
			    static func __safeDI_init(model: Model, safeDIBuilder: ((Model) -> Screen)?) -> Screen {
			        if let safeDIBuilder { safeDIBuilder(model) } else { Screen(model: model) }
			    }
			}

			/// Configuration for how `First` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_First_MockConfiguration {
			    public init(
			        screen: __safeDI_Feature_Screen_MockConfiguration = .init(),
			        _ safeDIBuilder: ((Instantiator<Screen>) -> First)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            screen: screen,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var screen: __safeDI_Feature_Screen_MockConfiguration { __safeDI_storage.screen }
			    /// Overrides how `First` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Instantiator<Screen>) -> First)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            screen: __safeDI_Feature_Screen_MockConfiguration,
			            safeDIBuilder: ((Instantiator<Screen>) -> First)?
			        ) {
			            self.screen = screen
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let screen: __safeDI_Feature_Screen_MockConfiguration
			        let safeDIBuilder: ((Instantiator<Screen>) -> First)?
			    }
			}

			extension First {
			    static func __safeDI_init(screen: Instantiator<Screen>, safeDIBuilder: ((Instantiator<Screen>) -> First)?) -> First {
			        if let safeDIBuilder { safeDIBuilder(screen) } else { First(screen: screen) }
			    }
			}

			/// Configuration for how `Second` is constructed within the public mock trees of module `Feature`.
			nonisolated public struct __safeDI_Feature_Second_MockConfiguration {
			    public init(
			        screen: __safeDI_Feature_Screen_MockConfiguration = .init(),
			        _ safeDIBuilder: ((Instantiator<Screen>) -> Second)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            screen: screen,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var screen: __safeDI_Feature_Screen_MockConfiguration { __safeDI_storage.screen }
			    /// Overrides how `Second` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((Instantiator<Screen>) -> Second)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            screen: __safeDI_Feature_Screen_MockConfiguration,
			            safeDIBuilder: ((Instantiator<Screen>) -> Second)?
			        ) {
			            self.screen = screen
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let screen: __safeDI_Feature_Screen_MockConfiguration
			        let safeDIBuilder: ((Instantiator<Screen>) -> Second)?
			    }
			}

			extension Second {
			    static func __safeDI_init(screen: Instantiator<Screen>, safeDIBuilder: ((Instantiator<Screen>) -> Second)?) -> Second {
			        if let safeDIBuilder { safeDIBuilder(screen) } else { Second(screen: screen) }
			    }
			}
			#endif

			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
