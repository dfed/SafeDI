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

/// A seam's generated initializer gives no parameter a default: a parameter received only if available – a
/// pass-through every receiver in the tree receives only if available, or the seam's own
/// `@Received(onlyIfAvailable: true)` property – is taken with its optional type, so every call, generated or
/// hand-written, writes every argument. A hand-written call therefore fails to compile when the tree gains such a
/// receive, rather than passing `nil` for it silently. Whether a parameter is received only if available still decides
/// what a generated caller passes, so it is still part of the guard.
struct SafeDIToolSeamOnlyIfAvailableParameterTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – The seam's own receive

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOwnOnlyIfAvailableReceiveWithoutDefaultOnEveryTier_whenSeamHasTwoTiers() async throws {
		// `Token` is internal, so the `token` `Detail` receives only if available gives `Screen` an internal tier beside its
		// public one. The seam's own `session`, received only if available, is a parameter of both, with its optional type
		// and no default; the public tier passes `nil` for the `token` it omits.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(session: Session, screen: Screen) {
				        self.session = session
				        self.screen = screen
				    }

				    @Instantiated let session: Session
				    @Instantiated let screen: Screen
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(session: Session?, detail: Detail) {
				        self.session = session
				        self.detail = detail
				    }

				    @Received(onlyIfAvailable: true) let session: Session?
				    @Instantiated let detail: Detail
				}
				""",
				"""
				@Instantiable
				public struct Detail: Instantiable {
				    init(token: Token?) {
				        self.token = token
				    }

				    @Received(onlyIfAvailable: true) let token: Token?
				}
				""",
				"""
				@Instantiable
				public struct Session: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				struct Token: Instantiable {
				    init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let session = Session()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_91B5820CDC525781.self
			            return Screen(session: session, token: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(session: session, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public init(session: Session?) {
			        self.init(session: session, token: nil)
			    }

			    internal init(session: Session?, token: Token?) {
			        let detail = Detail(token: token)
			        self.init(session: session, detail: detail)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_91B5820CDC525781 {}
			}
			""",
		])
	}

	// MARK: Tests – A required optional pass-through beside one received only if available

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsParameterAsRequiredOptionalOneButNamesAnotherGuard_whenEveryReceiverReceivesItOnlyIfAvailable() async throws {
		// `Detail` receives `session: Session?` only if available in one graph and requires it in the other. Both seams take
		// `session: Session?` with no default, so the generated initializers read the same; whether the parameter is
		// received only if available decides what a generated caller passes, so the guards differ, and a call computed for
		// one names an enum the other's module does not generate.
		let onlyIfAvailableOutput = try await executeSafeDIToolTest(
			swiftFileContent: Self.sessionPassThroughFixture(receive: "@Received(onlyIfAvailable: true) let session: Session?"),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		let requiredOutput = try await executeSafeDIToolTest(
			swiftFileContent: Self.sessionPassThroughFixture(receive: "@Received let session: Session?"),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(onlyIfAvailableOutput.dependencyTreeFiles == Self.sessionPassThroughOutput(guardName: "__safeDI_Screen_75FDE4A4CAE60A7D"))
		#expect(requiredOutput.dependencyTreeFiles == Self.sessionPassThroughOutput(guardName: "__safeDI_Screen_8FA1C5921394D121"))
	}

	// MARK: Tests – The public mock of a seam

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsNilDefaultOnPublicMockOnly_whenSeamWithPassThroughReceivedOnlyIfAvailableDeclaresPublicMock() async throws {
		// A mock never calls a seam's generated initializer. The seam's initializer takes `logger: Logger?` with no default,
		// while its public mock, a different mechanism, still defaults the parameter it takes for `logger` to `nil`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.screen.replacingOccurrences(of: "@Instantiable(generateDependencyTree: true)", with: "@Instantiable(generateDependencyTree: true, generateMock: .public)"),
				Self.cache(receivingAnalytics: false),
			] + Self.supportingTypes,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles == ["Screen+SafeDI.swift": generatedFileHeader + Self.screenInitializer])
		#expect(output.mockFiles == ["Screen+SafeDIMock.swift": generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            database: (() -> Database)? = nil,
		            cache: ((Database, Logger?) -> Cache)? = nil,
		            user: (() -> User)? = nil
		        ) {
		            self.database = database
		            self.cache = cache
		            self.user = user
		        }

		        public let database: (() -> Database)?
		        public let cache: ((Database, Logger?) -> Cache)?
		        public let user: (() -> User)?
		    }

		    public static func mock(
		        database: Database? = nil,
		        logger: Logger? = nil,
		        user: User? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let database = if let database { database } else if let safeDIBuilder = safeDIOverrides.database { safeDIBuilder() } else { Database() }
		        let cache = if let safeDIBuilder = safeDIOverrides.cache { safeDIBuilder(database, logger) } else { Cache(database: database, logger: logger) }
		        let user = if let user { user } else if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        return Screen(user: user, cache: cache)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_A9FC6297100C9E3B {}
		}
		#endif
		"""])
	}

	// MARK: Tests – Both multi-module integrations

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamPassingNilUnderGuardOfDeclaringModule_whenPassThroughReceivedOnlyIfAvailableIsDeclaredInAnotherModule(integration: MultiModuleIntegration) async throws {
		// The Manual's `Screen` split across two modules: `App` computes `Screen`'s signature from `Feature`'s declarations,
		// whichever way it reads them, so its call passes `nil` for `logger` and names the guard `Feature` generates.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.feature(receivingAnalytics: false),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [Self.root], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let callerComment = integration.seamCallComment(type: "Screen", declaringModule: "Feature")
		let rootCode = """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        let user = User()
		        let database = Database()
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_154FFE4ADBF72F8B.self\(callerComment)
		            return Screen(user: user, database: database, logger: nil)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, database: database, screen: screen)
		    }
		}
		"""
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.screenInitializer])
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + rootCode])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == ["Screen+SafeDI.swift": generatedFileHeader + Self.screenInitializer])
			#expect(output.modules["App"]?.generatedFiles == ["Root+SafeDI.swift": generatedFileHeader + rootCode])
		}
		try expectEveryModuleCompiled(output)
	}

	// MARK: Tests – A hand-written call

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compile_failsAtHandWrittenCall_whenCallOmitsPassThroughReceivedOnlyIfAvailable() async throws {
		// Code that does not use SafeDI yet calls `Screen`'s generated initializer by hand. It must write `logger`, which
		// the tree receives only if available, as a generated call does.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.feature(receivingAnalytics: false),
				Self.legacy(calling: "Screen(user: user, database: database)"),
			],
			integration: .swiftPackagePlugin,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["Feature"]?.generatedFiles == ["Screen+SafeDI.swift": generatedFileHeader + Self.screenInitializer])
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation)
		#expect(compilation.modules.map(\.moduleName) == ["Feature", "Legacy"])
		#expect(compilation.modules.map { $0.exitCode == 0 } == [true, false])
		let failure = try #require(compilation.failure)
		#expect(failure.standardError.contains("Legacy.swift:5:42: error: missing argument for parameter 'logger' in call"), "Unexpected compiler output \(failure.standardError)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compile_failsAtHandWrittenCallThatCompiledBefore_whenTreeGainsReceiveOnlyIfAvailable() async throws {
		// The hand-written call writes every argument `Screen`'s initializer takes. When `Cache` comes to receive `analytics`
		// only if available, the initializer takes it and the guard is renamed, and the call that compiled before fails at
		// the new parameter instead of passing `nil` for it.
		let call = "Screen(user: user, database: database, logger: nil)"
		let before = try await executeSafeDIToolMultiModuleTest(
			modules: [Self.feature(receivingAnalytics: false), Self.legacy(calling: call)],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		let after = try await executeSafeDIToolMultiModuleTest(
			modules: [Self.feature(receivingAnalytics: true), Self.legacy(calling: call)],
			integration: .swiftPackagePlugin,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)

		#expect(before.modules["Feature"]?.generatedFiles == ["Screen+SafeDI.swift": generatedFileHeader + Self.screenInitializer])
		#expect(after.modules["Feature"]?.generatedFiles == ["Screen+SafeDI.swift": generatedFileHeader + """
		extension Screen {
		    public init(user: User, analytics: Analytics?, database: Database, logger: Logger?) {
		        let cache = Cache(database: database, logger: logger, analytics: analytics)
		        self.init(user: user, cache: cache)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_C2D5D79CB9294E2F {}
		}
		"""])
		try expectEveryModuleCompiled(before)
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(after.compilation)
		#expect(compilation.modules.map(\.moduleName) == ["Feature", "Legacy"])
		#expect(compilation.modules.map { $0.exitCode == 0 } == [true, false])
		let failure = try #require(compilation.failure)
		#expect(failure.standardError.contains("Legacy.swift:5:22: error: missing argument for parameter 'analytics' in call"), "Unexpected compiler output \(failure.standardError)")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The Manual's seam: `Screen` receives `user` and instantiates `Cache`.
	private static let screen = """
	@Instantiable(generateDependencyTree: true)
	public struct Screen: Instantiable {
	    public init(user: User, cache: Cache) {
	        self.user = user
	        self.cache = cache
	    }

	    @Received let user: User
	    @Instantiated let cache: Cache
	}
	"""

	/// What `Feature` generates for `screen` beside `cache(receivingAnalytics: false)`.
	private static let screenInitializer = """
	extension Screen {
	    public init(user: User, database: Database, logger: Logger?) {
	        let cache = Cache(database: database, logger: logger)
	        self.init(user: user, cache: cache)
	    }
	}

	extension Screen {
	    public enum __safeDI_Screen_154FFE4ADBF72F8B {}
	}
	"""

	/// `Cache`, which requires `database` and receives `logger`, and, when `receivingAnalytics`, `analytics`, only if
	/// available.
	private static func cache(receivingAnalytics: Bool) -> String {
		"""
		@Instantiable
		public struct Cache: Instantiable {
		    public init(database: Database, logger: Logger?\(receivingAnalytics ? ", analytics: Analytics?" : "")) {
		        self.database = database
		        self.logger = logger\(receivingAnalytics ? "\n        self.analytics = analytics" : "")
		    }

		    @Received let database: Database
		    @Received(onlyIfAvailable: true) let logger: Logger?\(receivingAnalytics ? "\n    @Received(onlyIfAvailable: true) let analytics: Analytics?" : "")
		}
		"""
	}

	private static let supportingTypes = ["User", "Database", "Logger", "Analytics"].map { name in
		"""
		@Instantiable
		public struct \(name): Instantiable {
		    public init() {}
		}
		"""
	}

	/// Module `Feature`, which declares `screen` and its tree.
	private static func feature(receivingAnalytics: Bool) -> ModuleFixture {
		ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [screen, cache(receivingAnalytics: receivingAnalytics)] + supportingTypes)
	}

	/// A root of module `App` that holds `user` and `database`, and not `logger`.
	private static let root = """
	import Feature

	@Instantiable(isRoot: true)
	public struct Root: Instantiable {
	    public init(user: User, database: Database, screen: Screen) {
	        self.user = user
	        self.database = database
	        self.screen = screen
	    }

	    @Instantiated let user: User
	    @Instantiated let database: Database
	    @Instantiated let screen: Screen
	}
	"""

	/// Module `Legacy`, which does not use SafeDI and builds a `Screen` with `call`, a hand-written call of its generated
	/// initializer.
	private static func legacy(calling call: String) -> ModuleFixture {
		ModuleFixture(name: "Legacy", packageName: "Shop", swiftFileContentByFilePath: ["Legacy.swift": """
		import Feature

		public func makeScreen(user: User, database: Database) -> Screen {
		    \(call)
		}
		"""], dependencies: ["Feature"])
	}

	/// A seam `Screen` whose `Detail` takes `session: Session?` with `receive`, beneath a `Feature` that forwards it.
	private static func sessionPassThroughFixture(receive: String) -> [String] {
		[
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(featureBuilder: Instantiator<Feature>) {
			        self.featureBuilder = featureBuilder
			    }

			    @Instantiated let featureBuilder: Instantiator<Feature>
			}
			""",
			"""
			@Instantiable
			public struct Feature: Instantiable {
			    public init(session: Session?, screen: Screen) {
			        self.session = session
			        self.screen = screen
			    }

			    @Forwarded let session: Session?
			    @Instantiated let screen: Screen
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public struct Screen: Instantiable {
			    public init(detail: Detail) {
			        self.detail = detail
			    }

			    @Instantiated let detail: Detail
			}
			""",
			"""
			@Instantiable
			public struct Detail: Instantiable {
			    public init(session: Session?) {
			        self.session = session
			    }

			    \(receive)
			}
			""",
			"""
			public struct Session {
			    public init() {}
			}
			""",
		]
	}

	/// What `sessionPassThroughFixture` generates, with the seam's guard named `guardName`.
	private static func sessionPassThroughOutput(guardName: String) -> [String: String] {
		[
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_featureBuilder(session: Session?) -> Feature {
			            func __safeDI_screen() -> Screen {
			                _ = Screen.\(guardName).self
			                return Screen(session: session)
			            }
			            let screen: Screen = __safeDI_screen()
			            return Feature(session: session, screen: screen)
			        }
			        let featureBuilder = Instantiator<Feature> {
			            __safeDI_featureBuilder(session: $0)
			        }
			        self.init(featureBuilder: featureBuilder)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public init(session: Session?) {
			        let detail = Detail(session: session)
			        self.init(detail: detail)
			    }
			}

			extension Screen {
			    public enum \(guardName) {}
			}
			""",
		]
	}

	private func expectEveryModuleCompiled(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 }, sourceLocation: sourceLocation)
	}
}
