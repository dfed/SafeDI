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
@testable import SafeDITool

/// Public mocks (`@Instantiable(generateMock: .public)`): how the macro's argument reaches the tool, and the mock the
/// declaring module generates.
struct SafeDIToolPublicMockTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – the argument

	@Test(arguments: [
		("true", MockGeneration.internal),
		(".internal", .internal),
		("MockGeneration.internal", .internal),
		(".public", .public),
		("MockGeneration.public", .public),
		("false", .none),
		(".none", .none),
		("MockGeneration.none", .none),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_plansMockFile_whenGenerateMockSpellsCaseThatGeneratesOne(spelling: String, mockGeneration: MockGeneration) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: \(spelling))
				public struct Service: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.moduleInfo.instantiables.map(\.generateMock) == [mockGeneration])
		#expect(output.mockFiles.keys.sorted() == (mockGeneration.generatesMock ? ["Service+SafeDIMock.swift"] : []))
	}

	// MARK: Tests – what keeps a public mock from being generated

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicMockedTypeIsNestedInNarrowerType() async {
		// M1.8: the type spells `public`, which the macro accepts, but `Internals` keeps it `internal`.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["X.swift"]):2:33: error: `Internals.X` cannot have a public mock because `Internals` is `internal`. Make `Internals` `public`, or use `generateMock: .internal`.
			\(fixtures["X.swift"]):2:33-2:40: fixit: .internal
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					enum Internals {
					    @Instantiable(generateMock: .public) public struct X: Instantiable {
					        public init() {}
					    }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicMockForwardsPackageType() async {
		// M2.7: a forwarded parameter is required, so a narrower one makes the public tier impossible. Cause (i).
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Feature.swift"]):1:29: error: SafeDI cannot generate the public mock of `Feature`: its `public` tier, which `generateMock: .public` requires, cannot take `user: User`, which `Feature` forwards, and cannot pass `nil` for it, since it is required. `User`'s own `@Instantiable` declaration is `package`. Declare `User` `public`; give `User` a `mockOnly` mock; or use `generateMock: .internal`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: .public)
					public struct Feature: Instantiable {
					    package init(user: User) {
					        self.user = user
					    }

					    @Forwarded let user: User
					}
					""",
					"""
					@Instantiable
					package struct User: Instantiable {
					    package init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicMockedTypeIsDeclaredInUnspelledExtensionOfTypeWithoutEntry() async {
		// M1.25: `Panel` is a non-exact entry inside an unspelled extension of `Feed`, which has no entry, so nothing raises it
		// from `internal`, and its initializer proves `Theme` only at `internal`. Cause (v).
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Panel.swift"]):8:33: error: SafeDI cannot generate the public mock of `Feed.Panel`: its `public` tier, which `generateMock: .public` requires, cannot take `theme: Theme`, which the initializer of `Feed.Panel` receives, and cannot pass `nil` for it, since it is required. `Theme` is `internal` as far as SafeDI can tell: `Feed.Panel` is declared inside an extension of `Feed` that spells no access level, and SafeDI cannot see `Feed`'s, so `Feed.Panel`'s initializer proves its parameter types only at `internal`. If `Feed` can be `public`, spell the extension's access level (`public extension Feed { … }`, dropping the modifier on `Panel` that Swift then reports as redundant; the compiler rejects a level wider than `Feed`'s), or declare `Panel` in `Feed`'s body or at top level; mention `Theme` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; receive it with `onlyIfAvailable: true` and an optional type; widen the declaration that proves the parameter's type; or use `generateMock: .internal`.
			\(fixtures["Panel.swift"]):14:9: note: `Feed.Panel` receives `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public enum Feed {}

					public struct Theme {
					    public init() {}
					}

					extension Feed {
					    @Instantiable(generateMock: .public)
					    public struct Panel: Instantiable {
					        public init(theme: Theme) {
					            self.theme = theme
					        }

					        @Received let theme: Theme
					    }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicMockedTreeReceivesPlainTypeOnlyNarrowerInitializersMention() async {
		// M2.9b, M2.10: a received parameter nothing builds is required. Cause (ii), with a note at the receive.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:29: error: SafeDI cannot generate the public mock of `Service`: its `public` tier, which `generateMock: .public` requires, cannot take `token: Token`, which the initializer of `TokenCache` receives, and cannot pass `nil` for it, since it is required. `Token` is `internal` as far as SafeDI can tell: every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `internal` (`TokenCache.init(token:)`). Mention `Token` in a `public` initializer, `instantiate(…)` or mock method SafeDI records (or widen `Token`'s declaration); receive it with `onlyIfAvailable: true` and an optional type; widen the declaration that proves the parameter's type; or use `generateMock: .internal`.
			\(fixtures["TokenCache.swift"]):7:5: note: `TokenCache` receives `token: Token` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    init(tokenCache: TokenCache) {
					        self.tokenCache = tokenCache
					    }

					    @Instantiated let tokenCache: TokenCache
					}
					""",
					"""
					@Instantiable
					public struct TokenCache: Instantiable {
					    init(token: Token) {
					        self.token = token
					    }

					    @Received let token: Token
					}
					""",
					"public struct Token {\n    public init() {}\n}",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – the parameters of a public mock

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesPublicMockWithNoParameters_whenTypeHasNoDependencies() async throws {
		// M2.16, M3.16: no tree and no default, so no `SafeDIOverrides`; the guard enum still names the signature.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    public init() {}
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
			    public static func mock() -> Service {
			        Service()
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_CBF29CE484222325 {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOptionalDefaultAsParameterWithProvider_whenPublicMockHasNoTree() async throws {
		// M2.16b: no tree, so no `SafeDIOverrides`: the optional-typed default is a parameter that defaults to its
		// provider; the non-optional one is `T? = nil`, resolved in the body; a magic literal is kept (M6.11).
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public enum Defaults {
				    public static let name: String? = "service"
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    public init(name: String? = Defaults.name, retries: Int = 3, onTap: @escaping () -> Void = {}, file: String = #fileID) {}
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
			    @usableFromInline nonisolated static func __safeDI_publicMockDefault_name() -> String? { Defaults.name }

			    public static func mock(
			        name: String? = Service.__safeDI_publicMockDefault_name(),
			        retries: Int? = nil,
			        onTap: (() -> Void)? = nil,
			        file: String = #fileID
			    ) -> Service {
			        let retries = retries ?? (3)
			        let onTap = onTap ?? ({})
			        return Service(name: name, retries: retries, onTap: onTap, file: file)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_39A4AE30EA852266 {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesReceivedDependenciesAsOptionalParameters_whenPublicMockBuildsOrIsHandedThem() async throws {
		// M5.1a, M5.3, M5.4, M2.11, M2.19, M2.20: each received dependency the mock builds is `T? = nil`, an instance
		// winning over the override; one received only if available that nothing provides is a parameter rather than an
		// override; two forms of one label are two parameters named apart; label order. `Token` is internal, so its
		// parameter is on the internal tier only.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    public init(child: Child) {
				        self.child = child
				    }

				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public struct Child: Instantiable {
				    init(zebra: Zebra, apple: Apple, appleBuilder: Instantiator<Apple>, token: Token?) {
				        self.zebra = zebra
				        self.apple = apple
				        self.appleBuilder = appleBuilder
				        self.token = token
				    }

				    @Received let zebra: Zebra
				    @Received let apple: Apple
				    @Received let appleBuilder: Instantiator<Apple>
				    @Received(onlyIfAvailable: true) let token: Token?
				}
				""",
				"@Instantiable\npublic struct Zebra: Instantiable {\n    public init() {}\n}",
				"@Instantiable\npublic struct Apple: Instantiable {\n    public init() {}\n}",
				"struct Token {}",
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
			    public struct SafeDIOverrides {
			        public init(
			            zebra: (() -> Zebra)? = nil,
			            apple: (() -> Apple)? = nil,
			            appleBuilder: (() -> Apple)? = nil
			        ) {
			            self.zebra = zebra
			            self.apple = apple
			            self.appleBuilder = appleBuilder
			            self.child = nil
			        }

			        init(
			            zebra: (() -> Zebra)? = nil,
			            apple: (() -> Apple)? = nil,
			            appleBuilder: (() -> Apple)? = nil,
			            child: ((Zebra, Apple, Instantiator<Apple>, Token?) -> Child)? = nil
			        ) {
			            self.zebra = zebra
			            self.apple = apple
			            self.appleBuilder = appleBuilder
			            self.child = child
			        }

			        public let zebra: (() -> Zebra)?
			        public let apple: (() -> Apple)?
			        public let appleBuilder: (() -> Apple)?
			        let child: ((Zebra, Apple, Instantiator<Apple>, Token?) -> Child)?
			    }

			    public static func mock(
			        apple: Apple? = nil,
			        appleBuilder: Instantiator<Apple>? = nil,
			        zebra: Zebra? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        Service.mock(apple: apple, appleBuilder: appleBuilder, token: nil, zebra: zebra, safeDIOverrides: safeDIOverrides)
			    }

			    static func mock(
			        apple: Apple? = nil,
			        appleBuilder: Instantiator<Apple>? = nil,
			        token: Token? = nil,
			        zebra: Zebra? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let zebra = if let zebra { zebra } else if let safeDIBuilder = safeDIOverrides.zebra { safeDIBuilder() } else { Zebra() }
			        let apple = if let apple { apple } else if let safeDIBuilder = safeDIOverrides.apple { safeDIBuilder() } else { Apple() }
			        func __safeDI_appleBuilder() -> Apple {
			            if let safeDIBuilder = safeDIOverrides.appleBuilder { safeDIBuilder() } else { Apple() }
			        }
			        let appleBuilder = if let appleBuilder { appleBuilder } else { Instantiator<Apple>(__safeDI_appleBuilder) }
			        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(zebra, apple, appleBuilder, token) } else { Child(zebra: zebra, apple: apple, appleBuilder: appleBuilder, token: token) }
			        return Service(child: child)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_C2149D3536A3C96F {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsCustomMockThroughPublicMock_whenTypeNamesCustomMock() async throws {
		// M10.3, M1.12, M6.6: the public mock calls the hand-written `preview`, whose level adds no tier.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public, customMockName: "preview")
				public struct Service: Instantiable {
				    public init(analytics: Analytics) {
				        self.analytics = analytics
				    }

				    static func preview(analytics: Analytics, retries: Int = 3) -> Service {
				        Service(analytics: analytics)
				    }

				    @Received let analytics: Analytics
				}
				""",
				"@Instantiable\npublic struct Analytics: Instantiable {\n    public init() {}\n}",
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
			    public struct SafeDIOverrides {
			        public init(
			            analytics: (() -> Analytics)? = nil
			        ) {
			            self.analytics = analytics
			        }

			        public let analytics: (() -> Analytics)?
			    }

			    public static func mock(
			        retries: Int? = nil,
			        analytics: Analytics? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let retries = retries ?? (3)
			        let analytics = if let analytics { analytics } else if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
			        return Service.preview(analytics: analytics, retries: retries)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_9BEAAC23B11B566D {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesInternalInitializerOnly_whenEveryOverrideIsInternal() async throws {
		// M3.7, M4.4, M4.13: every member of `SafeDIOverrides` is internal, so its public initializer takes nothing; the
		// internal child's configuration is public, its default public, and its builder internal.
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
			public struct __safeDI_Child_MockConfiguration {
			    public init(
			        capacity: Int? = nil
			    ) {
			        self.grand = nil
			        self.capacity = capacity
			        self.safeDIBuilder = nil
			    }

			    init(
			        grand: (() -> Grand)? = nil,
			        capacity: Int? = nil,
			        _ safeDIBuilder: ((Grand, Int) -> Child)? = nil
			    ) {
			        self.grand = grand
			        self.capacity = capacity
			        self.safeDIBuilder = safeDIBuilder
			    }

			    let grand: (() -> Grand)?
			    /// `nil` keeps the default of `Child`'s `capacity`.
			    public let capacity: Int?
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    let safeDIBuilder: ((Grand, Int) -> Child)?
			}

			extension Child {
			    static func __safeDI_init(grand: Grand, capacity: Int?, safeDIBuilder: ((Grand, Int) -> Child)?) -> Child {
			        let capacity = capacity ?? (10)
			        return if let safeDIBuilder { safeDIBuilder(grand, capacity) } else { Child(grand: grand, capacity: capacity) }
			    }
			}
			#endif
			""" + "\n",
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            child: __safeDI_Child_MockConfiguration = .init()
			        ) {
			            self.child = child
			        }

			        public let child: __safeDI_Child_MockConfiguration
			    }

			    public static func mock(
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
	mutating func generate_readsConfiguredChildIntoLocals_whenChildIsBuiltInSendableBuilder() async throws {
		// M4.11, M3.9, M4.23: a configured child beneath a `SendableInstantiator`: its configuration's members are
		// `@Sendable`, read into locals before the `@Sendable` builder function, and passed to the construction function.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
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
				    public init(grand: Grand) {
				        self.grand = grand
				    }

				    @Instantiated let grand: Grand
				}
				""",
				"""
				@Instantiable
				public struct Grand: Instantiable, Sendable {
				    public init(capacity: Int = 10, label: String? = "grand") {}
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
			    public struct SafeDIOverrides {
			        public init(
			            childBuilder: __safeDI_Child_MockConfiguration = .init()
			        ) {
			            self.childBuilder = childBuilder
			        }

			        public let childBuilder: __safeDI_Child_MockConfiguration
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_childBuilder__childBuilder_grand_safeDIBuilder = safeDIOverrides.childBuilder.grand.safeDIBuilder
			        let __safeDI_childBuilder__childBuilder_grand_capacity = safeDIOverrides.childBuilder.grand.capacity
			        let __safeDI_childBuilder__childBuilder_grand_label = safeDIOverrides.childBuilder.grand.label
			        let __safeDI_childBuilder__safeDIBuilder = safeDIOverrides.childBuilder.safeDIBuilder
			        @Sendable func __safeDI_childBuilder() -> Child {
			            func __safeDI_grand() -> Grand {
			                return Grand.__safeDI_init(capacity: __safeDI_childBuilder__childBuilder_grand_capacity(), label: __safeDI_childBuilder__childBuilder_grand_label(), safeDIBuilder: __safeDI_childBuilder__childBuilder_grand_safeDIBuilder)
			            }
			            let grand: Grand = __safeDI_grand()
			            return Child.__safeDI_init(grand: grand, safeDIBuilder: __safeDI_childBuilder__safeDIBuilder)
			        }
			        let childBuilder = SendableInstantiator<Child>(__safeDI_childBuilder)
			        return Root(childBuilder: childBuilder)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Grand` is constructed within the public mock trees of this module.
			public struct __safeDI_Grand_MockConfiguration {
			    public init(
			        capacity: @autoclosure @escaping @Sendable () -> Int? = nil,
			        label: @autoclosure @escaping @Sendable () -> String? = __safeDI_Grand_mockDefault_label(),
			        _ safeDIBuilder: (@Sendable (Int, String?) -> Grand)? = nil
			    ) {
			        self.capacity = capacity
			        self.label = label
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Grand`'s `capacity`.
			    public let capacity: @Sendable () -> Int?
			    /// The default of `Grand`'s `label` unless set.
			    public let label: @Sendable () -> String?
			    /// Overrides how `Grand` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: (@Sendable (Int, String?) -> Grand)?
			}

			extension Grand {
			    nonisolated static func __safeDI_mockDefault_label() -> String? { "grand" }
			    static func __safeDI_init(capacity: Int?, label: String?, safeDIBuilder: (@Sendable (Int, String?) -> Grand)?) -> Grand {
			        let capacity = capacity ?? (10)
			        return if let safeDIBuilder { safeDIBuilder(capacity, label) } else { Grand(capacity: capacity, label: label) }
			    }
			}
			@usableFromInline nonisolated func __safeDI_Grand_mockDefault_label() -> String? { Grand.__safeDI_mockDefault_label() }

			/// Configuration for how `Child` is constructed within the public mock trees of this module.
			public struct __safeDI_Child_MockConfiguration {
			    public init(
			        grand: __safeDI_Grand_MockConfiguration = .init(),
			        _ safeDIBuilder: (@Sendable (Grand) -> Child)? = nil
			    ) {
			        self.grand = grand
			        self.safeDIBuilder = safeDIBuilder
			    }

			    public let grand: __safeDI_Grand_MockConfiguration
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: (@Sendable (Grand) -> Child)?
			}

			extension Child {
			    static func __safeDI_init(grand: Grand, safeDIBuilder: (@Sendable (Grand) -> Child)?) -> Child {
			        if let safeDIBuilder { safeDIBuilder(grand) } else { Child(grand: grand) }
			    }
			}
			#endif
			""" + "\n",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesForwardedTypeAsOptionalParameter_whenItsMockOnlyMockDefaultsIt() async throws {
		// M2.8b: the forwarded `user` defaults to its `package` `mockOnly` mock, so the public tier takes it as `T? = nil`
		// and resolves it in the mock's module, which can call that mock; another package calls the public tier. (M2.8,
		// the same with `User` itself `package`, cannot compile: the macro declares `Feature`'s `ForwardedProperties`
		// `public`, which cannot name a `package` type.)
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
					"""
					@Instantiable(generateMock: .public)
					public struct Feature: Instantiable {
					    package init(user: User, retries: Int = 3) {
					        self.user = user
					    }

					    @Forwarded let user: User
					}
					""",
					"""
					@Instantiable
					public struct User: Instantiable {
					    package init() {}
					}
					""",
					"""
					@Instantiable(mockOnly: true)
					extension User {
					    package static func mock() -> User {
					        User()
					    }
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Caller.swift": "import Core\n\n#if DEBUG\nfunc call() {\n    _ = Feature.mock()\n    _ = Feature.mock(user: nil, retries: 1)\n}\n#endif\n"], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == [
			"Core.swift": generatedFileHeader + """
			#if DEBUG
			extension Feature {
			    public static func mock(
			        user: User? = nil,
			        retries: Int? = nil
			    ) -> Feature {
			        let user = user ?? (User.mock())
			        let retries = retries ?? (3)
			        return Feature(user: user, retries: retries)
			    }
			}

			extension Feature {
			    public enum __safeDI_Feature_mock_FA70A635B61DA184 {}
			}
			#endif
			""",
		])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenConfigurationListsPublicMockOfAnotherModule() async {
		// M12.1: `Core` generates `Service`'s public mock, so `App` calls it rather than generating another.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]?["SafeDIConfiguration.swift"] ?? ""):3:1: error: `Service` already has a public `mock()` generated by `Core`. Remove it from additionalMocksToGenerate and call `Service.mock()`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
						"""
						@Instantiable(generateMock: .public)
						public struct Service: Instantiable {
						    public init() {}
						}
						""",
					]),
					ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: [
						"SafeDIConfiguration.swift": "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Service\"])\n",
					], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func query_throwsError_whenPublicMockCannotTakeRequiredParameter() async {
		// M13.3: whether a public mock can be generated is decided for one root, which the query builds too.
		await assertThrowsQueryError(diagnostics: { moduleFiles in
			"""
			\(moduleFiles["Core"]?.first { $0.lastPathComponent == "Feature.swift" }?.path ?? ""):1:29: error: SafeDI cannot generate the public mock of `Feature`: its `public` tier, which `generateMock: .public` requires, cannot take `user: User`, which `Feature` forwards, and cannot pass `nil` for it, since it is required. `User`'s own `@Instantiable` declaration is `internal`. Declare `User` `public`; give `User` a `mockOnly` mock; or use `generateMock: .internal`.
			"""
		}) {
			try await executeSafeDIToolQuery(
				typeName: "Feature",
				modules: [
					QueryTestModule("Core", [
						"""
						@Instantiable(generateMock: .public)
						public struct Feature: Instantiable {
						    init(user: User) {
						        self.user = user
						    }

						    @Forwarded let user: User
						}
						""",
						"""
						@Instantiable
						struct User: Instantiable {
						    init() {}
						}
						""",
					]),
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_putsMockAttributesOnEveryTier_whenPublicMockedRootHasThem() async throws {
		// M1.6, M2.15: a root with a public mock keeps its generated `init()`, and its attributes go on every tier.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, mockAttributes: "@MainActor", generateMock: .public)
				public struct Root: Instantiable {
				    public init(child: Child) {
				        self.child = child
				    }

				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public struct Child: Instantiable {
				    init(token: Token?) {
				        self.token = token
				    }

				    @Received(onlyIfAvailable: true) let token: Token?
				}
				""",
				"struct Token {}",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let child = Child(token: nil)
			        self.init(child: child)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init() {
			            self.child = nil
			        }

			        init(
			            child: ((Token?) -> Child)? = nil
			        ) {
			            self.child = child
			        }

			        let child: ((Token?) -> Child)?
			    }

			    @MainActor public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        Root.mock(token: nil, safeDIOverrides: safeDIOverrides)
			    }

			    @MainActor static func mock(
			        token: Token? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(token) } else { Child(token: token) }
			        return Root(child: child)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_C173F970333E7425 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesEachKindOfParameter_whenPublicMockedTypeForwardsReceivesAndDefaults() async throws {
		// M2.6, M2.9, M2.12, M2.13, M5.21, M6.2, M15.4: a required forwarded parameter first, a forwarded one with a default as
		// `T? = nil`, an optional forwarded one defaulting to its provider, a required received dependency nothing builds,
		// a builder for an instantiated one nothing fulfills, handed a public scope struct of the values built before it,
		// a received dependency the mock builds through a builder function, an alias in the tree, and an optional default
		// whose default is `nil`, which needs no provider.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    public init(name: String, count: Int = 1, tag: String? = "tag", token: Token, thing: Thing, child: Child, onCancel: (() -> Void)? = nil) {
				        self.name = name
				        self.count = count
				        self.tag = tag
				        self.token = token
				        self.thing = thing
				        self.child = child
				    }

				    @Forwarded let name: String
				    @Forwarded let count: Int
				    @Forwarded let tag: String?
				    @Received let token: Token
				    @Instantiated let thing: Thing
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public struct Child: Instantiable {
				    public init(config: Config, renamed: Config) {
				        self.config = config
				        self.renamed = renamed
				    }

				    @Received let config: Config
				    @Received(fulfilledByDependencyNamed: "config", ofType: Config.self) let renamed: Config
				}
				""",
				"""
				@Instantiable
				public struct Config: Instantiable {
				    public init(capacity: Int = 2) {}
				}
				""",
				"public struct Token {\n    public init() {}\n}",
				"public struct Thing {\n    public init() {}\n}",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Config` is constructed within the public mock trees of this module.
			public struct __safeDI_Config_MockConfiguration {
			    public init(
			        capacity: Int? = nil,
			        _ safeDIBuilder: ((Int) -> Config)? = nil
			    ) {
			        self.capacity = capacity
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Config`'s `capacity`.
			    public let capacity: Int?
			    /// Overrides how `Config` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Int) -> Config)?
			}

			extension Config {
			    static func __safeDI_init(capacity: Int?, safeDIBuilder: ((Int) -> Config)?) -> Config {
			        let capacity = capacity ?? (2)
			        return if let safeDIBuilder { safeDIBuilder(capacity) } else { Config(capacity: capacity) }
			    }
			}
			#endif
			""" + "\n",
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @usableFromInline nonisolated static func __safeDI_publicMockDefault_tag() -> String? { "tag" }

			    public struct SafeDIMockScope_Service_thing {
			        public let config: Config
			        public let child: Child
			    }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            config: __safeDI_Config_MockConfiguration = .init(),
			            child: ((Config, Config) -> Child)? = nil,
			            onCancel: (() -> Void)? = nil
			        ) {
			            self.config = config
			            self.child = child
			            self.onCancel = onCancel
			        }

			        public let config: __safeDI_Config_MockConfiguration
			        public let child: ((Config, Config) -> Child)?
			        /// The value of `Service`'s `onCancel`, `nil` unless set.
			        public let onCancel: (() -> Void)?
			    }

			    public static func mock(
			        count: Int? = nil,
			        name: String,
			        tag: String? = Service.__safeDI_publicMockDefault_tag(),
			        token: Token,
			        thingBuilder: @escaping (Service.SafeDIMockScope_Service_thing) -> Thing,
			        config: Config? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let __safeDI_thingBuilder = thingBuilder
			        let count = count ?? (1)
			        func __safeDI_config() -> Config {
			            return Config.__safeDI_init(capacity: safeDIOverrides.config.capacity, safeDIBuilder: safeDIOverrides.config.safeDIBuilder)
			        }
			        let config: Config = if let config { config } else { __safeDI_config() }
			        func __safeDI_child() -> Child {
			            #sourceLocation(file: "\(output.fixtures.compilerPath(of: "Child.swift"))", line: 9)
			            let renamed: Config = config
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(config, renamed) } else { Child(config: config, renamed: renamed) }
			        }
			        let child: Child = __safeDI_child()
			        let thing: Thing = __safeDI_thingBuilder(SafeDIMockScope_Service_thing(config: config, child: child))
			        return Service(name: name, count: count, tag: tag, token: token, thing: thing, child: child, onCancel: safeDIOverrides.onCancel)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_A8F8A622E86AAF36 {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsConfiguredChildrenThroughConstructionFunctions_whenChildrenAreExtensionBasedOrErased() async throws {
		// M3.6, M4.25, M6.5: an extension-based child's construction function calls `instantiate(…)`; an erased child is
		// wrapped where the mock builds it; an optional default of `nil` needs no provider; and two types whose names
		// read the same as identifiers get configurations named apart, in sorted type order.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Root: Instantiable {
				    public init(shelf: Shelf, service: AnyService, viewModel: Feed.ViewModel, otherViewModel: Feed_ViewModel) {
				        self.shelf = shelf
				        self.service = service
				        self.viewModel = viewModel
				        self.otherViewModel = otherViewModel
				    }

				    @Instantiated let shelf: Shelf
				    @Instantiated(fulfilledByType: "ConcreteService", erasedToConcreteExistential: true) let service: AnyService
				    @Instantiated let viewModel: Feed.ViewModel
				    @Instantiated let otherViewModel: Feed_ViewModel
				}
				""",
				"""
				public struct Shelf {
				    public init() {}
				}

				@Instantiable
				extension Shelf: Instantiable {
				    public static func instantiate(capacity: Int = 3, label: String? = nil) -> Shelf {
				        Shelf()
				    }
				}
				""",
				"""
				public protocol ServiceProtocol {}

				public struct AnyService: ServiceProtocol {
				    public init(_ service: some ServiceProtocol) {}
				}

				@Instantiable
				public struct ConcreteService: ServiceProtocol, Instantiable {
				    public init(retries: Int = 2) {}
				}
				""",
				"""
				public enum Feed {
				    @Instantiable
				    public struct ViewModel: Instantiable {
				        public init(title: String? = "feed") {}
				    }
				}
				""",
				"""
				@Instantiable
				public struct Feed_ViewModel: Instantiable {
				    public init(title: String? = "other") {}
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
			    public struct SafeDIOverrides {
			        public init(
			            shelf: __safeDI_Shelf_MockConfiguration = .init(),
			            service: __safeDI_ConcreteService_MockConfiguration = .init(),
			            viewModel: __safeDI_Feed_ViewModel_MockConfiguration = .init(),
			            otherViewModel: __safeDI_Feed_ViewModel__MockConfiguration = .init()
			        ) {
			            self.shelf = shelf
			            self.service = service
			            self.viewModel = viewModel
			            self.otherViewModel = otherViewModel
			        }

			        public let shelf: __safeDI_Shelf_MockConfiguration
			        public let service: __safeDI_ConcreteService_MockConfiguration
			        public let viewModel: __safeDI_Feed_ViewModel_MockConfiguration
			        public let otherViewModel: __safeDI_Feed_ViewModel__MockConfiguration
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_shelf() -> Shelf {
			            return Shelf.__safeDI_init(capacity: safeDIOverrides.shelf.capacity, label: safeDIOverrides.shelf.label, safeDIBuilder: safeDIOverrides.shelf.safeDIBuilder)
			        }
			        let shelf: Shelf = __safeDI_shelf()
			        func __safeDI_service() -> AnyService {
			            return AnyService(ConcreteService.__safeDI_init(retries: safeDIOverrides.service.retries, safeDIBuilder: safeDIOverrides.service.safeDIBuilder))
			        }
			        let service: AnyService = __safeDI_service()
			        func __safeDI_viewModel() -> Feed.ViewModel {
			            return Feed.ViewModel.__safeDI_init(title: safeDIOverrides.viewModel.title, safeDIBuilder: safeDIOverrides.viewModel.safeDIBuilder)
			        }
			        let viewModel: Feed.ViewModel = __safeDI_viewModel()
			        func __safeDI_otherViewModel() -> Feed_ViewModel {
			            return Feed_ViewModel.__safeDI_init(title: safeDIOverrides.otherViewModel.title, safeDIBuilder: safeDIOverrides.otherViewModel.safeDIBuilder)
			        }
			        let otherViewModel: Feed_ViewModel = __safeDI_otherViewModel()
			        return Root(shelf: shelf, service: service, viewModel: viewModel, otherViewModel: otherViewModel)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Shelf` is constructed within the public mock trees of this module.
			public struct __safeDI_Shelf_MockConfiguration {
			    public init(
			        capacity: Int? = nil,
			        label: String? = nil,
			        _ safeDIBuilder: ((Int, String?) -> Shelf)? = nil
			    ) {
			        self.capacity = capacity
			        self.label = label
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Shelf`'s `capacity`.
			    public let capacity: Int?
			    /// The default of `Shelf`'s `label` unless set.
			    public let label: String?
			    /// Overrides how `Shelf` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Int, String?) -> Shelf)?
			}

			extension Shelf {
			    static func __safeDI_init(capacity: Int?, label: String?, safeDIBuilder: ((Int, String?) -> Shelf)?) -> Shelf {
			        let capacity = capacity ?? (3)
			        return if let safeDIBuilder { safeDIBuilder(capacity, label) } else { Shelf.instantiate(capacity: capacity, label: label) }
			    }
			}

			/// Configuration for how `ConcreteService` is constructed within the public mock trees of this module.
			public struct __safeDI_ConcreteService_MockConfiguration {
			    public init(
			        retries: Int? = nil,
			        _ safeDIBuilder: ((Int) -> ConcreteService)? = nil
			    ) {
			        self.retries = retries
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `ConcreteService`'s `retries`.
			    public let retries: Int?
			    /// Overrides how `ConcreteService` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Int) -> ConcreteService)?
			}

			extension ConcreteService {
			    static func __safeDI_init(retries: Int?, safeDIBuilder: ((Int) -> ConcreteService)?) -> ConcreteService {
			        let retries = retries ?? (2)
			        return if let safeDIBuilder { safeDIBuilder(retries) } else { ConcreteService(retries: retries) }
			    }
			}

			/// Configuration for how `Feed.ViewModel` is constructed within the public mock trees of this module.
			public struct __safeDI_Feed_ViewModel_MockConfiguration {
			    public init(
			        title: String? = __safeDI_Feed_ViewModel_mockDefault_title(),
			        _ safeDIBuilder: ((String?) -> Feed.ViewModel)? = nil
			    ) {
			        self.title = title
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// The default of `Feed.ViewModel`'s `title` unless set.
			    public let title: String?
			    /// Overrides how `Feed.ViewModel` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((String?) -> Feed.ViewModel)?
			}

			extension Feed.ViewModel {
			    nonisolated static func __safeDI_mockDefault_title() -> String? { "feed" }
			    static func __safeDI_init(title: String?, safeDIBuilder: ((String?) -> Feed.ViewModel)?) -> Feed.ViewModel {
			        if let safeDIBuilder { safeDIBuilder(title) } else { Feed.ViewModel(title: title) }
			    }
			}
			@usableFromInline nonisolated func __safeDI_Feed_ViewModel_mockDefault_title() -> String? { Feed.ViewModel.__safeDI_mockDefault_title() }

			/// Configuration for how `Feed_ViewModel` is constructed within the public mock trees of this module.
			public struct __safeDI_Feed_ViewModel__MockConfiguration {
			    public init(
			        title: String? = __safeDI_Feed_ViewModel__mockDefault_title(),
			        _ safeDIBuilder: ((String?) -> Feed_ViewModel)? = nil
			    ) {
			        self.title = title
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// The default of `Feed_ViewModel`'s `title` unless set.
			    public let title: String?
			    /// Overrides how `Feed_ViewModel` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((String?) -> Feed_ViewModel)?
			}

			extension Feed_ViewModel {
			    nonisolated static func __safeDI_mockDefault_title() -> String? { "other" }
			    static func __safeDI_init(title: String?, safeDIBuilder: ((String?) -> Feed_ViewModel)?) -> Feed_ViewModel {
			        if let safeDIBuilder { safeDIBuilder(title) } else { Feed_ViewModel(title: title) }
			    }
			}
			@usableFromInline nonisolated func __safeDI_Feed_ViewModel__mockDefault_title() -> String? { Feed_ViewModel.__safeDI_mockDefault_title() }
			#endif
			""" + "\n",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilAndProviders_whenConfiguredTypeIsBuiltBeneathCycleEdge() async throws {
		// M4.10: `B` -> `A` is the cycle edge, so the `A` that `A`'s public mock builds beneath `B` reads no configuration: it passes
		// `nil` for each non-optional default, which its construction function resolves, and the provider's value for the
		// optional one.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct A: Instantiable {
				    public init(bBuilder: Instantiator<B>, label: String = "a", tag: String? = "tag") {
				        self.bBuilder = bBuilder
				    }

				    @Instantiated let bBuilder: Instantiator<B>
				}
				""",
				"""
				@Instantiable
				public struct B: Instantiable {
				    public init(aBuilder: Instantiator<A>) {
				        self.aBuilder = aBuilder
				    }

				    @Instantiated let aBuilder: Instantiator<A>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    @usableFromInline nonisolated static func __safeDI_publicMockDefault_tag() -> String? { "tag" }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            bBuilder: __safeDI_B_MockConfiguration = .init(),
			            tag: String? = A.__safeDI_publicMockDefault_tag()
			        ) {
			            self.bBuilder = bBuilder
			            self.tag = tag
			        }

			        public let bBuilder: __safeDI_B_MockConfiguration
			        /// The default of `A`'s `tag` unless set; `.init(tag: nil)` passes `nil`.
			        public let tag: String?
			    }

			    public static func mock(
			        label: String? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        let label = label ?? ("a")
			        func __safeDI_bBuilder() -> B {
			            func __safeDI_aBuilder() -> A {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return A.__safeDI_init(bBuilder: bBuilder, label: nil, tag: A.__safeDI_mockDefault_tag(), safeDIBuilder: nil)
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B.__safeDI_init(aBuilder: aBuilder, safeDIBuilder: safeDIOverrides.bBuilder.safeDIBuilder)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return A(bBuilder: bBuilder, label: label, tag: safeDIOverrides.tag)
			    }
			}

			extension A {
			    public enum __safeDI_A_mock_C0F16A51E96B1930 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `A` is constructed within the public mock trees of this module.
			public struct __safeDI_A_MockConfiguration {
			    public init(
			        bBuilder: __safeDI_B_MockConfiguration = .init(),
			        label: String? = nil,
			        tag: String? = __safeDI_A_mockDefault_tag(),
			        _ safeDIBuilder: ((Instantiator<B>, String, String?) -> A)? = nil
			    ) {
			        self.bBuilder = bBuilder
			        self.label = label
			        self.tag = tag
			        self.safeDIBuilder = safeDIBuilder
			    }

			    public let bBuilder: __safeDI_B_MockConfiguration
			    /// `nil` keeps the default of `A`'s `label`.
			    public let label: String?
			    /// The default of `A`'s `tag` unless set.
			    public let tag: String?
			    /// Overrides how `A` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Instantiator<B>, String, String?) -> A)?
			}

			extension A {
			    nonisolated static func __safeDI_mockDefault_tag() -> String? { "tag" }
			    static func __safeDI_init(bBuilder: Instantiator<B>, label: String?, tag: String?, safeDIBuilder: ((Instantiator<B>, String, String?) -> A)?) -> A {
			        let label = label ?? ("a")
			        return if let safeDIBuilder { safeDIBuilder(bBuilder, label, tag) } else { A(bBuilder: bBuilder, label: label, tag: tag) }
			    }
			}
			@usableFromInline nonisolated func __safeDI_A_mockDefault_tag() -> String? { A.__safeDI_mockDefault_tag() }

			/// Configuration for how `B` is constructed within the public mock trees of this module.
			public struct __safeDI_B_MockConfiguration {
			    public init(
			        _ safeDIBuilder: ((Instantiator<A>) -> B)? = nil
			    ) {
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// Overrides how `B` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Instantiator<A>) -> B)?
			}

			extension B {
			    static func __safeDI_init(aBuilder: Instantiator<A>, safeDIBuilder: ((Instantiator<A>) -> B)?) -> B {
			        if let safeDIBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			    }
			}
			#endif
			""" + "\n",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesStagedBuilderForHole_whenHoleIsBuiltInSendableBuilderFunction() async throws {
		// M7.4: a hole beneath a `SendableInstantiator` takes a staged builder, as a seam's does (decision 22): the mock
		// calls its first stage before the `@Sendable` builder function, which calls the stage it returns.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
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
				    public init(thing: Thing) {
				        self.thing = thing
				    }

				    @Instantiated let thing: Thing
				}
				""",
				"public struct Thing: Sendable {\n    public init() {}\n}",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    public enum SafeDIMockScope_Child_thing {
			        public struct Outer {}

			        public struct Inner {}
			    }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            childBuilder: (@Sendable (Thing) -> Child)? = nil
			        ) {
			            self.childBuilder = childBuilder
			        }

			        public let childBuilder: (@Sendable (Thing) -> Child)?
			    }

			    public static func mock(
			        thingBuilder: @escaping (Root.SafeDIMockScope_Child_thing.Outer) -> @Sendable (Root.SafeDIMockScope_Child_thing.Inner) -> Thing,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_thingBuilder = thingBuilder
			        let __safeDI_childBuilder__safeDIBuilder = safeDIOverrides.childBuilder
			        let __safeDI_thingBuilder_Inner = __safeDI_thingBuilder(SafeDIMockScope_Child_thing.Outer())
			        @Sendable func __safeDI_childBuilder() -> Child {
			            let thing: Thing = __safeDI_thingBuilder_Inner(SafeDIMockScope_Child_thing.Inner())
			            return if let safeDIBuilder = __safeDI_childBuilder__safeDIBuilder { safeDIBuilder(thing) } else { Child(thing: thing) }
			        }
			        let childBuilder = SendableInstantiator<Child>(__safeDI_childBuilder)
			        return Root(childBuilder: childBuilder)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_5EDA71B603D3203D {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenRequiredReceivedParameterAndHoleAreNarrower() async {
		// M2.9b with two receivers, and M7.1b's hole whose type is narrower: each is reported, with a note at each receive or
		// instantiation.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:29: error: SafeDI cannot generate the public mock of `Service`: its `public` tier, which `generateMock: .public` requires, cannot take `thingBuilder`, which returns `Thing` for the hole `thing`, and cannot pass `nil` for it, since it is required. `Thing` is `internal` as far as SafeDI can tell: every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `internal` (`Service.init(left:right:thing:)`). Mention `Thing` in a `public` initializer, `instantiate(…)` or mock method SafeDI records (or widen `Thing`'s declaration); widen the declaration that proves the parameter's type; or use `generateMock: .internal`.
			\(fixtures["Service.swift"]):10:5: note: `Service` instantiates `thing: Thing` here.
			\(fixtures["Service.swift"]):1:29: error: SafeDI cannot generate the public mock of `Service`: its `public` tier, which `generateMock: .public` requires, cannot take `token: Token`, which the initializers of `Left` and `Right` receive, and cannot pass `nil` for it, since it is required. `Token` is `internal` as far as SafeDI can tell: every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `internal` (`Left.init(token:)`, `Right.init(token:)`). Mention `Token` in a `public` initializer, `instantiate(…)` or mock method SafeDI records (or widen `Token`'s declaration); receive it with `onlyIfAvailable: true` and an optional type; widen the declaration that proves the parameter's type; or use `generateMock: .internal`.
			\(fixtures["Left.swift"]):7:5: note: `Left` receives `token: Token` here.
			\(fixtures["Right.swift"]):7:5: note: `Right` receives `token: Token` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    init(left: Left, right: Right, thing: Thing) {
					        self.left = left
					        self.right = right
					        self.thing = thing
					    }

					    @Instantiated let left: Left
					    @Instantiated let thing: Thing
					    @Instantiated let right: Right
					}
					""",
					"""
					@Instantiable
					public struct Left: Instantiable {
					    init(token: Token) {
					        self.token = token
					    }

					    @Received let token: Token
					}
					""",
					"""
					@Instantiable
					public struct Right: Instantiable {
					    init(token: Token) {
					        self.token = token
					    }

					    @Received let token: Token
					}
					""",
					"struct Token {}",
					"struct Thing {}",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – the canonical fixture

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesPublicAndPackageTiers_whenCanonicalServiceTakesPackageParameter() async throws {
		// M2.2, M3.14, M3.18, M3.18b, M4.1, M4.2, M5.5, M5.3, M6.1, M6.3, M6.3b: the canonical `Service`. Its public tier
		// omits the package `session`, which its package tier takes; `name` and `policy` are fields of `SafeDIOverrides`,
		// `policy` internal since only a default-valued argument names `Policy`; another package calls the public tier.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.canonicalModules(appCaller: Self.canonicalAppCaller),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == [
			"Core.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Dashboard {
			    @usableFromInline @MainActor static func __safeDI_publicMockDefault_label() -> String? { Defaults.label }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            vm: __safeDI_Core_ViewModel_MockConfiguration = .init()
			        ) {
			            self.vm = vm
			        }

			        public let vm: __safeDI_Core_ViewModel_MockConfiguration
			    }

			    public static func mock(
			        label: String? = Dashboard.__safeDI_publicMockDefault_label(),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Dashboard {
			        func __safeDI_vm() -> ViewModel {
			            return ViewModel.__safeDI_init(title: safeDIOverrides.vm.title, safeDIBuilder: safeDIOverrides.vm.safeDIBuilder)
			        }
			        let vm: ViewModel = __safeDI_vm()
			        return Dashboard(vm: vm, label: label)
			    }
			}

			extension Dashboard {
			    public enum __safeDI_Dashboard_mock_81EB86AE43991940 {}
			}
			#endif

			#if DEBUG
			extension Service {
			    @usableFromInline nonisolated static func __safeDI_publicMockDefault_name() -> String? { Defaults.name }
			    nonisolated static func __safeDI_publicMockDefault_policy() -> Policy? { Defaults.policy }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            logger: __safeDI_Core_FakeLogger_MockConfiguration = .init(),
			            analytics: (() -> Analytics)? = nil,
			            tokenCache: __safeDI_Core_TokenCache_MockConfiguration = .init(),
			            name: String? = Service.__safeDI_publicMockDefault_name()
			        ) {
			            self.logger = logger
			            self.analytics = analytics
			            self.session = nil
			            self.tokenCache = tokenCache
			            self.name = name
			            self.policy = Service.__safeDI_publicMockDefault_policy()
			        }

			        package init(
			            logger: __safeDI_Core_FakeLogger_MockConfiguration = .init(),
			            analytics: (() -> Analytics)? = nil,
			            session: (() -> Session)? = nil,
			            tokenCache: __safeDI_Core_TokenCache_MockConfiguration = .init(),
			            name: String? = Service.__safeDI_publicMockDefault_name()
			        ) {
			            self.logger = logger
			            self.analytics = analytics
			            self.session = session
			            self.tokenCache = tokenCache
			            self.name = name
			            self.policy = Service.__safeDI_publicMockDefault_policy()
			        }

			        init(
			            logger: __safeDI_Core_FakeLogger_MockConfiguration = .init(),
			            analytics: (() -> Analytics)? = nil,
			            session: (() -> Session)? = nil,
			            tokenCache: __safeDI_Core_TokenCache_MockConfiguration = .init(),
			            name: String? = Service.__safeDI_publicMockDefault_name(),
			            policy: Policy? = Service.__safeDI_publicMockDefault_policy()
			        ) {
			            self.logger = logger
			            self.analytics = analytics
			            self.session = session
			            self.tokenCache = tokenCache
			            self.name = name
			            self.policy = policy
			        }

			        public let logger: __safeDI_Core_FakeLogger_MockConfiguration
			        public let analytics: (() -> Analytics)?
			        package let session: (() -> Session)?
			        public let tokenCache: __safeDI_Core_TokenCache_MockConfiguration
			        /// The default of `Service`'s `name` unless set; `.init(name: nil)` passes `nil`.
			        public let name: String?
			        /// The default of `Service`'s `policy` unless set; `.init(policy: nil)` passes `nil`.
			        let policy: Policy?
			    }

			    public static func mock(
			        retries: Int? = nil,
			        analytics: Analytics? = nil,
			        theme: Theme? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        Service.mock(retries: retries, analytics: analytics, session: nil, theme: theme, safeDIOverrides: safeDIOverrides)
			    }

			    package static func mock(
			        retries: Int? = nil,
			        analytics: Analytics? = nil,
			        session: Session? = nil,
			        theme: Theme? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let retries = retries ?? (3)
			        func __safeDI_logger() -> Logger {
			            return FakeLogger.__safeDI_mock(verbose: safeDIOverrides.logger.verbose, safeDIBuilder: safeDIOverrides.logger.safeDIBuilder)
			        }
			        let logger: Logger = __safeDI_logger()
			        func __safeDI_analytics() -> Analytics {
			            if let analytics { analytics } else if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
			        }
			        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
			        let session = if let session { session } else if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        func __safeDI_tokenCache() -> TokenCache {
			            return TokenCache.__safeDI_init(analytics: analytics.instance, session: session, theme: theme, capacity: safeDIOverrides.tokenCache.capacity, safeDIBuilder: safeDIOverrides.tokenCache.safeDIBuilder)
			        }
			        let tokenCache: TokenCache = __safeDI_tokenCache()
			        return Service(analytics: analytics, logger: logger, tokenCache: tokenCache, retries: retries, name: safeDIOverrides.name, policy: safeDIOverrides.policy)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_209346FEA041FD20 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `ViewModel` is constructed within the public mock trees of module `Core`.
			public struct __safeDI_Core_ViewModel_MockConfiguration {
			    public init(
			        title: String? = __safeDI_Core_ViewModel_mockDefault_title()
			    ) {
			        self.title = title
			        self.safeDIBuilder = nil
			    }

			    package init(
			        title: String? = __safeDI_Core_ViewModel_mockDefault_title(),
			        _ safeDIBuilder: ((String?) -> ViewModel)? = nil
			    ) {
			        self.title = title
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// The default of `ViewModel`'s `title` unless set.
			    public let title: String?
			    /// Overrides how `ViewModel` is constructed. Parameters match the type’s initializer or custom mock method.
			    package let safeDIBuilder: ((String?) -> ViewModel)?
			}

			extension ViewModel {
			    nonisolated static func __safeDI_mockDefault_title() -> String? { defaultTitle }
			    static func __safeDI_init(title: String?, safeDIBuilder: ((String?) -> ViewModel)?) -> ViewModel {
			        if let safeDIBuilder { safeDIBuilder(title) } else { ViewModel(title: title) }
			    }
			}
			@usableFromInline nonisolated func __safeDI_Core_ViewModel_mockDefault_title() -> String? { ViewModel.__safeDI_mockDefault_title() }

			/// Configuration for how `FakeLogger` is constructed within the public mock trees of module `Core`.
			public struct __safeDI_Core_FakeLogger_MockConfiguration {
			    public init(
			        verbose: Bool? = nil
			    ) {
			        self.verbose = verbose
			        self.safeDIBuilder = nil
			    }

			    package init(
			        verbose: Bool? = nil,
			        _ safeDIBuilder: ((Bool) -> FakeLogger)? = nil
			    ) {
			        self.verbose = verbose
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `FakeLogger`'s `verbose`.
			    public let verbose: Bool?
			    /// Overrides how `FakeLogger` is constructed. Parameters match the type’s initializer or custom mock method.
			    package let safeDIBuilder: ((Bool) -> FakeLogger)?
			}

			extension FakeLogger {
			    static func __safeDI_mock(verbose: Bool?, safeDIBuilder: ((Bool) -> FakeLogger)?) -> Logger {
			        let verbose = verbose ?? (false)
			        return if let safeDIBuilder { safeDIBuilder(verbose) } else { FakeLogger.mock(verbose: verbose) }
			    }
			}

			/// Configuration for how `TokenCache` is constructed within the public mock trees of module `Core`.
			public struct __safeDI_Core_TokenCache_MockConfiguration {
			    public init(
			        capacity: Int? = nil
			    ) {
			        self.capacity = capacity
			        self.safeDIBuilder = nil
			    }

			    package init(
			        capacity: Int? = nil,
			        _ safeDIBuilder: ((Analytics, Session, Theme?, Int) -> TokenCache)? = nil
			    ) {
			        self.capacity = capacity
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `TokenCache`'s `capacity`.
			    public let capacity: Int?
			    /// Overrides how `TokenCache` is constructed. Parameters match the type’s initializer or custom mock method.
			    package let safeDIBuilder: ((Analytics, Session, Theme?, Int) -> TokenCache)?
			}

			extension TokenCache {
			    static func __safeDI_init(analytics: Analytics, session: Session, theme: Theme?, capacity: Int?, safeDIBuilder: ((Analytics, Session, Theme?, Int) -> TokenCache)?) -> TokenCache {
			        let capacity = capacity ?? (defaultCapacity)
			        return if let safeDIBuilder { safeDIBuilder(analytics, session, theme, capacity) } else { TokenCache(analytics: analytics, session: session, theme: theme, capacity: capacity) }
			    }
			}
			#endif
			""" + "\n",
		])
		try expectEveryModuleCompiled(output)
		// The public mocks build what `Core`'s internal mocks of the same declarations build.
		try await expectValuesAgreeWithInlineMocks(of: Self.canonicalModules(appCaller: Self.canonicalAppCaller).filter { $0.name == "Core" }, output: output, probes: [DifferentialValueProbe("Service.mock()"), DifferentialValueProbe("Dashboard.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_defaultsClosureLiteralThroughProvider_whenOptionalClosureDefaultIsReachedThroughSendableInstantiatorInPublicMock() async throws {
		// The public twin of #529's cell: a closure literal default of a type built beneath a `SendableInstantiator` is a
		// `@Sendable` autoclosure member of the type's configuration, which defaults to the forwarder of the provider that
		// evaluates the literal, so no literal is ever the autoclosure itself.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Root: Instantiable {
				    public init(childBuilder: SendableInstantiator<Child>) { self.childBuilder = childBuilder }
				    @Instantiated let childBuilder: SendableInstantiator<Child>
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(onTap: (() -> Void)? = {}) { self.onTap = onTap }
				    public let onTap: (() -> Void)?
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
			    public struct SafeDIOverrides {
			        public init(
			            childBuilder: __safeDI_Child_MockConfiguration = .init()
			        ) {
			            self.childBuilder = childBuilder
			        }

			        public let childBuilder: __safeDI_Child_MockConfiguration
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_childBuilder__childBuilder_onTap = safeDIOverrides.childBuilder.onTap
			        let __safeDI_childBuilder__safeDIBuilder = safeDIOverrides.childBuilder.safeDIBuilder
			        @Sendable func __safeDI_childBuilder() -> Child {
			            Child.__safeDI_init(onTap: __safeDI_childBuilder__childBuilder_onTap(), safeDIBuilder: __safeDI_childBuilder__safeDIBuilder)
			        }
			        let childBuilder = SendableInstantiator<Child>(__safeDI_childBuilder)
			        return Root(childBuilder: childBuilder)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Child` is constructed within the public mock trees of this module.
			public struct __safeDI_Child_MockConfiguration {
			    public init(
			        onTap: @autoclosure @escaping @Sendable () -> (() -> Void)? = __safeDI_Child_mockDefault_onTap(),
			        _ safeDIBuilder: (@Sendable ((() -> Void)?) -> Child)? = nil
			    ) {
			        self.onTap = onTap
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// The default of `Child`'s `onTap` unless set.
			    public let onTap: @Sendable () -> (() -> Void)?
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: (@Sendable ((() -> Void)?) -> Child)?
			}

			extension Child {
			    nonisolated static func __safeDI_mockDefault_onTap() -> (() -> Void)? { {} }
			    static func __safeDI_init(onTap: (() -> Void)?, safeDIBuilder: (@Sendable ((() -> Void)?) -> Child)?) -> Child {
			        if let safeDIBuilder { safeDIBuilder(onTap) } else { Child(onTap: onTap) }
			    }
			}
			@usableFromInline nonisolated func __safeDI_Child_mockDefault_onTap() -> (() -> Void)? { Child.__safeDI_mockDefault_onTap() }
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesStandardTypedParameterOnPublicTier_whenOnlyPackageInitializerMentionsIt() async throws {
		// The allowlist proves `Result`, `Data` and `Error` `public`, so the required parameter is on the public tier
		// although only an `internal` initializer mentions its type.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				import Foundation

				@Instantiable(generateMock: .public)
				public struct Loader: Instantiable {
				    init(outcome: Result<Data, any Error>) {
				        self.outcome = outcome
				    }

				    @Received let outcome: Result<Data, any Error>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		let imports = """
		#if canImport(Foundation)
		import Foundation
		#endif
		"""
		#expect(output.generatedFiles == [
			"Loader+SafeDIMock.swift": generatedFileHeader + imports + """


			#if DEBUG
			extension Loader {
			    public static func mock(
			        outcome: Result<Data, any Error>
			    ) -> Loader {
			        return Loader(outcome: outcome)
			    }
			}

			extension Loader {
			    public enum __safeDI_Loader_mock_78C8E153D4A0F201 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + imports + "\n\n",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOwnOptionalDefaultsAsParametersWithIsolatedProviders_whenTypeIsBoundToGlobalActor() async throws {
		// M6.3b: `Dashboard` is bound to the main actor, so its `mock()` is, and its own optional default reads the actor's
		// state, as an internal mock's parameter default may. The default is a parameter of `mock()` whose provider shares
		// its isolation, never a field of the nonisolated `SafeDIOverrides` initializer, whose default could not call it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public struct Theme: Instantiable {
				    public init() {}
				}
				""",
				"""
				@MainActor
				@Instantiable(generateMock: .public)
				public struct Dashboard: Instantiable {
				    static var defaultLabel: String? = "label"

				    init(theme: Theme, label: String? = defaultLabel) {
				        self.theme = theme
				    }

				    @Instantiated let theme: Theme
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Dashboard+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Dashboard {
			    @usableFromInline @MainActor static func __safeDI_publicMockDefault_label() -> String? { defaultLabel }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            theme: (() -> Theme)? = nil
			        ) {
			            self.theme = theme
			        }

			        public let theme: (() -> Theme)?
			    }

			    public static func mock(
			        label: String? = Dashboard.__safeDI_publicMockDefault_label(),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Dashboard {
			        let theme = if let safeDIBuilder = safeDIOverrides.theme { safeDIBuilder() } else { Theme() }
			        return Dashboard(theme: theme, label: label)
			    }
			}

			extension Dashboard {
			    public enum __safeDI_Dashboard_mock_81EB86AE43991940 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_isolatesProviderOfOwnOptionalDefault_whenMockAttributesBindMockToGlobalActor() async throws {
		// M2.16b, M6.3b: `mockAttributes` binds the mock of `NoTree`, whose initializer is bound to the main actor, so the
		// provider of its default, which reads the actor's state, is bound to it too.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				enum Defaults {
				    static var name: String? = "name"
				}

				@Instantiable(mockAttributes: "@MainActor", generateMock: .public)
				public final class NoTree: Instantiable {
				    @MainActor init(name: String? = Defaults.name) {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"NoTree+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension NoTree {
			    @usableFromInline @MainActor static func __safeDI_publicMockDefault_name() -> String? { Defaults.name }

			    @MainActor public static func mock(
			        name: String? = NoTree.__safeDI_publicMockDefault_name()
			    ) -> NoTree {
			        return NoTree(name: name)
			    }
			}

			extension NoTree {
			    public enum __safeDI_NoTree_mock_9B791E5044AD415C {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsEveryParameterKindInEachSpelling_whenPublicMockedTypeTakesSpellingAxisFixture() async throws {
		// M15.11, R15's primary cell: closures, `@Sendable` closures, an optional closure, a tuple, an array, an existential,
		// a nested type, a closure typealias, another module's type and a plain public type, as forwarded, received,
		// only-if-available and default-valued parameters, override members and configuration fields. Another package
		// calls both tiers it can reach.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Base", packageName: "pkg", swiftFileContentByFilePath: ["Analytics.swift": """
				import SafeDI

				@Instantiable
				public final class Analytics: Instantiable, Sendable {
				    public init() {}
				}

				/// A plain public type of another module, not `@Instantiable`.
				public struct BaseTheme: Sendable {
				    public init() {}
				}
				"""]),
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: [
					"Badge.swift": """
					import Base
					import SafeDI

					/// A public receiver outside the mocked tree whose public initializer mentions the types only package
					/// initializers would otherwise mention, so they are proven public.
					@Instantiable
					public struct Badge: Instantiable {
					    public init(auth: any Auth, theme: Theme, baseTheme: BaseTheme) {
					        self.auth = auth
					        self.theme = theme
					        self.baseTheme = baseTheme
					    }

					    @Received let auth: any Auth
					    @Received let theme: Theme
					    @Received let baseTheme: BaseTheme
					}
					""",
					"Leaf.swift": """
					import Base
					import SafeDI

					@Instantiable
					public struct Leaf: Instantiable {
					    package init(
					        onTap: @escaping () -> Void,
					        sendableTap: @escaping @Sendable () -> Void,
					        pair: (Int, Bool),
					        theme: Theme,
					        baseTheme: BaseTheme,
					        auth: any Auth,
					        inner: Outer.Inner,
					        analytics: Analytics,
					        sessionBuilder: Instantiator<Session>,
					        onDismiss: (() -> Void)?,
					        handler: Handler?,
					        optionalAuth: (any Auth)?,
					        capacity: Int = 10,
					        onDone: @escaping () -> Void = {},
					        names: [String] = [],
					        label: String? = "leaf"
					    ) {
					        self.onTap = onTap
					        self.sendableTap = sendableTap
					        self.pair = pair
					        self.theme = theme
					        self.baseTheme = baseTheme
					        self.auth = auth
					        self.inner = inner
					        self.analytics = analytics
					        self.sessionBuilder = sessionBuilder
					        self.onDismiss = onDismiss
					        self.handler = handler
					        self.optionalAuth = optionalAuth
					    }

					    @Received let onTap: () -> Void
					    @Received let sendableTap: @Sendable () -> Void
					    @Received let pair: (Int, Bool)
					    @Received let theme: Theme
					    @Received let baseTheme: BaseTheme
					    @Received let auth: any Auth
					    @Received let inner: Outer.Inner
					    @Received let analytics: Analytics
					    @Received let sessionBuilder: Instantiator<Session>
					    @Received(onlyIfAvailable: true) let onDismiss: (() -> Void)?
					    @Received(onlyIfAvailable: true) let handler: Handler?
					    @Received(onlyIfAvailable: true) let optionalAuth: (any Auth)?
					}
					""",
					"Service.swift": """
					import Base
					import SafeDI

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    package init(
					        onSelect: @escaping (String) -> Void,
					        sendableSelect: @escaping @Sendable () -> Void,
					        size: (Int, Int),
					        tags: [String],
					        inner2: Outer.Inner,
					        leaf: Leaf,
					        retries: Int = 3,
					        onFinish: @escaping () -> Void = {},
					        title: String? = "service",
					        onCancel: (() -> Void)? = nil
					    ) {
					        self.onSelect = onSelect
					        self.sendableSelect = sendableSelect
					        self.size = size
					        self.tags = tags
					        self.inner2 = inner2
					        self.leaf = leaf
					    }

					    @Forwarded let onSelect: (String) -> Void
					    @Forwarded let sendableSelect: @Sendable () -> Void
					    @Forwarded let size: (Int, Int)
					    @Forwarded let tags: [String]
					    @Forwarded let inner2: Outer.Inner
					    @Instantiated let leaf: Leaf
					}
					""",
					"Types.swift": """
					import Base
					import SafeDI

					public protocol Auth {}

					@Instantiable(fulfillingAdditionalTypes: [Auth.self])
					public struct DefaultAuth: Auth, Instantiable {
					    public init() {}
					}

					public typealias Handler = (String) -> Bool

					public enum Outer {
					    @Instantiable
					    public struct Inner: Instantiable {
					        public init() {}
					    }
					}

					@Instantiable
					public struct Session: Instantiable {
					    public init() {}
					}

					/// A plain public type, not `@Instantiable`.
					public struct Theme {
					    public init() {}
					}
					""",
				], dependencies: ["Base"]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["AppCaller.swift": """
				import Base
				import Core
				import SafeDI

				#if DEBUG
				func callPublicTier() {
				    _ = Service.mock(inner2: Outer.Inner(), onSelect: { _ in }, sendableSelect: {}, size: (1, 2), tags: [], baseTheme: BaseTheme(), onTap: {}, pair: (1, true), sendableTap: {}, theme: Theme())
				    _ = Service.mock(
				        inner2: Outer.Inner(), onSelect: { _ in }, sendableSelect: {}, size: (1, 2), tags: ["a"],
				        retries: 9, onFinish: {}, baseTheme: BaseTheme(), onTap: {}, pair: (1, true), sendableTap: {}, theme: Theme(),
				        analytics: Analytics(), auth: DefaultAuth(), inner: Outer.Inner(), onDismiss: {}, optionalAuth: DefaultAuth(),
				        sessionBuilder: Instantiator<Session> { Session() },
				        safeDIOverrides: .init(auth: { DefaultAuth() }, leaf: .init(capacity: 3, onDone: {}, names: ["n"], label: nil), title: nil, onCancel: {})
				    )
				}
				#endif
				"""], dependencies: ["Base", "Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(Base)
		import Base
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Service {
		    @usableFromInline nonisolated static func __safeDI_publicMockDefault_title() -> String? { "service" }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            auth: (() -> Auth)? = nil,
		            inner: (() -> Outer.Inner)? = nil,
		            analytics: (() -> Analytics)? = nil,
		            sessionBuilder: (() -> Session)? = nil,
		            leaf: __safeDI_Core_Leaf_MockConfiguration = .init(),
		            title: String? = Service.__safeDI_publicMockDefault_title(),
		            onCancel: (() -> Void)? = nil
		        ) {
		            self.auth = auth
		            self.inner = inner
		            self.analytics = analytics
		            self.sessionBuilder = sessionBuilder
		            self.leaf = leaf
		            self.title = title
		            self.onCancel = onCancel
		        }

		        public let auth: (() -> Auth)?
		        public let inner: (() -> Outer.Inner)?
		        public let analytics: (() -> Analytics)?
		        public let sessionBuilder: (() -> Session)?
		        public let leaf: __safeDI_Core_Leaf_MockConfiguration
		        /// The default of `Service`'s `title` unless set; `.init(title: nil)` passes `nil`.
		        public let title: String?
		        /// The value of `Service`'s `onCancel`, `nil` unless set.
		        public let onCancel: (() -> Void)?
		    }

		    public static func mock(
		        inner2: Outer.Inner,
		        onSelect: @escaping (String) -> Void,
		        sendableSelect: @escaping @Sendable () -> Void,
		        size: (Int, Int),
		        tags: [String],
		        retries: Int? = nil,
		        onFinish: (() -> Void)? = nil,
		        baseTheme: BaseTheme,
		        onTap: @escaping () -> Void,
		        pair: (Int, Bool),
		        sendableTap: @escaping @Sendable () -> Void,
		        theme: Theme,
		        analytics: Analytics? = nil,
		        auth: (any Auth)? = nil,
		        inner: Outer.Inner? = nil,
		        onDismiss: (() -> Void)? = nil,
		        optionalAuth: (any Auth)? = nil,
		        sessionBuilder: Instantiator<Session>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        Service.mock(inner2: inner2, onSelect: onSelect, sendableSelect: sendableSelect, size: size, tags: tags, retries: retries, onFinish: onFinish, baseTheme: baseTheme, onTap: onTap, pair: pair, sendableTap: sendableTap, theme: theme, analytics: analytics, auth: auth, handler: nil, inner: inner, onDismiss: onDismiss, optionalAuth: optionalAuth, sessionBuilder: sessionBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    package static func mock(
		        inner2: Outer.Inner,
		        onSelect: @escaping (String) -> Void,
		        sendableSelect: @escaping @Sendable () -> Void,
		        size: (Int, Int),
		        tags: [String],
		        retries: Int? = nil,
		        onFinish: (() -> Void)? = nil,
		        baseTheme: BaseTheme,
		        onTap: @escaping () -> Void,
		        pair: (Int, Bool),
		        sendableTap: @escaping @Sendable () -> Void,
		        theme: Theme,
		        analytics: Analytics? = nil,
		        auth: (any Auth)? = nil,
		        handler: Handler? = nil,
		        inner: Outer.Inner? = nil,
		        onDismiss: (() -> Void)? = nil,
		        optionalAuth: (any Auth)? = nil,
		        sessionBuilder: Instantiator<Session>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        let retries = retries ?? (3)
		        let onFinish = onFinish ?? ({})
		        let auth: Auth = if let auth { auth } else if let safeDIBuilder = safeDIOverrides.auth { safeDIBuilder() } else { DefaultAuth() }
		        let inner = if let inner { inner } else if let safeDIBuilder = safeDIOverrides.inner { safeDIBuilder() } else { Outer.Inner() }
		        let analytics = if let analytics { analytics } else if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_sessionBuilder() -> Session {
		            if let safeDIBuilder = safeDIOverrides.sessionBuilder { safeDIBuilder() } else { Session() }
		        }
		        let sessionBuilder = if let sessionBuilder { sessionBuilder } else { Instantiator<Session>(__safeDI_sessionBuilder) }
		        func __safeDI_leaf() -> Leaf {
		            return Leaf.__safeDI_init(onTap: onTap, sendableTap: sendableTap, pair: pair, theme: theme, baseTheme: baseTheme, auth: auth, inner: inner, analytics: analytics, sessionBuilder: sessionBuilder, onDismiss: onDismiss, handler: handler, optionalAuth: optionalAuth, capacity: safeDIOverrides.leaf.capacity, onDone: safeDIOverrides.leaf.onDone, names: safeDIOverrides.leaf.names, label: safeDIOverrides.leaf.label, safeDIBuilder: safeDIOverrides.leaf.safeDIBuilder)
		        }
		        let leaf: Leaf = __safeDI_leaf()
		        return Service(onSelect: onSelect, sendableSelect: sendableSelect, size: size, tags: tags, inner2: inner2, leaf: leaf, retries: retries, onFinish: onFinish, title: safeDIOverrides.title, onCancel: safeDIOverrides.onCancel)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_mock_191982787DB3160A {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Leaf` is constructed within the public mock trees of module `Core`.
		public struct __safeDI_Core_Leaf_MockConfiguration {
		    public init(
		        capacity: Int? = nil,
		        onDone: (() -> Void)? = nil,
		        names: [String]? = nil,
		        label: String? = __safeDI_Core_Leaf_mockDefault_label()
		    ) {
		        self.capacity = capacity
		        self.onDone = onDone
		        self.names = names
		        self.label = label
		        self.safeDIBuilder = nil
		    }

		    package init(
		        capacity: Int? = nil,
		        onDone: (() -> Void)? = nil,
		        names: [String]? = nil,
		        label: String? = __safeDI_Core_Leaf_mockDefault_label(),
		        _ safeDIBuilder: ((@escaping () -> Void, @escaping @Sendable () -> Void, (Int, Bool), Theme, BaseTheme, any Auth, Outer.Inner, Analytics, Instantiator<Session>, (() -> Void)?, Handler?, (any Auth)?, Int, @escaping () -> Void, [String], String?) -> Leaf)? = nil
		    ) {
		        self.capacity = capacity
		        self.onDone = onDone
		        self.names = names
		        self.label = label
		        self.safeDIBuilder = safeDIBuilder
		    }

		    /// `nil` keeps the default of `Leaf`'s `capacity`.
		    public let capacity: Int?
		    /// `nil` keeps the default of `Leaf`'s `onDone`.
		    public let onDone: (() -> Void)?
		    /// `nil` keeps the default of `Leaf`'s `names`.
		    public let names: [String]?
		    /// The default of `Leaf`'s `label` unless set.
		    public let label: String?
		    /// Overrides how `Leaf` is constructed. Parameters match the type’s initializer or custom mock method.
		    package let safeDIBuilder: ((@escaping () -> Void, @escaping @Sendable () -> Void, (Int, Bool), Theme, BaseTheme, any Auth, Outer.Inner, Analytics, Instantiator<Session>, (() -> Void)?, Handler?, (any Auth)?, Int, @escaping () -> Void, [String], String?) -> Leaf)?
		}

		extension Leaf {
		    nonisolated static func __safeDI_mockDefault_label() -> String? { "leaf" }
		    static func __safeDI_init(onTap: @escaping () -> Void, sendableTap: @escaping @Sendable () -> Void, pair: (Int, Bool), theme: Theme, baseTheme: BaseTheme, auth: any Auth, inner: Outer.Inner, analytics: Analytics, sessionBuilder: Instantiator<Session>, onDismiss: (() -> Void)?, handler: Handler?, optionalAuth: (any Auth)?, capacity: Int?, onDone: (() -> Void)?, names: [String]?, label: String?, safeDIBuilder: ((@escaping () -> Void, @escaping @Sendable () -> Void, (Int, Bool), Theme, BaseTheme, any Auth, Outer.Inner, Analytics, Instantiator<Session>, (() -> Void)?, Handler?, (any Auth)?, Int, @escaping () -> Void, [String], String?) -> Leaf)?) -> Leaf {
		        let capacity = capacity ?? (10)
		        let onDone = onDone ?? ({})
		        let names = names ?? ([])
		        return if let safeDIBuilder { safeDIBuilder(onTap, sendableTap, pair, theme, baseTheme, auth, inner, analytics, sessionBuilder, onDismiss, handler, optionalAuth, capacity, onDone, names, label) } else { Leaf(onTap: onTap, sendableTap: sendableTap, pair: pair, theme: theme, baseTheme: baseTheme, auth: auth, inner: inner, analytics: analytics, sessionBuilder: sessionBuilder, onDismiss: onDismiss, handler: handler, optionalAuth: optionalAuth, capacity: capacity, onDone: onDone, names: names, label: label) }
		    }
		}
		@usableFromInline nonisolated func __safeDI_Core_Leaf_mockDefault_label() -> String? { Leaf.__safeDI_mockDefault_label() }
		#endif
		""" + "\n"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesOwnDefaultsProvider_whenWiderTierOmitsIsolatedMocksOwnDefaultOfNarrowerType() async throws {
		// M6.3b, found by the public mock corpus (seed 188): `label`, of the internal `Label`, is on the internal tier
		// only, so the public tier omits it and passes the provider's value, the declaration's default, never `nil`.
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Dashboard.swift": """
			import SafeDI

			struct Label {
			    init() {}
			}

			@Instantiable
			public struct Theme: Instantiable {
			    public init() {}
			}

			@MainActor
			@Instantiable(generateMock: .public)
			public struct Dashboard: Instantiable {
			    static var defaultLabel: Label? = Label()

			    init(theme: Theme, label: Label? = defaultLabel) {
			        self.theme = theme
			        self.label = label
			    }

			    @Instantiated let theme: Theme
			    let label: Label?
			}
			"""]),
			// Another package calls the public tier, which `Core`'s own code, seeing both tiers, would not.
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Probe.swift": """
			import Core

			#if DEBUG
			@MainActor func mockDashboard() -> Dashboard {
			    Dashboard.mock()
			}
			#endif
			"""], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Dashboard {
		    @MainActor static func __safeDI_publicMockDefault_label() -> Label? { defaultLabel }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            theme: (() -> Theme)? = nil
		        ) {
		            self.theme = theme
		        }

		        public let theme: (() -> Theme)?
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Dashboard {
		        Dashboard.mock(label: Dashboard.__safeDI_publicMockDefault_label(), safeDIOverrides: safeDIOverrides)
		    }

		    static func mock(
		        label: Label? = Dashboard.__safeDI_publicMockDefault_label(),
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Dashboard {
		        let theme = if let safeDIBuilder = safeDIOverrides.theme { safeDIBuilder() } else { Theme() }
		        return Dashboard(theme: theme, label: label)
		    }
		}

		extension Dashboard {
		    public enum __safeDI_Dashboard_mock_0D31A45F0EAEE567 {}
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("mockDashboard()")])
	}

	// MARK: Tests – builder closures for holes

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderForHole_whenPublicMockedTreeInstantiatesTypeNoDeclarationFulfills() async throws {
		// M7.1, M2.12: no declaration fulfills `UserService`, so the public mock takes a builder for it, required, handed
		// the values in scope at the site; a public initializer elsewhere proves `UserService` `public`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public final class UserService {
				    public init() {}
				}

				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: UserService) {
				        self.userService = userService
				    }

				    @Received let userService: UserService
				}

				@Instantiable
				public final class Analytics: Instantiable {
				    public init() {}
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    init(analytics: Analytics, userService: UserService) {
				        self.analytics = analytics
				        self.userService = userService
				    }

				    @Received let analytics: Analytics
				    @Instantiated let userService: UserService
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Profile+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    public struct SafeDIMockScope_Service_userService {
			        public let analytics: Analytics
			    }

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            analytics: (() -> Analytics)? = nil
			        ) {
			            self.analytics = analytics
			        }

			        public let analytics: (() -> Analytics)?
			    }

			    public static func mock(
			        userServiceBuilder: @escaping (Service.SafeDIMockScope_Service_userService) -> UserService,
			        analytics: Analytics? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let __safeDI_userServiceBuilder = userServiceBuilder
			        let analytics = if let analytics { analytics } else if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
			        let userService: UserService = __safeDI_userServiceBuilder(SafeDIMockScope_Service_userService(analytics: analytics))
			        return Service(analytics: analytics, userService: userService)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_060ADA58E40044B3 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenHoleTypeOnlyPackageInitializerMentions() async {
		// M2.12b, M7.1b: only `Service`'s `package` initializer mentions `UserService`, so its builder is `package`, and
		// the public tier cannot take it.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):5:29: error: SafeDI cannot generate the public mock of `Service`: its `public` tier, which `generateMock: .public` requires, cannot take `userServiceBuilder`, which returns `UserService` for the hole `userService`, and cannot pass `nil` for it, since it is required. `UserService` is `package` as far as SafeDI can tell: every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `package` (`Service.init(userService:)`). Mention `UserService` in a `public` initializer, `instantiate(…)` or mock method SafeDI records (or widen `UserService`'s declaration); widen the declaration that proves the parameter's type; or use `generateMock: .internal`.
			\(fixtures["Service.swift"]):11:5: note: `Service` instantiates `userService: UserService` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public final class UserService {
					    public init() {}
					}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    package init(userService: UserService) {
					        self.userService = userService
					    }

					    @Instantiated let userService: UserService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresEachScopeFieldWithItsOwnAccess_whenHoleScopeHoldsNarrowerTypes() async throws {
		// M2.13, M7.8: the builder is public, as `UserService`'s proof allows, and its scope struct stays public with a
		// `package` field for `Session` and an internal one for `Token`; another package passes a builder that reads the
		// one field it can see.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
					"""
					public final class UserService {
					    public init(analytics: Analytics) {}
					}

					@Instantiable
					public struct Profile: Instantiable {
					    public init(userService: UserService) {
					        self.userService = userService
					    }

					    @Received let userService: UserService
					}

					@Instantiable
					public final class Analytics: Instantiable {
					    public init() {}
					}

					@Instantiable
					package final class Session: Instantiable {
					    package init() {}
					}

					@Instantiable
					final class Token: Instantiable {
					    init() {}
					}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    init(analytics: Analytics, session: Session, token: Token, userService: UserService) {
					        self.analytics = analytics
					        self.session = session
					        self.token = token
					        self.userService = userService
					    }

					    @Received let analytics: Analytics
					    @Instantiated let session: Session
					    @Instantiated let token: Token
					    @Instantiated let userService: UserService
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Caller.swift": "import Core\n\n#if DEBUG\nfunc call() {\n    _ = Service.mock(userServiceBuilder: { scope in UserService(analytics: scope.analytics) })\n}\n#endif\n"], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles["Core.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Service {
		    public struct SafeDIMockScope_Service_userService {
		        package let session: Session
		        internal let token: Token
		        public let analytics: Analytics
		    }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil
		        ) {
		            self.session = nil
		            self.token = nil
		            self.analytics = analytics
		        }

		        package init(
		            session: (() -> Session)? = nil,
		            analytics: (() -> Analytics)? = nil
		        ) {
		            self.session = session
		            self.token = nil
		            self.analytics = analytics
		        }

		        init(
		            session: (() -> Session)? = nil,
		            token: (() -> Token)? = nil,
		            analytics: (() -> Analytics)? = nil
		        ) {
		            self.session = session
		            self.token = token
		            self.analytics = analytics
		        }

		        package let session: (() -> Session)?
		        let token: (() -> Token)?
		        public let analytics: (() -> Analytics)?
		    }

		    public static func mock(
		        userServiceBuilder: @escaping (Service.SafeDIMockScope_Service_userService) -> UserService,
		        analytics: Analytics? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        let __safeDI_userServiceBuilder = userServiceBuilder
		        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        let analytics = if let analytics { analytics } else if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        let userService: UserService = __safeDI_userServiceBuilder(SafeDIMockScope_Service_userService(session: session, token: token, analytics: analytics))
		        return Service(analytics: analytics, session: session, token: token, userService: userService)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_mock_65B17DCF3A268BD2 {}
		}
		#endif
		""")
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderReturningInstantiator_whenHoleIsDeclaredAsInstantiator() async throws {
		// M7.7, M15.13: the builder returns the declared `Instantiator<UserService>`, on the public tier, since the wrapper is
		// allow-listed and a public initializer proves `UserService` `public`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public final class UserService: Instantiable {
				    public init() {}
				}

				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: UserService) {
				        self.userService = userService
				    }

				    @Received let userService: UserService
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    init(userServiceBuilder: Instantiator<UserService>) {
				        self.userServiceBuilder = userServiceBuilder
				    }

				    @Instantiated let userServiceBuilder: Instantiator<UserService>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Profile+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    public struct SafeDIMockScope_Service_userServiceBuilder {}

			    public static func mock(
			        userServiceBuilderBuilder: @escaping (Service.SafeDIMockScope_Service_userServiceBuilder) -> Instantiator<UserService>
			    ) -> Service {
			        let __safeDI_userServiceBuilderBuilder = userServiceBuilderBuilder
			        let userServiceBuilder = __safeDI_userServiceBuilderBuilder(SafeDIMockScope_Service_userServiceBuilder())
			        return Service(userServiceBuilder: userServiceBuilder)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_F2F7AC97BDC0800F {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsEscapingBuilderFromWrappersBuilderFunction_whenHoleIsBeneathInstantiatorOrLazilyInstantiated() async throws {
		// M7.9: each site sits in the builder function of an `Instantiator` or a `LazilyInstantiated`, which captures the
		// builder, so the builder is `@escaping`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public final class UserService {
				    public init() {}
				}

				public final class Clock {
				    public init() {}
				}

				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: UserService) {
				        self.userService = userService
				    }

				    @Instantiated let userService: UserService
				}

				@Instantiable
				public struct Settings: Instantiable {
				    public init(clock: Clock) {
				        self.clock = clock
				    }

				    @Instantiated let clock: Clock
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    init(profileBuilder: Instantiator<Profile>, settings: LazilyInstantiated<Settings>) {
				        self.profileBuilder = profileBuilder
				        self.settings = settings
				    }

				    @Instantiated let profileBuilder: Instantiator<Profile>
				    @Instantiated let settings: LazilyInstantiated<Settings>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Profile+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    public struct SafeDIMockScope_Settings_clock {
			        public let profileBuilder: Instantiator<Profile>
			    }

			    public struct SafeDIMockScope_Profile_userService {}

			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            profileBuilder: ((UserService) -> Profile)? = nil,
			            settings: ((Clock) -> Settings)? = nil
			        ) {
			            self.profileBuilder = profileBuilder
			            self.settings = settings
			        }

			        public let profileBuilder: ((UserService) -> Profile)?
			        public let settings: ((Clock) -> Settings)?
			    }

			    public static func mock(
			        clockBuilder: @escaping (Service.SafeDIMockScope_Settings_clock) -> Clock,
			        userServiceBuilder: @escaping (Service.SafeDIMockScope_Profile_userService) -> UserService,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let __safeDI_clockBuilder = clockBuilder
			        let __safeDI_userServiceBuilder = userServiceBuilder
			        func __safeDI_profileBuilder() -> Profile {
			            let userService: UserService = __safeDI_userServiceBuilder(SafeDIMockScope_Profile_userService())
			            return if let safeDIBuilder = safeDIOverrides.profileBuilder { safeDIBuilder(userService) } else { Profile(userService: userService) }
			        }
			        let profileBuilder = Instantiator<Profile>(__safeDI_profileBuilder)
			        func __safeDI_settings() -> Settings {
			            let clock: Clock = __safeDI_clockBuilder(SafeDIMockScope_Settings_clock(profileBuilder: profileBuilder))
			            return if let safeDIBuilder = safeDIOverrides.settings { safeDIBuilder(clock) } else { Settings(clock: clock) }
			        }
			        let settings = LazilyInstantiated<Settings>(__safeDI_settings)
			        return Service(profileBuilder: profileBuilder, settings: settings)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_44D66FF4F5AC28C5 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderReturningDeclaredSpelling_whenHoleIsExistentialOrClosureTypealias() async throws {
		// M15.13: a builder returns the hole's declared type as spelled, `any UserService` and the typealias `Scores`, each
		// proven `public` by a public initializer that mentions it. (A closure typealias cannot be a dependency: Swift stores
		// only an `@escaping` parameter, and the macro matches `@escaping Handler` to no property.)
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol UserService {}

				public typealias Scores = [String: Int]

				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: any UserService, scores: Scores) {
				        self.userService = userService
				        self.scores = scores
				    }

				    @Received let userService: any UserService
				    @Received let scores: Scores
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    init(userService: any UserService, scores: Scores) {
				        self.userService = userService
				        self.scores = scores
				    }

				    @Instantiated let userService: any UserService
				    @Instantiated let scores: Scores
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Profile+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    public struct SafeDIMockScope_Service_scores {
			        public let userService: any UserService
			    }

			    public struct SafeDIMockScope_Service_userService {}

			    public static func mock(
			        scoresBuilder: @escaping (Service.SafeDIMockScope_Service_scores) -> Scores,
			        userServiceBuilder: @escaping (Service.SafeDIMockScope_Service_userService) -> any UserService
			    ) -> Service {
			        let __safeDI_scoresBuilder = scoresBuilder
			        let __safeDI_userServiceBuilder = userServiceBuilder
			        let userService: any UserService = __safeDI_userServiceBuilder(SafeDIMockScope_Service_userService())
			        let scores: Scores = __safeDI_scoresBuilder(SafeDIMockScope_Service_scores(userService: userService))
			        return Service(userService: userService, scores: scores)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_901A1BFB972C4B78 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderOfCalledPublicMock_whenConsumerSeesNoTypeThatFulfillsHole() async throws {
		// R7: `App` sees no declaration that fulfills `Service`'s hole, so `Screen`'s mock takes the builder the public mock
		// takes and passes it on.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.holeModules(app: Self.holeScreen),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        let analytics: (() -> Analytics)?
		        let service: Service.SafeDIOverrides
		    }

		    static func mock(
		        userServiceBuilder: @escaping (Service.SafeDIMockScope_Service_userService) -> AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        _ = Service.__safeDI_Service_mock_2B11C431EE7A52B8.self
		        let service = Service.mock(userServiceBuilder: userServiceBuilder, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        return Screen(analytics: analytics, service: service)
		    }
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsBuilderOfCalledPublicMock_whenConsumerSeesTypeThatFulfillsHole() async throws {
		// M7.3: `App` sees `DefaultUserService`, so `Screen`'s mock fills `Service`'s builder with a function that builds it
		// from the values the scope struct carries.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.holeModules(app: Self.holeScreen + "\n\n" + Self.defaultUserService),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        let analytics: (() -> Analytics)?
		        let service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        func __safeDI_userServiceBuilder(_ scope: Service.SafeDIMockScope_Service_userService) -> AnyUserService {
		            let analytics = scope.analytics
		            let userService = AnyUserService(DefaultUserService(analytics: analytics))
		            return userService
		        }
		        _ = Service.__safeDI_Service_mock_2B11C431EE7A52B8.self
		        let service = Service.mock(userServiceBuilder: __safeDI_userServiceBuilder, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        return Screen(analytics: analytics, service: service)
		    }
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_refersToEnclosingFill_whenFillBuildsTypeWhoseInstantiatorCallsSamePublicMock() async throws {
		// M8.27: `Router` fills `Service`'s hole and builds `Service` again through an `Instantiator`, a fully lazy cycle.
		// The call inside the fill passes the fill around it, which it refers to by name.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.lazyCycleThroughFillModules(router: """
			@Instantiable
			public final class Router: Instantiable, Routing {
			    public init(serviceBuilder: Instantiator<Service>) {
			        self.serviceBuilder = serviceBuilder
			    }

			    @Instantiated let serviceBuilder: Instantiator<Service>
			}
			"""),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.service = service
		        }

		        let service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_routerBuilderBuilder(_ scope: Service.SafeDIMockScope_Service_routerBuilder) -> ErasedInstantiator<(), AnyRouting> {
		            let analytics = scope.analytics
		            func __safeDI_routerBuilder() -> Router {
		                func __safeDI_serviceBuilder() -> Service {
		                    Service.mock(routerBuilderBuilder: __safeDI_routerBuilderBuilder, analytics: analytics)
		                }
		                let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
		                return Router(serviceBuilder: serviceBuilder)
		            }
		            let routerBuilder = ErasedInstantiator<(), AnyRouting> {
		                AnyRouting(__safeDI_routerBuilder())
		            }
		            return routerBuilder
		        }
		        _ = Service.__safeDI_Service_mock_EFE368FB931BE019.self
		        let service = Service.mock(routerBuilderBuilder: __safeDI_routerBuilderBuilder, analytics: nil, safeDIOverrides: safeDIOverrides.service)
		        return Screen(service: service)
		    }
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderUp_whenFillWouldReceiveInstantiatorOfTypeItBuildsWithin() async throws {
		// M8.27b: `Router` receives the `Instantiator<Service>` whose tree it is built in, which no value of the scope
		// struct gives it, so `Screen`'s mock does not fill `Service`'s builder: it takes it, as a caller that sees no
		// fulfilling type does.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.lazyCycleThroughFillModules(router: """
			@Instantiable
			public final class Router: Instantiable, Routing {
			    public init(serviceBuilder: Instantiator<Service>) {
			        self.serviceBuilder = serviceBuilder
			    }

			    @Received let serviceBuilder: Instantiator<Service>
			}
			"""),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.service = service
		        }

		        let service: Service.SafeDIOverrides
		    }

		    static func mock(
		        routerBuilderBuilder: @escaping (Service.SafeDIMockScope_Service_routerBuilder) -> ErasedInstantiator<(), AnyRouting>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Service.__safeDI_Service_mock_EFE368FB931BE019.self
		        let service = Service.mock(routerBuilderBuilder: routerBuilderBuilder, analytics: nil, safeDIOverrides: safeDIOverrides.service)
		        return Screen(service: service)
		    }
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderUpOnPublicTier_whenPublicConsumerSeesNoTypeThatFulfillsHole() async throws {
		// R7: `Screen`'s own public mock takes the builder it passes up on its public tier, as `Service`'s takes it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.holeModules(app: Self.holeScreen.replacingOccurrences(of: "generateMock: true", with: "generateMock: .public")),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		        }

		        public let analytics: (() -> Analytics)?
		        public let service: Service.SafeDIOverrides
		    }

		    public static func mock(
		        userServiceBuilder: @escaping (Service.SafeDIMockScope_Service_userService) -> AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        _ = Service.__safeDI_Service_mock_2B11C431EE7A52B8.self
		        let service = Service.mock(userServiceBuilder: userServiceBuilder, analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        return Screen(analytics: analytics, service: service)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_10126BE056EC8617 {}
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicMocksTreeReachesDeclarationOfModuleInfoNamingNoModule() async {
		// M8.25b: `Base`'s module info was written without `--module-name`, so the modules that call `Service`'s public
		// mock compute its signature without `Logger`: for them `logger` is a hole, whose builder the mock would take,
		// while `Core` builds it. The calls would not match the mock, so `Core` reports `Service`, naming `Logger`.
		await assertThrowsMultiModuleError(inModule: "Core", diagnostics: { fixtures in
			"\(fixtures["Core"]!["Service.swift"]):3:29: error: SafeDI cannot generate the public mock of `Service`: its signature depends on `Logger`, which is declared in a module whose SafeDI module info names no module, and the modules that call the mock, which compute its signature from the modules this module's module info names, cannot see that declaration, so their calls would not match the mock. Generate that module's module info with `--module-name`."
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Base",
						packageName: "Shop",
						swiftFileContent: [
							"""
							@Instantiable
							public final class Logger: Instantiable {
							    public init() {}
							}
							""",
						],
						omitsModuleName: true,
					),
					ModuleFixture(
						name: "Core",
						packageName: "Shop",
						swiftFileContent: [
							"""
							import Base

							@Instantiable(generateMock: .public)
							public struct Service: Instantiable {
							    public init(logger: Logger) {
							        self.logger = logger
							    }

							    @Instantiated let logger: Logger
							}
							""",
						],
						dependencies: ["Base"],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicMocksTreeReachesAdditionalDirectoryDeclarationUnderTargetGraph() async {
		// M8.26: the callers compute `Service`'s public mock from the files the plugin's target graph lists, which leave
		// out the directory the configuration adds and its `Detail`, so for them `detail` is a hole.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:29: error: SafeDI cannot generate the public mock of `Service`: its signature depends on `Detail`, which is declared in a directory this module's `#SafeDIConfiguration` adds, and the modules that call the mock cannot see that declaration, so their calls would not match the mock. Declare `Detail` in a file of this module, or of a module it depends on.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					#SafeDIConfiguration(
					    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
					)
					""",
					"""
					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    public init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
				],
				additionalDirectorySwiftFileContent: [
					"""
					@Instantiable
					public struct Detail: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				pluginTargetGraph: { inputSwiftFilePaths in
					PluginTargetGraph(
						target: PluginTargetGraph.Target(moduleName: "App", packageID: "application", sourceFilePaths: inputSwiftFilePaths, dependencyModuleNames: []),
						dependencyTargets: [],
					)
				},
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenConsumerMustCallPublicMockOfModuleWhoseDependencysModuleInfoIsNotGiven() async {
		// M8.26b: `App` cannot build `Service`'s tree, so it must call the public mock, whose signature is computed from
		// what `Core` sees, which includes `Base`: `App`, given only `Core`'s module info, cannot compute it. Reported at
		// `App`'s dependency on `Service`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):9:5: error: SafeDI cannot generate a call to the public mock SafeDI generated for `Service` in module `Core`, which this module's mocks cannot build inline: that mock's signature depends on the declarations `Core` sees, which include module `Base`'s, and this run was not given `Base`'s SafeDI module info. Give this run every module `Core` depends on: add `Base` (the target that compiles it) to this target's `deps` under Bazel, or to its `dependencies` under Tuist, or pass its `.safedi` file to `--dependent-module-info-file-path`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Base", packageName: "pkg", swiftFileContent: [
						"""
						@Instantiable
						public final class Analytics: Instantiable {
						    public init() {}
						}
						""",
					]),
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
						"""
						import Base

						@Instantiable
						package final class Session: Instantiable {
						    package init() {}
						}

						@Instantiable(generateMock: .public)
						public struct Service: Instantiable {
						    package init(analytics: Analytics, session: Session) {
						        self.analytics = analytics
						        self.session = session
						    }

						    @Instantiated let analytics: Analytics
						    @Instantiated let session: Session
						}
						""",
					], dependencies: ["Base"]),
					ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
					import Core

					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(service: Service) {
					        self.service = service
					    }

					    @Instantiated let service: Service
					}
					"""], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableBuilder_whenBuilderPassedUpIsCalledInSendableBuilderFunction() async throws {
		// Found by the public mock corpus (seed 56): `Screen` builds `Service` in a `@Sendable` builder function, which
		// captures the builder `Screen`'s mock passes up, so the mock takes it `@Sendable`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.holeModules(app: """
			import Core

			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(serviceBuilder: SendableInstantiator<Service>) {
			        self.serviceBuilder = serviceBuilder
			    }

			    @Instantiated let serviceBuilder: SendableInstantiator<Service>
			}
			"""),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            serviceBuilder: (@Sendable () -> Service.SafeDIOverrides)? = nil
		        ) {
		            self.serviceBuilder = serviceBuilder
		        }

		        let serviceBuilder: (@Sendable () -> Service.SafeDIOverrides)?
		    }

		    static func mock(
		        userServiceBuilder: @escaping @Sendable (Service.SafeDIMockScope_Service_userService) -> AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Service.__safeDI_Service_mock_2B11C431EE7A52B8.self
		        let __safeDI_serviceBuilder__safeDIBuilder = safeDIOverrides.serviceBuilder
		        @Sendable func __safeDI_serviceBuilder() -> Service {
		            Service.mock(userServiceBuilder: userServiceBuilder, analytics: nil, safeDIOverrides: __safeDI_serviceBuilder__safeDIBuilder?() ?? .init())
		        }
		        let serviceBuilder = SendableInstantiator<Service>(__safeDI_serviceBuilder)
		        return Screen(serviceBuilder: serviceBuilder)
		    }
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesRequiredParameter_whenTreeInstantiatesTypeThatCannotBeHole() async throws {
		// R7: only a type a nominal type could be is a hole. An array nothing fulfills, as a seam's tree reports it, is a
		// required parameter of the public mock, as an internal mock takes it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    public init(names: [String]) {
				        self.names = names
				    }

				    @Instantiated let names: [String]
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    public static func mock(
			        names: [String]
			    ) -> Service {
			        return Service(names: names)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_1E19B78A930879F1 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenTreeInstantiatesNarrowerTypeThatCannotBeHole() async {
		// R7: an array of an internal type nothing fulfills is a required parameter no public tier can take.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):3:29: error: SafeDI cannot generate the public mock of `Service`: its `public` tier, which `generateMock: .public` requires, cannot take `secrets: [Secret]`, which `Service` instantiates and no `@Instantiable` declaration this module sees fulfills, and cannot pass `nil` for it, since it is required. `Secret` is `internal` as far as SafeDI can tell: every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `internal` (`Service.init(secrets:)`). Mention `Secret` in a `public` initializer, `instantiate(…)` or mock method SafeDI records (or widen `Secret`'s declaration); widen the declaration that proves the parameter's type; or use `generateMock: .internal`.
			\(fixtures["Service.swift"]):9:5: note: `Service` instantiates `secrets: [Secret]` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					struct Secret {}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    init(secrets: [Secret]) {
					        self.secrets = secrets
					    }

					    @Instantiated let secrets: [Secret]
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – calling a public mock from another module

	@Test(arguments: [MultiModuleIntegration.moduleInfo, .swiftPackagePlugin])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicTierOfPublicMock_whenAnotherPackageCannotBuildItsTree(integration: MultiModuleIntegration) async throws {
		// M8.4: `App` cannot build `Service`'s tree (`TokenCache` and `FakeLogger` are `package`), so its mock calls
		// the public tier, passing what its tree provides, and `nil` for `session`, which the tier omits.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.canonicalModules(appCaller: Self.canonicalScreen),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let imports = """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		"""
		let pluginComment = integration == .swiftPackagePlugin ? " // If this line does not compile, add the SafeDI plugin to the target that declares Service." : ""
		let screenMock = """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            theme: (() -> Theme)? = nil,
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.theme = theme
		            self.service = service
		        }

		        let analytics: (() -> Analytics)?
		        let theme: (() -> Theme)?
		        let service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        let theme = if let safeDIBuilder = safeDIOverrides.theme { safeDIBuilder() } else { Theme() }
		        _ = Service.__safeDI_Service_mock_209346FEA041FD20.self\(pluginComment)
		        let service = Service.mock(analytics: analytics.instance, theme: theme, safeDIOverrides: safeDIOverrides.service)
		        return Screen(analytics: analytics, theme: theme, service: service)
		    }
		}
		#endif
		"""
		switch integration {
		case .moduleInfo:
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + imports + "\n\n" + screenMock])
		case .swiftPackagePlugin:
			#expect(output.modules["App"]?.generatedFiles == [
				"SafeDIMockConfiguration.swift": generatedFileHeader + imports + "\n\n",
				"Caller+SafeDIMock.swift": generatedFileHeader + imports + "\n\n" + screenMock,
			])
		}
		try expectEveryModuleCompiled(output)
		guard integration == .moduleInfo else { return }
		// M8.32, a stated divergence: the call hands `Service`'s mock the instance of `Screen`'s `analytics`, which the
		// mock wraps again, reading it as it does; the instance is the one the inline mock shares.
		try await expectValuesAgreeWithInlineMocks(
			of: Self.canonicalModules(appCaller: Self.canonicalScreen),
			output: output,
			probes: [DifferentialValueProbe("Screen.mock()")],
			exempting: [DifferentialValueDifference(
				probe: "Screen.mock()",
				path: ["Screen", "service", "analytics"],
				feature: "analytics: <2> LazilyInstantiated<Analytics> (already instantiated, instance read last)",
				knownRight: "analytics: <1> LazilyInstantiated<Analytics> (seen, first at Screen > analytics)",
			)],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenConsumerProvidesValueThatReachedTierOmits() async {
		// M2.23a: `App` reaches `Service`'s public tier, which omits `filter`, a type only `TokenCache`'s package
		// initializer mentions; `Screen` forwards `filter`, which the inline mock would hand `TokenCache`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):11:5: error: `Screen` provides `filter: Filter`, but the `public` mock SafeDI generated for `Service` in module `Core`, the narrowest one module `App` can call, does not take it: `Service.mock` takes `filter` only on its `package` tier, so this call would pass `nil` to `TokenCache`, which the inline mock would hand `filter`. `Filter` is `package` as far as SafeDI can tell: every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `package` (`TokenCache.init(filter:)`). Widen `TokenCache.init(filter:)` to `public`; mention `Filter` in a `public` initializer, `instantiate(…)` or mock method SafeDI records (or widen `Filter`'s declaration); or stop providing `filter` on this path.
			\(fixtures["Core"]!["Service.swift"]):13:5: note: `TokenCache` receives `filter: Filter?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
					import SafeDI

					public struct Filter {
					    public init() {}
					}

					@Instantiable
					package struct TokenCache: Instantiable {
					    package init(filter: Filter?) {
					        self.filter = filter
					    }

					    @Received(onlyIfAvailable: true) let filter: Filter?
					}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    package init(tokenCache: TokenCache) {
					        self.tokenCache = tokenCache
					    }

					    @Instantiated let tokenCache: TokenCache
					}
					"""]),
					ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
					import Core
					import SafeDI

					@Instantiable(generateMock: true)
					public struct Screen: Instantiable {
					    public init(filter: Filter, service: Service) {
					        self.filter = filter
					        self.service = service
					    }

					    @Forwarded let filter: Filter
					    @Received let service: Service
					}
					"""], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenConsumerThatCannotTellItsPackageProvidesValueThatReachedTierOmits() async {
		// M8.35: neither module has a package name, so nothing is `package`, and `App`, which SafeDI cannot tell is in
		// `Core`'s package, reaches the tier `package` access reaches, the public one, which omits `filter`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):11:5: error: `Screen` provides `filter: Filter`, but the `public` mock SafeDI generated for `Service` in module `Core`, the narrowest one module `App`, which SafeDI cannot tell is in the same package, can call, does not take it: `Service.mock` takes `filter` only on its `internal` tier, so this call would pass `nil` to `TokenCache`, which the inline mock would hand `filter`. `Filter` is `internal` as far as SafeDI can tell: every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `internal` (`TokenCache.init(filter:)`). Widen `TokenCache.init(filter:)` to `package`, or `public` if the two modules are in different packages; mention `Filter` in a `package` initializer, `instantiate(…)` or mock method SafeDI records (or widen `Filter`'s declaration); or stop providing `filter` on this path.
			\(fixtures["Core"]!["Service.swift"]):13:5: note: `TokenCache` receives `filter: Filter?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
					import SafeDI

					public struct Filter {
					    public init() {}
					}

					@Instantiable
					struct TokenCache: Instantiable {
					    init(filter: Filter?) {
					        self.filter = filter
					    }

					    @Received(onlyIfAvailable: true) let filter: Filter?
					}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    init(tokenCache: TokenCache) {
					        self.tokenCache = tokenCache
					    }

					    @Instantiated let tokenCache: TokenCache
					}
					"""], omitsPackageName: true),
					ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
					import Core
					import SafeDI

					@Instantiable(generateMock: true)
					public struct Screen: Instantiable {
					    public init(filter: Filter, service: Service) {
					        self.filter = filter
					        self.service = service
					    }

					    @Forwarded let filter: Filter
					    @Received let service: Service
					}
					"""], dependencies: ["Core"], omitsPackageName: true),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTreeInlineThatDoesNotCompile_whenConsumerThatCannotTellItsPackageReachesPackageConstruction() async throws {
		// M8.35b, a stated leftover of row 4b's B4.10b that this row does not cause: `App` has a module name and no package
		// name, which SafeDI assumes reaches `package` access, so it builds `Service`'s tree inline, as it would from
		// within `Core`'s package, with PR 3b's comment, and a module outside that package cannot compile it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
				import SafeDI

				public struct Filter {
				    public init() {}
				}

				@Instantiable
				package struct TokenCache: Instantiable {
				    package init(filter: Filter?) {
				        self.filter = filter
				    }

				    @Received(onlyIfAvailable: true) let filter: Filter?
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    package init(tokenCache: TokenCache) {
				        self.tokenCache = tokenCache
				    }

				    @Instantiated let tokenCache: TokenCache
				}
				"""]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
				import Core
				import SafeDI

				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(filter: Filter, service: Service) {
				        self.filter = filter
				        self.service = service
				    }

				    @Forwarded let filter: Filter
				    @Received let service: Service
				}
				"""], dependencies: ["Core"], omitsPackageName: true),
			],
			integration: .moduleInfo,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)
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
		            service: Service.SafeDIMockConfiguration = .init()
		        ) {
		            self.service = service
		        }

		        let service: Service.SafeDIMockConfiguration
		    }

		    static func mock(
		        filter: Filter,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_service() -> Service {
		            let tokenCache = if let safeDIBuilder = safeDIOverrides.service.tokenCache { safeDIBuilder(filter) } else { TokenCache(filter: filter) } // SafeDI could not verify that TokenCache is in this package; `package` access is assumed.
		            return if let safeDIBuilder = safeDIOverrides.service.safeDIBuilder { safeDIBuilder(tokenCache) } else { Service(tokenCache: tokenCache) } // SafeDI could not verify that Service is in this package; `package` access is assumed.
		        }
		        let service: Service = __safeDI_service()
		        return Screen(filter: filter, service: service)
		    }
		}
		#endif

		#if DEBUG
		extension Service {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            tokenCache: ((Filter?) -> TokenCache)? = nil,
		            _ safeDIBuilder: ((TokenCache) -> Service)? = nil
		        ) {
		            self.tokenCache = tokenCache
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let tokenCache: ((Filter?) -> TokenCache)?
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        let safeDIBuilder: ((TokenCache) -> Service)?
		    }
		}
		#endif
		""" + "\n"])
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation)
		#expect(compilation.modules.map { $0.exitCode == 0 } == [true, false])
		let failure = try #require(compilation.failure)
		#expect(failure.moduleName == "App")
		#expect(failure.standardError.contains("cannot find type 'TokenCache' in scope"), "Unexpected compiler output \(failure.standardError)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsPublicMockFirst_whenProviderOfOmittedValueIsDeclaredFirstAndReceivesItOnlyIfAvailable() async throws {
		// M2.23c, `filter` declared first: `AppFilter`'s receive of `service` orders `service` first, so the leaf's soft
		// edge on `filter` would close a cycle and is dropped; `filter` is not yet built where `service` is, and no
		// value is omitted, as the inline mock passes `TokenCache` `nil`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.softEdgeModules(screenDeclaresFilterFirst: true),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
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
		            service: Service.SafeDIOverrides = .init(),
		            filter: ((Service?) -> FilterProtocol)? = nil
		        ) {
		            self.service = service
		            self.filter = filter
		        }

		        let service: Service.SafeDIOverrides
		        let filter: ((Service?) -> FilterProtocol)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Service.__safeDI_Service_mock_A107C7CF39C5CB30.self
		        let service = Service.mock(safeDIOverrides: safeDIOverrides.service)
		        let filter: FilterProtocol = if let safeDIBuilder = safeDIOverrides.filter { safeDIBuilder(service) } else { AppFilter(service: service) }
		        return Screen(filter: filter, service: service)
		    }
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicMockIsDeclaredBeforeProviderOfValueItsTierOmits() async {
		// M2.23c, `service` declared first: the leaf's soft edge on `filter` is kept, so `filter` is built first, and
		// the call would pass `nil` for the value the inline mock hands `TokenCache`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):21:5: error: `Screen` provides `filter: any FilterProtocol`, but the `public` mock SafeDI generated for `Service` in module `Core`, the narrowest one module `App` can call, does not take it: `Service.mock` takes `filter` only on its `package` tier, so this call would pass `nil` to `TokenCache`, which the inline mock would hand `filter`. `FilterProtocol` is `package` as far as SafeDI can tell: every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `package` (`TokenCache.init(filter:)`). Widen `TokenCache.init(filter:)` to `public`; mention `FilterProtocol` in a `public` initializer, `instantiate(…)` or mock method SafeDI records (or widen `FilterProtocol`'s declaration); or stop providing `filter` on this path.
			\(fixtures["Core"]!["Service.swift"]):11:5: note: `TokenCache` receives `filter: (any FilterProtocol)?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.softEdgeModules(screenDeclaresFilterFirst: false),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesValueDownChainOfPublicMocks_whenOuterPublicMockTakesWhatInnerCallPasses() async throws {
		// M8.33: `Dashboard`'s mock calls `Service`'s and does not provide `analytics`, so it takes `analytics: Analytics? =
		// nil` on its public tier and passes it on; `AppRoot` passes the instance it holds, so one instance is shared.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
				import SafeDI

				@Instantiable
				public final class Analytics: Instantiable {
				    public init() {}
				}

				@Instantiable
				package struct TokenCache: Instantiable {
				    package init(analytics: Analytics) {
				        self.analytics = analytics
				    }

				    @Received let analytics: Analytics
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    package init(analytics: Analytics, tokenCache: TokenCache) {
				        self.analytics = analytics
				        self.tokenCache = tokenCache
				    }

				    @Received let analytics: Analytics
				    @Instantiated let tokenCache: TokenCache
				}
				"""]),
				ModuleFixture(name: "Feature", packageName: "feature", swiftFileContentByFilePath: ["Dashboard.swift": """
				import Core
				import SafeDI

				@Instantiable(generateMock: .public)
				public struct Dashboard: Instantiable {
				    package init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				"""], dependencies: ["Core"]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["AppRoot.swift": """
				import Core
				import Feature
				import SafeDI

				@Instantiable(generateMock: true)
				public struct AppRoot: Instantiable {
				    public init(analytics: LazilyInstantiated<Analytics>, dashboard: Dashboard) {
				        self.analytics = analytics
				        self.dashboard = dashboard
				    }

				    @Instantiated let analytics: LazilyInstantiated<Analytics>
				    @Instantiated let dashboard: Dashboard
				}
				"""], dependencies: ["Core", "Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Dashboard {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.service = service
		        }

		        public let service: Service.SafeDIOverrides
		    }

		    public static func mock(
		        analytics: Analytics? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Dashboard {
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self
		        let service = Service.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        return Dashboard(service: service)
		    }
		}

		extension Dashboard {
		    public enum __safeDI_Dashboard_mock_81027395670D1D21 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension AppRoot {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            dashboard: Dashboard.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.dashboard = dashboard
		        }

		        let analytics: (() -> Analytics)?
		        let dashboard: Dashboard.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> AppRoot {
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        _ = Dashboard.__safeDI_Dashboard_mock_81027395670D1D21.self
		        let dashboard = Dashboard.mock(analytics: analytics.instance, safeDIOverrides: safeDIOverrides.dashboard)
		        return AppRoot(analytics: analytics, dashboard: dashboard)
		    }
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_letsEachPublicMockBuildDependencyItsCallerCannotName_whenTwoPublicMocksReceiveIt() async throws {
		// M8.9b: each public tier omits the package `session`, which `App` cannot name, so each call passes nothing for it
		// and each public mock builds its own `Session`, where an inline mock would share one (a stated divergence).
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
				import SafeDI

				@Instantiable
				package struct Session: Instantiable {
				    package init() {}
				}

				@Instantiable
				package struct TokenCache: Instantiable {
				    package init(session: Session) {
				        self.session = session
				    }

				    @Received let session: Session
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    package init(tokenCache: TokenCache) {
				        self.tokenCache = tokenCache
				    }

				    @Instantiated let tokenCache: TokenCache
				}

				@Instantiable(generateMock: .public)
				public struct Vault: Instantiable {
				    package init(tokenCache: TokenCache) {
				        self.tokenCache = tokenCache
				    }

				    @Instantiated let tokenCache: TokenCache
				}
				"""]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
				import Core
				import SafeDI

				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(service: Service, vault: Vault) {
				        self.service = service
				        self.vault = vault
				    }

				    @Received let service: Service
				    @Received let vault: Vault
				}
				"""], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
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
		            service: Service.SafeDIOverrides = .init(),
		            vault: Vault.SafeDIOverrides = .init()
		        ) {
		            self.service = service
		            self.vault = vault
		        }

		        let service: Service.SafeDIOverrides
		        let vault: Vault.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Service.__safeDI_Service_mock_B3677AD76727096E.self
		        let service = Service.mock(safeDIOverrides: safeDIOverrides.service)
		        _ = Vault.__safeDI_Vault_mock_B3677AD76727096E.self
		        let vault = Vault.mock(safeDIOverrides: safeDIOverrides.vault)
		        return Screen(service: service, vault: vault)
		    }
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesParameterOnNoTier_whenPublicMockTreeCallsTierThatOmitsIt() async throws {
		// M8.33d, `AppRoot` holding nothing for `filter`: `Outer` reaches `Service`'s public tier, which omits `filter`,
		// so no tier of `Outer`'s mock takes it, and `App` calls `Outer.mock()`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.chainModules(appRootForwardsFilter: false),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Mid"]?.generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Outer {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.service = service
		        }

		        public let service: Service.SafeDIOverrides
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        _ = Service.__safeDI_Service_mock_5BD7973A2F881650.self
		        let service = Service.mock(safeDIOverrides: safeDIOverrides.service)
		        return Outer(service: service)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_mock_51799E6AA5E7B634 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Mid)
		import Mid
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension AppRoot {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            outer: Outer.SafeDIOverrides = .init()
		        ) {
		            self.outer = outer
		        }

		        let outer: Outer.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> AppRoot {
		        _ = Outer.__safeDI_Outer_mock_51799E6AA5E7B634.self
		        let outer = Outer.mock(safeDIOverrides: safeDIOverrides.outer)
		        return AppRoot(outer: outer)
		    }
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenConsumerProvidesValueNoTierOfCalledPublicMockTakes() async {
		// M8.33d, `AppRoot` forwarding `filter`: the inline mock would hand it to `TokenCache`, deep in `Outer`'s tree,
		// but no tier of `Outer`'s mock takes it, since the tier of `Service`'s mock that `Outer`'s tree calls omits it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["AppRoot.swift"]):12:5: error: `AppRoot` provides `filter: Filter`, but no mock SafeDI generated for `Outer` takes it: `Outer`'s mock tree calls the `public` mock SafeDI generated for `Service` in module `Core`, the narrowest one module `Mid` can call, which takes `filter` only on its `package` tier, so calling it would pass `nil` to `TokenCache`, which the inline mock would hand `filter`. `Filter` is `package` as far as SafeDI can tell: every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `package` (`TokenCache.init(filter:)`). Widen `TokenCache.init(filter:)` to `public`; mention `Filter` in a `public` initializer, `instantiate(…)` or mock method SafeDI records (or widen `Filter`'s declaration); or stop providing `filter` on this path.
			\(fixtures["Core"]!["Service.swift"]):13:5: note: `TokenCache` receives `filter: Filter?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.chainModules(appRootForwardsFilter: true),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenConsumerCallsPublicMockGeneratedUnderAnotherMockCondition() async {
		// M11.2: `Core` generates its mocks under `TESTING`, which this run reads from its module info; `App`'s mocks
		// compile under `DEBUG`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):10:5: error: `Service.mock()` is generated under `#if TESTING` in `Core`, but this module's mocks compile under `#if DEBUG`. Give both modules one `mockConditionalCompilation`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.mockConditionModules(appMockCondition: nil),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicMock_whenPluginReadsDeclaringModulesConfigurationThatNamesTheSameMockCondition() async throws {
		// M11.5b: under the plugin, the condition is read from the configuration in a file of `Core`, which names
		// `TESTING`, as `App`'s does, so the call is generated under `TESTING`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.mockConditionModules(appMockCondition: "TESTING"),
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		let imports = """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		"""
		#expect(output.modules["App"]?.generatedFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + imports + """


			#if TESTING
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: Service.SafeDIOverrides = .init()
			        ) {
			            self.service = service
			        }

			        let service: Service.SafeDIOverrides
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        _ = Service.__safeDI_Service_mock_51799E6AA5E7B634.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
			        let service = Service.mock(safeDIOverrides: safeDIOverrides.service)
			        return Screen(service: service)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + imports + "\n\n",
		])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenConsumerHoldsHandWrittenMockNamedMockForTypeWithPublicMock() async {
		// M9.2: `App` reaches `Service`, whose public `mock()` `Core` generates, while holding a hand-written `mock` for it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):15:5: error: `Service` has a public `mock()` generated by `Core`; a hand-written `mock` here makes every call ambiguous. Give it another name and pass it as `customMockName`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
					import SafeDI

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    public init() {}
					}
					"""]),
					ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
					import Core
					import SafeDI

					@Instantiable(generateMock: true)
					public struct Screen: Instantiable {
					    public init(service: Service) {
					        self.service = service
					    }

					    @Received let service: Service
					}

					@Instantiable(mockOnly: true)
					extension Service {
					    public static func mock(name: String = "") -> Service { Service() }
					}
					"""], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSuggestingPublicMock_whenConsumerCannotBuildTreeOfTypeWithoutOne() async {
		// M8.6: `Service` has no public mock, and `App` cannot construct `TokenCache` in its tree.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Service.swift"]):5:5: error: `TokenCache`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix, or give `Service` a public mock: `generateMock: .public`, or a hand-written public `mock`.
			\(fixtures["Core"]!["Service.swift"]):5:5-5:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
					import SafeDI

					@Instantiable
					public struct TokenCache: Instantiable {
					    package init() {}
					}

					@Instantiable
					public struct Service: Instantiable {
					    public init(tokenCache: TokenCache) {
					        self.tokenCache = tokenCache
					    }

					    @Instantiated let tokenCache: TokenCache
					}
					"""]),
					ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
					import Core
					import SafeDI

					@Instantiable(generateMock: true)
					public struct Screen: Instantiable {
					    public init(service: Service) {
					        self.service = service
					    }

					    @Received let service: Service
					}
					"""], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsPublicMockOverridesThroughSendableClosure_whenCallIsInSendableBuilder() async throws {
		// M8.20: `Wrapper` is built inside a `@Sendable` builder function, which cannot capture `Service.SafeDIOverrides`,
		// so `Wrapper`'s configuration holds a `@Sendable` closure that returns it, read into a local before the function.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.canonicalModules(appCaller: Self.canonicalBoard),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Board {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            wrapperBuilder: Wrapper.SafeDIMockConfiguration = .init()
		        ) {
		            self.wrapperBuilder = wrapperBuilder
		        }

		        let wrapperBuilder: Wrapper.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Board {
		        let __safeDI_wrapperBuilder__wrapperBuilder_analytics_safeDIBuilder = safeDIOverrides.wrapperBuilder.analytics
		        let __safeDI_wrapperBuilder__wrapperBuilder_service_safeDIBuilder = safeDIOverrides.wrapperBuilder.service
		        let __safeDI_wrapperBuilder__safeDIBuilder = safeDIOverrides.wrapperBuilder.safeDIBuilder
		        @Sendable func __safeDI_wrapperBuilder() -> Wrapper {
		            func __safeDI_analytics() -> Analytics {
		                if let safeDIBuilder = __safeDI_wrapperBuilder__wrapperBuilder_analytics_safeDIBuilder { safeDIBuilder() } else { Analytics() }
		            }
		            let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		            _ = Service.__safeDI_Service_mock_209346FEA041FD20.self
		            let service = Service.mock(analytics: analytics.instance, theme: nil, safeDIOverrides: __safeDI_wrapperBuilder__wrapperBuilder_service_safeDIBuilder?() ?? .init())
		            return if let safeDIBuilder = __safeDI_wrapperBuilder__safeDIBuilder { safeDIBuilder(analytics, service) } else { Wrapper(analytics: analytics, service: service) }
		        }
		        let wrapperBuilder = SendableInstantiator<Wrapper>(__safeDI_wrapperBuilder)
		        return Board(wrapperBuilder: wrapperBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Wrapper {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            analytics: (@Sendable () -> Analytics)? = nil,
		            service: (@Sendable () -> Service.SafeDIOverrides)? = nil,
		            _ safeDIBuilder: (@Sendable (LazilyInstantiated<Analytics>, Service) -> Wrapper)? = nil
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let analytics: (@Sendable () -> Analytics)?
		        let service: (@Sendable () -> Service.SafeDIOverrides)?
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        let safeDIBuilder: (@Sendable (LazilyInstantiated<Analytics>, Service) -> Wrapper)?
		    }
		}
		#endif
		""" + "\n"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicMockInsideInstantiator_whenConsumerInstantiatesInstantiatorOfType() async throws {
		// M8.15: the builder function an `Instantiator<Service>` calls is the public mock's call.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.canonicalModules(appCaller: """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(analytics: LazilyInstantiated<Analytics>, serviceBuilder: Instantiator<Service>) {
			        self.analytics = analytics
			        self.serviceBuilder = serviceBuilder
			    }

			    @Instantiated let analytics: LazilyInstantiated<Analytics>
			    @Instantiated let serviceBuilder: Instantiator<Service>
			}
			"""),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
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
		            analytics: (() -> Analytics)? = nil,
		            serviceBuilder: Service.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.serviceBuilder = serviceBuilder
		        }

		        let analytics: (() -> Analytics)?
		        let serviceBuilder: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_analytics() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        }
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        _ = Service.__safeDI_Service_mock_209346FEA041FD20.self
		        func __safeDI_serviceBuilder() -> Service {
		            Service.mock(analytics: analytics.instance, theme: nil, safeDIOverrides: safeDIOverrides.serviceBuilder)
		        }
		        let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
		        return Screen(analytics: analytics, serviceBuilder: serviceBuilder)
		    }
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_wrapsPublicMockCallInErasedType_whenConsumerReachesItThroughErasure() async throws {
		// M8.19, M8.20b: `Screen` reaches `Service`, whose tree `App` cannot build, as a constant erased to `AnyServicing`,
		// through an `ErasedInstantiator` and through a `SendableErasedInstantiator`: each call of the public mock is
		// wrapped in the erased type, as an inline construction is.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
					"""
					@Instantiable
					public final class Analytics: Instantiable, Sendable {
					    public init() {}
					}

					@Instantiable
					package final class Session: Instantiable, Sendable {
					    package init(analytics: Analytics) {
					        self.analytics = analytics
					    }

					    @Received let analytics: Analytics
					}

					@Instantiable(generateMock: .public)
					public final class Service: Instantiable, Sendable {
					    package init(analytics: Analytics, session: Session) {
					        self.analytics = analytics
					        self.session = session
					    }

					    @Received let analytics: Analytics
					    @Instantiated let session: Session
					}

					public protocol Servicing: Sendable {}

					extension Service: Servicing {}

					public struct AnyServicing: Servicing {
					    public init(_ servicing: any Servicing) {}
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
					"""
					import Core

					@Instantiable(generateMock: true)
					public final class Screen: Instantiable {
					    public init(analytics: Analytics, constant: AnyServicing, erased: ErasedInstantiator<(), AnyServicing>, sendableErased: SendableErasedInstantiator<(), AnyServicing>) {
					        self.analytics = analytics
					        self.constant = constant
					        self.erased = erased
					        self.sendableErased = sendableErased
					    }

					    @Instantiated let analytics: Analytics
					    @Instantiated(fulfilledByType: "Service", erasedToConcreteExistential: true) let constant: AnyServicing
					    @Instantiated(fulfilledByType: "Service", erasedToConcreteExistential: true) let erased: ErasedInstantiator<(), AnyServicing>
					    @Instantiated(fulfilledByType: "Service", erasedToConcreteExistential: true) let sendableErased: SendableErasedInstantiator<(), AnyServicing>
					}
					""",
				], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            constant: Service.SafeDIOverrides = .init(),
		            erased: Service.SafeDIOverrides = .init(),
		            sendableErased: (@Sendable () -> Service.SafeDIOverrides)? = nil
		        ) {
		            self.analytics = analytics
		            self.constant = constant
		            self.erased = erased
		            self.sendableErased = sendableErased
		        }

		        let analytics: (() -> Analytics)?
		        let constant: Service.SafeDIOverrides
		        let erased: Service.SafeDIOverrides
		        let sendableErased: (@Sendable () -> Service.SafeDIOverrides)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self
		        let constant = AnyServicing(Service.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.constant))
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self
		        func __safeDI_erased() -> AnyServicing {
		            AnyServicing(Service.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.erased))
		        }
		        let erased = ErasedInstantiator<(), AnyServicing>(__safeDI_erased)
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self
		        let __safeDI_sendableErased__safeDIBuilder = safeDIOverrides.sendableErased
		        @Sendable func __safeDI_sendableErased() -> AnyServicing {
		            AnyServicing(Service.mock(analytics: analytics, safeDIOverrides: __safeDI_sendableErased__safeDIBuilder?() ?? .init()))
		        }
		        let sendableErased = SendableErasedInstantiator<(), AnyServicing>(__safeDI_sendableErased)
		        return Screen(analytics: analytics, constant: constant, erased: erased, sendableErased: sendableErased)
		    }
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesConsumersOwnReceive_whenConsumerAndPublicMockBothReceiveLabelOnlyIfAvailable() async throws {
		// M8.13: `Screen` receives `theme` only if available itself, so its mock takes `theme` as an override, which the
		// call hands `Service`'s mock, as the inline mock hands it `TokenCache`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.canonicalModules(appCaller: """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(theme: Theme?, service: Service) {
			        self.theme = theme
			        self.service = service
			    }

			    @Received(onlyIfAvailable: true) let theme: Theme?
			    @Received let service: Service
			}
			"""),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
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
		            service: Service.SafeDIOverrides = .init(),
		            theme: Theme? = nil
		        ) {
		            self.service = service
		            self.theme = theme
		        }

		        let service: Service.SafeDIOverrides
		        let theme: Theme?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let theme: Theme? = safeDIOverrides.theme
		        _ = Service.__safeDI_Service_mock_209346FEA041FD20.self
		        let service = Service.mock(analytics: nil, theme: theme, safeDIOverrides: safeDIOverrides.service)
		        return Screen(theme: theme, service: service)
		    }
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingView_whenTargetTheXcodeProjectPluginBuildsCannotBuildTreeOfTypeWithPublicMock() async {
		// M8.24: without a target graph no module is known, so `Service`'s public mock cannot be called, and its tree is
		// built inline, where `TokenCache` is `internal`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = NormalizedFilePath(fixtures["Core"]!.compilerPath(of: "Service.swift")).path
			return """
			\(servicePath):4:1: error: `Service` has a public `mock()`, but it cannot be called from a target the Xcode project plugin builds, and `TokenCache` is `internal`. Build this target's mocks in a SwiftPM package target.
			\(servicePath):5:5: error: `Service` has a public `mock()`, but it cannot be called from a target the Xcode project plugin builds, and `TokenCache`’s initializer is `internal`. Build this target's mocks in a SwiftPM package target.
			\(servicePath):10:5: error: `Service` has a public `mock()`, but it cannot be called from a target the Xcode project plugin builds, and `Service`’s initializer is `internal`. Build this target's mocks in a SwiftPM package target.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.unknownModuleModules(omitsCoreModuleName: false),
				integration: .swiftPackagePlugin,
				writesTargetGraph: false,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingView_whenModuleInfoOfTypeWithPublicMockNamesNoModule() async {
		// M8.25: `Core`'s module info names no module, so `Service`'s public mock cannot be called from `App`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Service.swift"]):4:1: error: `Service` has a public `mock()`, but it cannot be called from a module whose module info names no module, and `TokenCache` is `internal`. Generate the module info of the module that declares `Service` with `--module-name`.
			\(fixtures["Core"]!["Service.swift"]):5:5: error: `Service` has a public `mock()`, but it cannot be called from a module whose module info names no module, and `TokenCache`’s initializer is `internal`. Generate the module info of the module that declares `Service` with `--module-name`.
			\(fixtures["Core"]!["Service.swift"]):10:5: error: `Service` has a public `mock()`, but it cannot be called from a module whose module info names no module, and `Service`’s initializer is `internal`. Generate the module info of the module that declares `Service` with `--module-name`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.unknownModuleModules(omitsCoreModuleName: true),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicMock_whenConsumerCannotCallTypesCustomMock() async throws {
		// A type whose public mock calls its `customMockName` method is built inline with that method where the consumer
		// can call it; `App` cannot call the `internal` `customMock`, so it calls the public `mock()`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
				import SafeDI

				@Instantiable(generateMock: .public, customMockName: "customMock")
				public final class Service: Instantiable {
				    public init() {}

				    static func customMock() -> Service {
				        Service()
				    }
				}
				"""]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
				import Core
				import SafeDI

				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Received let service: Service
				}
				"""], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
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
		            service: (() -> Service)? = nil
		        ) {
		            self.service = service
		        }

		        let service: (() -> Service)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Service.__safeDI_Service_mock_CBF29CE484222325.self
		        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service.mock() }
		        return Screen(service: service)
		    }
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicMock_whenConsumerCannotBuildDependencyTypesTreeReceives() async throws {
		// `App` can construct `Service` itself, but not `Space.Shelf`, which `Service`'s tree receives and an inline mock
		// would build beside it, so it calls the public `mock()`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
				import SafeDI

				public enum Space {}

				public extension Space {
				    @Instantiable
				    final class Shelf: Instantiable {
				        init() {}
				    }
				}

				@Instantiable(generateMock: .public)
				public final class Service: Instantiable {
				    package init(shelf: Space.Shelf) {
				        self.shelf = shelf
				    }

				    @Received let shelf: Space.Shelf
				}
				"""]),
				ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Screen.swift": """
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
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
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
		            self.service = service
		        }

		        let service: Service.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Service.__safeDI_Service_mock_CBCD36FF0797CB15.self
		        let service = Service.mock(shelf: nil, safeDIOverrides: safeDIOverrides.service)
		        return Screen(service: service)
		    }
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsSharedDependencyOnceForEveryCall_whenTwoPublicMocksBuildIt() async throws {
		// M8.8b: both public mocks build `analytics` when passed `nil`, and the inline mock would share the one it promotes,
		// so `App`'s mock builds it once and passes it to both calls.
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
			import SafeDI

			@Instantiable
			public final class Analytics: Instantiable {
			    public init() {}
			}

			@Instantiable
			package struct TokenCache: Instantiable {
			    package init() {}
			}

			@Instantiable(generateMock: .public)
			public struct Service: Instantiable {
			    package init(analytics: Analytics, tokenCache: TokenCache) {
			        self.analytics = analytics
			        self.tokenCache = tokenCache
			    }

			    @Received let analytics: Analytics
			    @Instantiated let tokenCache: TokenCache
			}

			@Instantiable(generateMock: .public)
			public struct Vault: Instantiable {
			    package init(analytics: Analytics, tokenCache: TokenCache) {
			        self.analytics = analytics
			        self.tokenCache = tokenCache
			    }

			    @Received let analytics: Analytics
			    @Instantiated let tokenCache: TokenCache
			}
			"""]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(service: Service, vault: Vault) {
			        self.service = service
			        self.vault = vault
			    }

			    @Received let service: Service
			    @Received let vault: Vault
			}
			"""], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules,
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
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
		            analytics: (() -> Analytics)? = nil,
		            service: Service.SafeDIOverrides = .init(),
		            vault: Vault.SafeDIOverrides = .init()
		        ) {
		            self.analytics = analytics
		            self.service = service
		            self.vault = vault
		        }

		        let analytics: (() -> Analytics)?
		        let service: Service.SafeDIOverrides
		        let vault: Vault.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        _ = Service.__safeDI_Service_mock_81027395670D1D21.self
		        let service = Service.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.service)
		        _ = Vault.__safeDI_Vault_mock_81027395670D1D21.self
		        let vault = Vault.mock(analytics: analytics, safeDIOverrides: safeDIOverrides.vault)
		        return Screen(service: service, vault: vault)
		    }
		}
		#endif
		"""])
		try expectEveryModuleCompiled(output)
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [DifferentialValueProbe("Screen.mock()")])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The canonical fixture's `Core` module (the shape matrix's section 0), with `appCaller` in `App`, another package.
	/// M7.1's modules: `Service`'s tree holds a hole, `userService`, which `DefaultUserService` fulfills only where `App`
	/// declares it, and the package `Session`, which keeps `App` from building the tree; `Profile`'s public initializer
	/// proves `AnyUserService` `public`.
	private static func holeModules(app: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
				"""
				@Instantiable
				public final class Analytics: Instantiable {
				    public init() {}
				}

				@Instantiable
				package final class Session: Instantiable {
				    package init() {}
				}

				public protocol UserService {}

				public struct AnyUserService: UserService {
				    public init(_ userService: any UserService) {}
				}

				@Instantiable
				public struct Profile: Instantiable {
				    public init(userService: AnyUserService) {
				        self.userService = userService
				    }

				    @Received let userService: AnyUserService
				}

				@Instantiable(generateMock: .public)
				public struct Service: Instantiable {
				    package init(analytics: Analytics, session: Session, userService: AnyUserService) {
				        self.analytics = analytics
				        self.session = session
				        self.userService = userService
				    }

				    @Received let analytics: Analytics
				    @Instantiated let session: Session
				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [app], dependencies: ["Core"]),
		]
	}

	/// M8.27's modules: `Service`'s hole `routerBuilder`, an `ErasedInstantiator` of `AnyRouting`, which `Profile`'s
	/// public initializer proves `public`, is fulfilled by `App`'s `Router`; the scope struct carries the `analytics`
	/// `Service` receives, which a call inside the fill passes on.
	private static func lazyCycleThroughFillModules(router: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
				"""
				@Instantiable
				package final class Session: Instantiable {
				    package init() {}
				}

				public protocol Routing {}

				public struct AnyRouting {
				    public init(_ routing: any Routing) {}
				}

				@Instantiable
				public struct Profile: Instantiable {
				    public init(routing: AnyRouting) {
				        self.routing = routing
				    }

				    @Received let routing: AnyRouting
				}

				@Instantiable
				public final class Analytics: Instantiable {
				    public init() {}
				}

				@Instantiable(generateMock: .public)
				public final class Service: Instantiable {
				    package init(analytics: Analytics, session: Session, routerBuilder: ErasedInstantiator<(), AnyRouting>) {
				        self.analytics = analytics
				        self.session = session
				        self.routerBuilder = routerBuilder
				    }

				    @Received let analytics: Analytics
				    @Instantiated let session: Session
				    @Instantiated(fulfilledByType: "Router", erasedToConcreteExistential: true) let routerBuilder: ErasedInstantiator<(), AnyRouting>
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
				"""
				import Core

				\(router)
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
			], dependencies: ["Core"]),
		]
	}

	private static let holeScreen = """
	import Core

	@Instantiable(generateMock: true)
	public final class Screen: Instantiable {
	    public init(analytics: Analytics, service: Service) {
	        self.analytics = analytics
	        self.service = service
	    }

	    @Instantiated let analytics: Analytics
	    @Instantiated let service: Service
	}
	"""

	private static let defaultUserService = """
	@Instantiable
	public final class DefaultUserService: UserService, Instantiable {
	    public init(analytics: Analytics) {
	        self.analytics = analytics
	    }

	    @Received let analytics: Analytics
	}
	"""

	/// Compares the values the mocks of `modules`, as `output` generated them, build for `probes` with what internal
	/// mocks build inline when every declaration of `modules` is in one module and every public mock is internal, which
	/// nothing keeps from building every tree inline: a public mock must build what the inline mock would, apart from
	/// `exemptions`.
	private mutating func expectValuesAgreeWithInlineMocks(
		of modules: [ModuleFixture],
		output: MultiModuleTestOutput,
		probes: [DifferentialValueProbe],
		exempting exemptions: [DifferentialValueDifference] = [],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let moduleNames = Set(modules.map(\.name))
		func inline(_ source: String) -> String {
			source
				.split(separator: "\n", omittingEmptySubsequences: false)
				.filter { line in !moduleNames.contains { line == "import \($0)" } }
				.joined(separator: "\n")
				.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true")
		}
		var inlineFiles = [String: String]()
		for module in modules {
			for (fileName, content) in module.swiftFileContentByFilePath {
				inlineFiles["\(module.name)_\(fileName)"] = inline(content)
			}
			for (index, content) in module.swiftFileContent.enumerated() {
				inlineFiles["\(module.name)_File\(index).swift"] = inline(content)
			}
		}
		let inlineModules = [ModuleFixture(name: modules[0].name, packageName: modules[0].packageName, swiftFileContentByFilePath: inlineFiles)]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		func path(of modules: [ModuleFixture], output: MultiModuleTestOutput) throws -> DifferentialValuePath {
			try DifferentialValuePath(modules: modules.map { module in
				var fixtureFiles = module.swiftFileContentByFilePath
				for (index, content) in module.swiftFileContent.enumerated() {
					fixtureFiles["File\(index).swift"] = content
				}
				return try DifferentialValueModule(
					name: module.name,
					packageName: module.packageName,
					dependencyModuleNames: module.dependencies,
					fixtureFiles: fixtureFiles,
					generatedFiles: #require(output.modules[module.name], sourceLocation: sourceLocation).generatedFiles,
				)
			})
		}
		try expectDifferentialValuesAgree(
			feature: path(of: modules, output: output),
			knownRight: path(of: inlineModules, output: inlineOutput),
			probes: probes,
			exempting: exemptions,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	private static func canonicalModules(appCaller: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Canonical.swift": canonicalCore]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Caller.swift": appCaller], dependencies: ["Core"]),
		]
	}

	private static let canonicalCore = """
	import SafeDI

	@Instantiable
	public final class Analytics: Instantiable, Sendable {
	    public init() {}
	}

	@Instantiable
	public struct Theme: Instantiable {
	    public init() {}
	}

	public protocol Logger {}

	@Instantiable(fulfillingAdditionalTypes: [Logger.self])
	public struct ConsoleLogger: Logger, Instantiable {
	    public init() {}
	}

	@Instantiable(fulfillingAdditionalTypes: [Logger.self], mockOnly: true)
	package final class FakeLogger: Logger {
	    package static func mock(verbose: Bool = false) -> FakeLogger {
	        FakeLogger()
	    }
	}

	@Instantiable
	package struct Session: Instantiable {
	    package init() {}
	}

	package struct Policy {
	    package static let standard = Policy()
	}

	enum Defaults {
	    static let capacity = 10
	    static let name: String? = "service"
	    static let policy: Policy? = .standard
	    static let label: String? = "dash"
	}

	@Instantiable
	package struct TokenCache: Instantiable {
	    static let defaultCapacity = Defaults.capacity

	    package init(analytics: Analytics, session: Session, theme: Theme?, capacity: Int = defaultCapacity) {
	        self.analytics = analytics
	        self.session = session
	        self.theme = theme
	    }

	    @Received let analytics: Analytics
	    @Received let session: Session
	    @Received(onlyIfAvailable: true) let theme: Theme?
	}

	@Instantiable(generateMock: .public)
	public struct Service: Instantiable {
	    package init(analytics: LazilyInstantiated<Analytics>, logger: any Logger, tokenCache: TokenCache, retries: Int = 3, name: String? = Defaults.name, policy: Policy? = Defaults.policy) {
	        self.analytics = analytics
	        self.logger = logger
	        self.tokenCache = tokenCache
	    }

	    @Received let analytics: LazilyInstantiated<Analytics>
	    @Instantiated let logger: any Logger
	    @Instantiated let tokenCache: TokenCache
	}

	@Instantiable
	@MainActor
	package final class ViewModel: Instantiable {
	    nonisolated static let defaultTitle: String? = "title"

	    package init(title: String? = defaultTitle) {}
	}

	@Instantiable(generateMock: .public)
	@MainActor
	public struct Dashboard: Instantiable {
	    package init(vm: ViewModel, label: String? = Defaults.label) {
	        self.vm = vm
	    }

	    @Instantiated let vm: ViewModel
	}
	"""

	private static let canonicalAppCaller = """
	import Core

	#if DEBUG
	func callPublicTiers() {
	    _ = Service.mock()
	    _ = Service.mock(retries: 9, analytics: Analytics(), theme: Theme(), safeDIOverrides: .init(logger: .init(verbose: true), analytics: { Analytics() }, tokenCache: .init(capacity: 5), name: nil))
	    _ = Service.__safeDI_Service_mock_209346FEA041FD20.self
	}

	@MainActor func callDashboard() {
	    _ = Dashboard.mock()
	    _ = Dashboard.mock(label: "custom", safeDIOverrides: .init(vm: .init(title: nil)))
	}
	#endif
	"""

	/// M2.23c's modules: `AppFilter` provides `filter` and receives `service` only if available, and `Service`'s public
	/// tier omits `filter`, which `TokenCache` receives only if available.
	private static func softEdgeModules(screenDeclaresFilterFirst: Bool) -> [ModuleFixture] {
		let filterDeclaration = "@Instantiated let filter: any FilterProtocol"
		let serviceDeclaration = "@Instantiated let service: Service"
		let declarations = screenDeclaresFilterFirst ? [filterDeclaration, serviceDeclaration] : [serviceDeclaration, filterDeclaration]
		return [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
			import SafeDI

			public protocol FilterProtocol {}

			@Instantiable
			package struct TokenCache: Instantiable {
			    package init(filter: (any FilterProtocol)?) {
			        self.filter = filter
			    }

			    @Received(onlyIfAvailable: true) let filter: (any FilterProtocol)?
			}

			@Instantiable(generateMock: .public)
			public struct Service: Instantiable {
			    package init(tokenCache: TokenCache) {
			        self.tokenCache = tokenCache
			    }

			    @Instantiated let tokenCache: TokenCache
			}
			"""]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
			import Core
			import SafeDI

			@Instantiable(fulfillingAdditionalTypes: [FilterProtocol.self])
			public struct AppFilter: FilterProtocol, Instantiable {
			    public init(service: Service?) {
			        self.service = service
			    }

			    @Received(onlyIfAvailable: true) let service: Service?
			}

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(filter: any FilterProtocol, service: Service) {
			        self.filter = filter
			        self.service = service
			    }

			    \(declarations[0])
			    \(declarations[1])
			}
			"""], dependencies: ["Core"]),
		]
	}

	/// M8.33d's modules: `Mid.Outer`, a public mock in another package, builds `Core.Service` through its public tier,
	/// which omits `filter`; `App.AppRoot` builds `Outer` through its public mock.
	private static func chainModules(appRootForwardsFilter: Bool) -> [ModuleFixture] {
		let appRootFilter = appRootForwardsFilter ? "\n    @Forwarded let filter: Filter" : ""
		let appRootInitializer = appRootForwardsFilter ? "public init(filter: Filter, outer: Outer) {\n        self.filter = filter\n        self.outer = outer\n    }" : "public init(outer: Outer) {\n        self.outer = outer\n    }"
		return [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
			import SafeDI

			public struct Filter {
			    public init() {}
			}

			@Instantiable
			package struct TokenCache: Instantiable {
			    package init(filter: Filter?) {
			        self.filter = filter
			    }

			    @Received(onlyIfAvailable: true) let filter: Filter?
			}

			@Instantiable(generateMock: .public)
			public struct Service: Instantiable {
			    package init(tokenCache: TokenCache) {
			        self.tokenCache = tokenCache
			    }

			    @Instantiated let tokenCache: TokenCache
			}
			"""]),
			ModuleFixture(name: "Mid", packageName: "mid", swiftFileContentByFilePath: ["Outer.swift": """
			import Core
			import SafeDI

			@Instantiable(generateMock: .public)
			public struct Outer: Instantiable {
			    package init(service: Service) {
			        self.service = service
			    }

			    @Instantiated let service: Service
			}
			"""], dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["AppRoot.swift": """
			import Core
			import Mid
			import SafeDI

			@Instantiable(generateMock: true)
			public struct AppRoot: Instantiable {
			    \(appRootInitializer)
			\(appRootFilter)
			    @Instantiated let outer: Outer
			}
			"""], dependencies: ["Core", "Mid"]),
		]
	}

	/// R11's modules: `Core` generates its mocks under `TESTING`, and `App`, whose mock calls `Service`'s public mock,
	/// under `appMockCondition`, or `DEBUG` when it is `nil`.
	private static func mockConditionModules(appMockCondition: String?) -> [ModuleFixture] {
		[
			ModuleFixture(
				name: "Core",
				packageName: "pkg",
				swiftFileContentByFilePath: [
					"Service.swift": """
					import SafeDI

					@Instantiable
					package struct TokenCache: Instantiable {
					    package init() {}
					}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    package init(tokenCache: TokenCache) {
					        self.tokenCache = tokenCache
					    }

					    @Instantiated let tokenCache: TokenCache
					}
					""",
					"SafeDIConfiguration.swift": "#SafeDIConfiguration(mockConditionalCompilation: \"TESTING\")",
				],
				mockConditionalCompilation: "TESTING",
			),
			ModuleFixture(
				name: "App",
				packageName: "app",
				swiftFileContentByFilePath: [
					"Screen.swift": """
					import Core
					import SafeDI

					@Instantiable(generateMock: true)
					public struct Screen: Instantiable {
					    public init(service: Service) {
					        self.service = service
					    }

					    @Received let service: Service
					}
					""",
				].merging(appMockCondition.map { ["SafeDIConfiguration.swift": "#SafeDIConfiguration(mockConditionalCompilation: \"\($0)\")"] } ?? [:]) { first, _ in first },
				dependencies: ["Core"],
				mockConditionalCompilation: appMockCondition,
			),
		]
	}

	private static let canonicalBoard = """
	import Core
	import SafeDI

	@Instantiable
	public struct Wrapper: Instantiable {
	    public init(analytics: LazilyInstantiated<Analytics>, service: Service) {
	        self.analytics = analytics
	        self.service = service
	    }

	    @Instantiated let analytics: LazilyInstantiated<Analytics>
	    @Instantiated let service: Service
	}

	@Instantiable(generateMock: true)
	public struct Board: Instantiable {
	    public init(wrapperBuilder: SendableInstantiator<Wrapper>) {
	        self.wrapperBuilder = wrapperBuilder
	    }

	    @Instantiated let wrapperBuilder: SendableInstantiator<Wrapper>
	}
	"""

	/// M8.24's and M8.25's modules: `Service`, with a public mock, builds an `internal` `TokenCache`.
	private static func unknownModuleModules(omitsCoreModuleName: Bool) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
			import SafeDI

			@Instantiable
			struct TokenCache: Instantiable {
			    init() {}
			}

			@Instantiable(generateMock: .public)
			public struct Service: Instantiable {
			    init(tokenCache: TokenCache) {
			        self.tokenCache = tokenCache
			    }

			    @Instantiated let tokenCache: TokenCache
			}
			"""], omitsModuleName: omitsCoreModuleName),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(service: Service) {
			        self.service = service
			    }

			    @Received let service: Service
			}
			"""], dependencies: ["Core"]),
		]
	}

	private static let canonicalScreen = """
	import Core
	import SafeDI

	@Instantiable(generateMock: true)
	public struct Screen: Instantiable {
	    public init(analytics: LazilyInstantiated<Analytics>, theme: Theme, service: Service) {
	        self.analytics = analytics
	        self.theme = theme
	        self.service = service
	    }

	    @Instantiated let analytics: LazilyInstantiated<Analytics>
	    @Instantiated let theme: Theme
	    @Received let service: Service
	}
	"""

	private func expectEveryModuleCompiled(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 }, sourceLocation: sourceLocation)
		#expect(compilation.failure == nil, sourceLocation: sourceLocation)
	}
}
