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
@testable import SafeDICore
@testable import SafeDITool

/// A type declared with `generateDependencyTree: true` – a seam – gets its dependency tree generated in the module
/// that declares it, as an initializer that takes what the tree needs from outside as parameters, and every tree that
/// reaches it calls that initializer.
struct SafeDIToolDependencyTreeGenerationTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – One module

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesSeamInitializerAndCallsIt_whenRootReachesSeamInSameModule() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
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
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(user: User, cache: Cache) {
				        self.user = user
				        self.cache = cache
				    }

				    @Received let user: User
				    @Instantiated let cache: Cache
				}
				""",
				"""
				@Instantiable
				public struct Cache: Instantiable {
				    public init(database: Database, logger: Logger?) {
				        self.database = database
				        self.logger = logger
				    }

				    @Received let database: Database
				    @Received(onlyIfAvailable: true) let logger: Logger?
				}
				""",
				"""
				@Instantiable
				public struct User: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public struct Database: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public struct Logger: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles.keys.sorted() == ["Root+SafeDI.swift", "Screen+SafeDI.swift"])
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(user: User, database: Database, logger: Logger?) {
		        let cache = Cache(database: database, logger: logger)
		        self.init(user: user, cache: cache)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_154FFE4ADBF72F8B {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let user = User()
		        let database = Database()
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_154FFE4ADBF72F8B.self
		            return Screen(user: user, database: database, logger: nil)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, database: database, screen: screen)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesEachKindOfParameter_whenSeamForwardsReceivesAndPassesThrough() async throws {
		// The seam's own `@Received` and `@Forwarded` properties come first, in declaration order; then each property
		// the tree receives from outside, in label order: required where some receiver requires it, and optional, with no
		// default, where every receiver receives it only if available.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(database: Database, session: Session, screenBuilder: Instantiator<Screen>) {
				        self.database = database
				        self.session = session
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated let database: Database
				    @Instantiated let session: Session
				    @Instantiated let screenBuilder: Instantiator<Screen>
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(user: User, database: Database, cache: Cache, tracker: Tracker) {
				        self.user = user
				        self.database = database
				        self.cache = cache
				        self.tracker = tracker
				    }

				    @Forwarded let user: User
				    @Received let database: Database
				    @Instantiated let cache: Cache
				    @Instantiated let tracker: Tracker
				}
				""",
				"""
				@Instantiable
				public struct Cache: Instantiable {
				    public init(database: Database, logger: Logger?) {
				        self.database = database
				        self.logger = logger
				    }

				    @Received let database: Database
				    @Received(onlyIfAvailable: true) let logger: Logger?
				}
				""",
				"""
				@Instantiable
				public struct Tracker: Instantiable {
				    public init(session: Session, user: User) {
				        self.session = session
				        self.user = user
				    }

				    @Received let session: Session
				    @Received let user: User
				}
				""",
				"""
				@Instantiable
				public struct Session: Instantiable {
				    public init() {}
				}
				""",
				"""
				public struct User {
				    public init() {}
				}
				""",
				Self.databaseContent,
				Self.loggerContent,
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(user: User, database: Database, logger: Logger?, session: Session) {
		        let cache = Cache(database: database, logger: logger)
		        let tracker = Tracker(session: session, user: user)
		        self.init(user: user, database: database, cache: cache, tracker: tracker)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_064BB97DAE4CBDB8 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let database = Database()
		        let session = Session()
		        func __safeDI_screenBuilder(user: User) -> Screen {
		            _ = Screen.__safeDI_Screen_064BB97DAE4CBDB8.self
		            return Screen(user: user, database: database, logger: nil, session: session)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(user: $0)
		        }
		        self.init(database: database, session: session, screenBuilder: screenBuilder)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesPropertyBeforeRename_whenSeamTreeRenamesReceivedProperty() async throws {
		// A rename inside the seam's tree is the tree's to make: the parameter is the property the alias is created
		// from. A rename declared above the seam is what the tree receives: the parameter is the renamed property.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(database: Database, storage: Database, screen: Screen) {
				        self.database = database
				        self.storage = storage
				        self.screen = screen
				    }

				    @Instantiated let database: Database
				    @Received(fulfilledByDependencyNamed: "database", ofType: Database.self) let storage: Database
				    @Instantiated let screen: Screen
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(cache: Cache, archive: Archive) {
				        self.cache = cache
				        self.archive = archive
				    }

				    @Instantiated let cache: Cache
				    @Instantiated let archive: Archive
				}
				""",
				"""
				@Instantiable
				public struct Cache: Instantiable {
				    public init(store: Database) {
				        self.store = store
				    }

				    @Received(fulfilledByDependencyNamed: "database", ofType: Database.self) let store: Database
				}
				""",
				"""
				@Instantiable
				public struct Archive: Instantiable {
				    public init(storage: Database) {
				        self.storage = storage
				    }

				    @Received let storage: Database
				}
				""",
				Self.databaseContent,
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		let cachePath = output.fixtures["Cache.swift"]
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(database: Database, storage: Database) {
		        func __safeDI_cache() -> Cache {
		            #sourceLocation(file: "\(cachePath)", line: 7)
		            let store: Database = database
		            #sourceLocation()
		            return Cache(store: store)
		        }
		        let cache: Cache = __safeDI_cache()
		        let archive = Archive(storage: storage)
		        self.init(cache: cache, archive: archive)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_A9B24CDAAFB23C69 {}
		}
		""")
		let rootPath = output.fixtures["Root.swift"]
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let database = Database()
		        #sourceLocation(file: "\(rootPath)", line: 10)
		        let storage: Database = database
		        #sourceLocation()
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_A9B24CDAAFB23C69.self
		            return Screen(database: database, storage: storage)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(database: database, storage: storage, screen: screen)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesRequiredOptionalParameter_whenReceiverRequiresPropertyDeclaredWithOptionalType() async throws {
		// A receiver inside the seam requires `session: Session?`, a property an outer type declares with an optional
		// type, so the parameter keeps that type and has no default: the caller passes the optional value it holds.
		// Found by the graph fuzzer (seed 139 of the `generateDependencyTree` corpus).
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
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

				    @Received let session: Session?
				}
				""",
				"""
				public struct Session {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(session: Session?) {
		        let detail = Detail(session: session)
		        self.init(detail: detail)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_8FA1C5921394D121 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_featureBuilder(session: Session?) -> Feature {
		            func __safeDI_screen() -> Screen {
		                _ = Screen.__safeDI_Screen_8FA1C5921394D121.self
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
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamReceivesPropertyOnlyIfAvailableThatReceiverInsideRequires() async {
		// The seam receives `session` only if available while `Detail`, inside its tree, requires it: the seam's own
		// receive is a parameter as declared, which provides only optional receives of `session`, so `Detail`'s is a
		// second parameter under the label. The remedy says to receive it required on the seam. Found by the graph fuzzer.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `session` as `session: Session?` on `Screen` and `session: Session` on `Detail`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `session` the same way in every type of the tree, or declare it on `Screen` as the form that provides the others: `@Received let session: Session`.
			\(fixtures["Screen.swift"]):8:5: note: `Screen` receives `session: Session?` here.
			\(fixtures["Detail.swift"]):7:5: note: `Detail` receives `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolTest(
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
					    public init(session: Session) {
					        self.session = session
					    }

					    @Received let session: Session
					}
					""",
					"""
					@Instantiable
					public struct Session: Instantiable {
					    public init() {}
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
	mutating func generate_takesParameterAtInstantiateMethodsSpelledAccess_whenExtensionWithoutModifierDeclaresPublicInstantiate() async throws {
		// An extension never caps its members: `extension Clock { public static func instantiate(…) }` declares a
		// public method whatever the extension's own level, and the extended type's access is unknown to SafeDI, so
		// the receive `instantiate(…)` declares is public, and the parameter that passes it is on the public tier.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(token: Token, screen: Screen) {
				        self.token = token
				        self.screen = screen
				    }

				    @Instantiated let token: Token
				    @Instantiated let screen: Screen
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(clock: Clock) {
				        self.clock = clock
				    }

				    @Instantiated let clock: Clock
				}
				""",
				"""
				public struct Clock {
				    public init(token: Token) {
				        self.token = token
				    }

				    let token: Token
				}

				@Instantiable
				extension Clock: Instantiable {
				    public static func instantiate(token: Token) -> Clock {
				        Clock(token: token)
				    }
				}
				""",
				"""
				@Instantiable
				public struct Token: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(token: Token) {
		        let clock: Clock = Clock.instantiate(token: token)
		        self.init(clock: clock)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_1EB503BFA23A82BA {}
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenLabelIsReceivedAsWrappersOfTwoTypes() async {
		// One label's forms collapse to one parameter only when they are one wrapper and its instance, or one
		// property and its optional form; two wrappers of different types are two properties under one label.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `session` as `session: LazilyInstantiated<Session>` on `Cache` and `session: LazilyInstantiated<Token>` on `Tracker`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.
			\(fixtures["Cache.swift"]):7:5: note: `Cache` receives `session: LazilyInstantiated<Session>` here.
			\(fixtures["Tracker.swift"]):7:5: note: `Tracker` receives `session: LazilyInstantiated<Token>` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(cache: Cache, tracker: Tracker) {
					        self.cache = cache
					        self.tracker = tracker
					    }

					    @Instantiated let cache: Cache
					    @Instantiated let tracker: Tracker
					}
					""",
					"""
					@Instantiable
					public struct Cache: Instantiable {
					    public init(session: LazilyInstantiated<Session>) {
					        self.session = session
					    }

					    @Received let session: LazilyInstantiated<Session>
					}
					""",
					"""
					@Instantiable
					public struct Tracker: Instantiable {
					    public init(session: LazilyInstantiated<Token>) {
					        self.session = session
					    }

					    @Received let session: LazilyInstantiated<Token>
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
					public struct Token: Instantiable {
					    public init() {}
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
	mutating func generate_throwsError_whenSeamsOwnReceiveAndReceiverInsideShareLabelWithDifferentTypes() async {
		// The seam's own `@Received` property is a parameter under its label, so a receiver inside its tree that
		// requires the label with another type has no parameter to be passed: the error names both.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `token` as `token: Token` on `Screen` and `token: String` on `Client`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.
			\(fixtures["Screen.swift"]):8:5: note: `Screen` receives `token: Token` here.
			\(fixtures["Client.swift"]):7:5: note: `Client` receives `token: String` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(token: Token, client: Client) {
					        self.token = token
					        self.client = client
					    }

					    @Received let token: Token
					    @Instantiated let client: Client
					}
					""",
					"""
					@Instantiable
					public struct Client: Instantiable {
					    public init(token: String) {
					        self.token = token
					    }

					    @Received let token: String
					}
					""",
					"""
					@Instantiable
					public struct Token: Instantiable {
					    public init() {}
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
	mutating func generate_declaresNarrowestTierAtSeamsOwnInitializersLevel_whenEveryParameterIsWider() async throws {
		// Every tier is capped at the seam's type's access: a seam nested in an internal enum has an internal type, so
		// the one tier its public parameter would make is internal, taking that parameter, rather than a public tier
		// beside an internal one with the same parameters.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(token: Token, screen: AnyScreen) {
				        self.token = token
				        self.screen = screen
				    }

				    @Instantiated let token: Token
				    @Instantiated(fulfilledByType: "Internals.Screen", erasedToConcreteExistential: true) let screen: AnyScreen
				}
				""",
				"""
				internal enum Internals {
				    @Instantiable(generateDependencyTree: true)
				    public struct Screen: Instantiable, ScreenProtocol {
				        public init(tracker: Tracker) {
				            self.tracker = tracker
				        }

				        @Instantiated let tracker: Tracker
				    }
				}
				""",
				"""
				public protocol ScreenProtocol {}

				public struct AnyScreen: ScreenProtocol {
				    public init(_ screen: some ScreenProtocol) {}
				}
				""",
				"""
				@Instantiable
				public struct Tracker: Instantiable {
				    public init(token: Token) {
				        self.token = token
				    }

				    @Received let token: Token
				}
				""",
				"""
				@Instantiable
				public struct Token: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Internals.Screen {
		    internal init(token: Token) {
		        let tracker = Tracker(token: token)
		        self.init(tracker: tracker)
		    }
		}

		extension Internals.Screen {
		    public enum __safeDI_Internals_Screen_E15B3D9758D01BA2 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let token = Token()
		        func __safeDI_screen() -> Internals.Screen {
		            _ = Internals.Screen.__safeDI_Internals_Screen_E15B3D9758D01BA2.self
		            return Internals.Screen(token: token)
		        }
		        let screen = AnyScreen(__safeDI_screen())
		        self.init(token: token, screen: screen)
		    }
		}
		""")
	}

	@Test(arguments: [["--module-name", "App"], []])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsSeamsTreeInlineWithComment_whenSeamIsDeclaredInAdditionalDirectory(moduleMembershipArguments: [String]) async throws {
		// A seam in a directory a `#SafeDIConfiguration` adds is in no module's own files: `scan` plans a seam's file
		// among the module's own files only, so no module generates its initializer, and a tree that reaches it
		// builds its tree inline, as it builds any other type's. Its construction says so, in the same words whether the
		// run is given `--module-name`, which names the module of no file the configuration adds, or names no module,
		// as the Xcode project plugin's run does.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				#SafeDIConfiguration(
				    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
				)
				""",
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
				@Instantiable
				public struct Session: Instantiable {
				    public init() {}
				}
				""",
			],
			additionalDirectorySwiftFileContent: [
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
				    public init(session: Session) {
				        self.session = session
				    }

				    @Received let session: Session
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: moduleMembershipArguments,
		)

		#expect(output.dependencyTreeFiles.keys.sorted() == ["Root+SafeDI.swift"])
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let session = Session()
		        func __safeDI_screen() -> Screen {
		            let detail = Detail(session: session)
		            return Screen(detail: detail) // Built inline: SafeDI does not know which module declares `Screen`, so this tree cannot call the initializer SafeDI generates for it.
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(session: session, screen: screen)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsSeamsTreeInlineWithoutComment_whenSeamIsDeclaredInAdditionalDirectory() async throws {
		// A mock builds every seam's tree inline, whether or not SafeDI knows which module declares the seam, so the
		// comment that a production construction of a seam of an unknown module ends with would give the wrong cause
		// in a mock: neither a mock that instantiates the seam nor the default of a mock's forwarded parameter, which
		// calls the seam's hand-written mock, carries it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				#SafeDIConfiguration(
				    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
				)
				""",
				"""
				@Instantiable(generateMock: true)
				public struct Holder: Instantiable {
				    public init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated let screen: Screen
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public struct Forwarder: Instantiable {
				    public init(screen: Screen) {
				        self.screen = screen
				    }

				    @Forwarded let screen: Screen
				}
				""",
			],
			additionalDirectorySwiftFileContent: [
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(detail: Detail) {
				        self.detail = detail
				    }

				    @Instantiated let detail: Detail

				    public static func mock(detail: Detail = Detail()) -> Screen {
				        Screen(detail: detail)
				    }
				}
				""",
				"""
				@Instantiable
				public struct Detail: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles.keys.sorted() == ["Forwarder+SafeDIMock.swift", "Holder+SafeDIMock.swift"])
		#expect(output.mockFiles["Forwarder+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Forwarder {
		    static func mock(
		        screen: Screen = Screen.mock()
		    ) -> Forwarder {
		        return Forwarder(screen: screen)
		    }
		}
		#endif
		""")
		#expect(output.mockFiles["Holder+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Holder {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screen: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            self.screen = screen
		        }

		        let screen: Screen.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Holder {
		        func __safeDI_screen() -> Screen {
		            let detail = if let safeDIBuilder = safeDIOverrides.screen.detail { safeDIBuilder() } else { Detail() }
		            return if let safeDIBuilder = safeDIOverrides.screen.safeDIBuilder { safeDIBuilder(detail) } else { Screen.mock(detail: detail) }
		        }
		        let screen: Screen = __safeDI_screen()
		        return Holder(screen: screen)
		    }
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsParameterDeterministically_whenLabelIsReceivedWithAndWithoutAny() async throws {
		// `any ServiceProtocol0` and `ServiceProtocol0` are one type to the compiler and to `TypeDescription ==`; the
		// forms are visited in sorted order, so the spelling each of twenty such parameters takes is the same in every
		// process – a visit in `Set` order would scramble them on nearly every run – and the guard enum hashes the
		// spelling without `any`, so a caller that spells a type differently names the same enum.
		let labels = (0..<20).map { "service\($0)" }
		var files = [
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(\(labels.map { "\($0): any \($0.replacingOccurrences(of: "service", with: "ServiceProtocol"))" }.joined(separator: ", ")), screen: Screen) {
			\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
			        self.screen = screen
			    }

			\(labels.map { "    @Instantiated(fulfilledByType: \"\($0.replacingOccurrences(of: "service", with: "Service"))\") let \($0): any \($0.replacingOccurrences(of: "service", with: "ServiceProtocol"))" }.joined(separator: "\n"))
			    @Instantiated let screen: Screen
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public struct Screen: Instantiable {
			    public init(client: Client, tracker: Tracker) {
			        self.client = client
			        self.tracker = tracker
			    }

			    @Instantiated let client: Client
			    @Instantiated let tracker: Tracker
			}
			""",
			"""
			@Instantiable
			public struct Client: Instantiable {
			    public init(\(labels.map { "\($0): \($0.replacingOccurrences(of: "service", with: "ServiceProtocol"))" }.joined(separator: ", "))) {
			\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
			    }

			\(labels.map { "    @Received let \($0): \($0.replacingOccurrences(of: "service", with: "ServiceProtocol"))" }.joined(separator: "\n"))
			}
			""",
			"""
			@Instantiable
			public struct Tracker: Instantiable {
			    public init(\(labels.map { "\($0): (any \($0.replacingOccurrences(of: "service", with: "ServiceProtocol")))?" }.joined(separator: ", "))) {
			\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
			    }

			\(labels.map { "    @Received(onlyIfAvailable: true) let \($0): (any \($0.replacingOccurrences(of: "service", with: "ServiceProtocol")))?" }.joined(separator: "\n"))
			}
			""",
		]
		for index in 0..<20 {
			files.append("""
			public protocol ServiceProtocol\(index) {}

			@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol\(index).self])
			public struct Service\(index): Instantiable, ServiceProtocol\(index) {
			    public init() {}
			}
			""")
		}
		let output = try await executeSafeDIToolTest(
			swiftFileContent: files,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(service0: any ServiceProtocol0, service1: any ServiceProtocol1, service10: any ServiceProtocol10, service11: any ServiceProtocol11, service12: any ServiceProtocol12, service13: any ServiceProtocol13, service14: any ServiceProtocol14, service15: any ServiceProtocol15, service16: any ServiceProtocol16, service17: any ServiceProtocol17, service18: any ServiceProtocol18, service19: any ServiceProtocol19, service2: any ServiceProtocol2, service3: any ServiceProtocol3, service4: any ServiceProtocol4, service5: any ServiceProtocol5, service6: any ServiceProtocol6, service7: any ServiceProtocol7, service8: any ServiceProtocol8, service9: any ServiceProtocol9) {
		        let client = Client(service0: service0, service1: service1, service2: service2, service3: service3, service4: service4, service5: service5, service6: service6, service7: service7, service8: service8, service9: service9, service10: service10, service11: service11, service12: service12, service13: service13, service14: service14, service15: service15, service16: service16, service17: service17, service18: service18, service19: service19)
		        let tracker = Tracker(service0: service0, service1: service1, service2: service2, service3: service3, service4: service4, service5: service5, service6: service6, service7: service7, service8: service8, service9: service9, service10: service10, service11: service11, service12: service12, service13: service13, service14: service14, service15: service15, service16: service16, service17: service17, service18: service18, service19: service19)
		        self.init(client: client, tracker: tracker)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_F961047489424103 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let service0: any ServiceProtocol0 = Service0()
		        let service1: any ServiceProtocol1 = Service1()
		        let service2: any ServiceProtocol2 = Service2()
		        let service3: any ServiceProtocol3 = Service3()
		        let service4: any ServiceProtocol4 = Service4()
		        let service5: any ServiceProtocol5 = Service5()
		        let service6: any ServiceProtocol6 = Service6()
		        let service7: any ServiceProtocol7 = Service7()
		        let service8: any ServiceProtocol8 = Service8()
		        let service9: any ServiceProtocol9 = Service9()
		        let service10: any ServiceProtocol10 = Service10()
		        let service11: any ServiceProtocol11 = Service11()
		        let service12: any ServiceProtocol12 = Service12()
		        let service13: any ServiceProtocol13 = Service13()
		        let service14: any ServiceProtocol14 = Service14()
		        let service15: any ServiceProtocol15 = Service15()
		        let service16: any ServiceProtocol16 = Service16()
		        let service17: any ServiceProtocol17 = Service17()
		        let service18: any ServiceProtocol18 = Service18()
		        let service19: any ServiceProtocol19 = Service19()
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_F961047489424103.self
		            return Screen(service0: service0, service1: service1, service10: service10, service11: service11, service12: service12, service13: service13, service14: service14, service15: service15, service16: service16, service17: service17, service18: service18, service19: service19, service2: service2, service3: service3, service4: service4, service5: service5, service6: service6, service7: service7, service8: service8, service9: service9)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(service0: service0, service1: service1, service2: service2, service3: service3, service4: service4, service5: service5, service6: service6, service7: service7, service8: service8, service9: service9, service10: service10, service11: service11, service12: service12, service13: service13, service14: service14, service15: service15, service16: service16, service17: service17, service18: service18, service19: service19, screen: screen)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSendableBuilderInsideSeamReadsInstanceOfWrapperParameter() async {
		// The seam's generated initializer declares `cache: LazilyInstantiated<Cache>` outside every builder function,
		// so the `@Sendable` builder of `worker`, which reads its instance, captures a wrapper that is not `Sendable`:
		// reported as it is for a wrapper the tree receives from outside it, since the inline tree no longer runs
		// this check, with the remedy to declare it `Sendable` where the caller declares it and where it is received.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Worker.swift"]):7:5: error: @Received property `cache: Cache` cannot be received inside a `@Sendable` function in chain: Screen -> Worker. SafeDI builds `workerBuilder: SendableInstantiator<Worker>` on `Screen` in a `@Sendable` function, which cannot capture `cache: LazilyInstantiated<Cache>`, which the tree of `Screen` receives from outside it, because `LazilyInstantiated<Cache>` is not `Sendable`. Declare `cache` as `SendableLazilyInstantiated<Cache>` where it is declared and where it is received as `LazilyInstantiated<Cache>` to fix. A `SendableLazilyInstantiated` requires its instance type, `Cache`, to be `Sendable`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(cache: LazilyInstantiated<Cache>, screen: Screen) {
					        self.cache = cache
					        self.screen = screen
					    }

					    @Instantiated let cache: LazilyInstantiated<Cache>
					    @Instantiated let screen: Screen
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(workerBuilder: SendableInstantiator<Worker>, holder: Holder) {
					        self.workerBuilder = workerBuilder
					        self.holder = holder
					    }

					    @Instantiated let workerBuilder: SendableInstantiator<Worker>
					    @Instantiated let holder: Holder
					}
					""",
					"""
					@Instantiable
					public struct Worker: Instantiable {
					    public init(cache: Cache) {
					        self.cache = cache
					    }

					    @Received let cache: Cache
					}
					""",
					"""
					@Instantiable
					public struct Holder: Instantiable {
					    public init(cache: LazilyInstantiated<Cache>) {
					        self.cache = cache
					    }

					    @Received let cache: LazilyInstantiated<Cache>
					}
					""",
					"""
					@Instantiable
					public struct Cache: Instantiable {
					    public init() {}
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
	mutating func generate_keepsOwnOptionalParameter_whenOnlyIfAvailableAliasOfUnwrappedFormIsDeclaredInside() async throws {
		// The seam receives `session` only if available, and `Detail` inside declares an `onlyIfAvailable` alias of
		// `session: Session`: the seam's own parameter serves, as a value that may be `nil`, from which the alias is
		// bound as an optional value – not a label collision; nothing beneath reads it, so no fallback is taken.
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
				    public init(current: Session?) {
				        self.current = current
				    }

				    @Received(fulfilledByDependencyNamed: "session", ofType: Session.self, onlyIfAvailable: true) let current: Session?
				}
				""",
				"""
				@Instantiable
				public struct Session: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		let detailPath = output.fixtures["Detail.swift"]
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(session: Session?) {
		        func __safeDI_detail() -> Detail {
		            #sourceLocation(file: "\(detailPath)", line: 7)
		            let current: Session? = session
		            #sourceLocation()
		            return Detail(current: current)
		        }
		        let detail: Detail = __safeDI_detail()
		        self.init(session: session, detail: detail)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_75FDE4A4CAE60A7D {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let session = Session()
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_75FDE4A4CAE60A7D.self
		            return Screen(session: session)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(session: session, screen: screen)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsErasedAliasAsOptional_whenItsPropertyIsRequiredOptionalParameter() async throws {
		// `Detail` requires `session: Session?`, so the parameter is `session: Session?` with no default, and
		// `Summary`'s erased `onlyIfAvailable` alias of `session: Session` is bound as an optional value, since the
		// parameter may be `nil`, rather than as `AnySession(session)` on an optional.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
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
				    public init(detail: Detail, summary: Summary) {
				        self.detail = detail
				        self.summary = summary
				    }

				    @Instantiated let detail: Detail
				    @Instantiated let summary: Summary
				}
				""",
				"""
				@Instantiable
				public struct Detail: Instantiable {
				    public init(session: Session?) {
				        self.session = session
				    }

				    @Received let session: Session?
				}
				""",
				"""
				@Instantiable
				public struct Summary: Instantiable {
				    public init(anySession: AnySession?) {
				        self.anySession = anySession
				    }

				    @Received(fulfilledByDependencyNamed: "session", ofType: Session.self, erasedToConcreteExistential: true, onlyIfAvailable: true) let anySession: AnySession?
				}
				""",
				"""
				public struct Session: SessionProtocol {
				    public init() {}
				}

				public protocol SessionProtocol {}

				public struct AnySession: SessionProtocol {
				    public init(_ session: some SessionProtocol) {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		let summaryPath = output.fixtures["Summary.swift"]
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(session: Session?) {
		        let detail = Detail(session: session)
		        func __safeDI_summary() -> Summary {
		            #sourceLocation(file: "\(summaryPath)", line: 7)
		            let anySession: AnySession? = (session as Session?).map { AnySession($0) }
		            #sourceLocation()
		            return Summary(anySession: anySession)
		        }
		        let summary: Summary = __safeDI_summary()
		        self.init(detail: detail, summary: summary)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_8FA1C5921394D121 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_featureBuilder(session: Session?) -> Feature {
		            func __safeDI_screen() -> Screen {
		                _ = Screen.__safeDI_Screen_8FA1C5921394D121.self
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
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesOptionalDeclaration_whenOnlyIfAvailableReceiveAboveSeamDeclaresPropertyOverInstantiatedOne() async throws {
		// `Feature` receives `session` only if available over `Root`'s instantiated `session`, so its tree declares
		// `session: Session?`; `Detail` inside the seam requires `session: Session?`, and the caller passes
		// `Feature`'s optional declaration to the parameter, which keeps that type.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(session: Session, feature: Feature) {
				        self.session = session
				        self.feature = feature
				    }

				    @Instantiated let session: Session
				    @Instantiated let feature: Feature
				}
				""",
				"""
				@Instantiable
				public struct Feature: Instantiable {
				    public init(session: Session?, screen: Screen) {
				        self.session = session
				        self.screen = screen
				    }

				    @Received(onlyIfAvailable: true) let session: Session?
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

				    @Received let session: Session?
				}
				""",
				"""
				@Instantiable
				public struct Session: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(session: Session?) {
		        let detail = Detail(session: session)
		        self.init(detail: detail)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_8FA1C5921394D121 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let session = Session()
		        func __safeDI_feature() -> Feature {
		            func __safeDI_screen() -> Screen {
		                _ = Screen.__safeDI_Screen_8FA1C5921394D121.self
		                return Screen(session: session)
		            }
		            let screen: Screen = __safeDI_screen()
		            return Feature(session: session, screen: screen)
		        }
		        let feature: Feature = __safeDI_feature()
		        self.init(session: session, feature: feature)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_capsEveryTierAtSeamsTypeAccess_whenSeamIsInternalAndReceiversArePublic() async throws {
		// `Internals.Screen` is internal, so no tier can be wider: its own `@Received` and `@Forwarded` properties and
		// the pass-through `Tracker` receives from a public initializer are all taken by one internal tier, rather
		// than by a public tier that could not be declared and an internal one it would redeclare.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(token: Token, session: Session, screenBuilder: ErasedInstantiator<User, AnyScreen>) {
				        self.token = token
				        self.session = session
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated let token: Token
				    @Instantiated let session: Session
				    @Instantiated(fulfilledByType: "Internals.Screen", erasedToConcreteExistential: true) let screenBuilder: ErasedInstantiator<User, AnyScreen>
				}
				""",
				"""
				internal enum Internals {
				    @Instantiable(generateDependencyTree: true)
				    public struct Screen: Instantiable, ScreenProtocol {
				        public init(user: User, session: Session, tracker: Tracker) {
				            self.user = user
				            self.session = session
				            self.tracker = tracker
				        }

				        @Forwarded let user: User
				        @Received let session: Session
				        @Instantiated let tracker: Tracker
				    }
				}
				""",
				"""
				public protocol ScreenProtocol {}

				public struct AnyScreen: ScreenProtocol {
				    public init(_ screen: some ScreenProtocol) {}
				}
				""",
				"""
				@Instantiable
				public struct Tracker: Instantiable {
				    public init(token: Token) {
				        self.token = token
				    }

				    @Received let token: Token
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
				public struct Token: Instantiable {
				    public init() {}
				}
				""",
				"""
				public struct User {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Internals.Screen {
		    internal init(user: User, session: Session, token: Token) {
		        let tracker = Tracker(token: token)
		        self.init(user: user, session: session, tracker: tracker)
		    }
		}

		extension Internals.Screen {
		    public enum __safeDI_Internals_Screen_A50891B3B6BDBBCE {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let token = Token()
		        let session = Session()
		        func __safeDI_screenBuilder(user: User) -> Internals.Screen {
		            _ = Internals.Screen.__safeDI_Internals_Screen_A50891B3B6BDBBCE.self
		            return Internals.Screen(user: user, session: session, token: token)
		        }
		        let screenBuilder = ErasedInstantiator<User, AnyScreen> {
		            AnyScreen(__safeDI_screenBuilder(user: $0))
		        }
		        self.init(token: token, session: session, screenBuilder: screenBuilder)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamsTreeReachesAdditionalDirectoryDeclarationUnderTargetGraph() async {
		// Under the plugin's target graph, a caller computes this module's seams from the files the graph lists, which
		// leave out the directory the configuration adds, so a seam whose tree reaches `Detail` there would be called
		// with another signature: reported at the seam.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: the initializer SafeDI generates for it depends on `Detail`, which is declared in a directory this module's `#SafeDIConfiguration` adds, and the modules that call that initializer cannot see that declaration, so their calls would not match the initializer. Declare `Detail` in a file of this module, or of a module it depends on.
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
					    public init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
					"""
					@Instantiable
					public struct Session: Instantiable {
					    public init() {}
					}
					""",
				],
				additionalDirectorySwiftFileContent: [
					"""
					@Instantiable
					public struct Detail: Instantiable {
					    public init(session: Session) {
					        self.session = session
					    }

					    @Received let session: Session
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
	mutating func generate_throwsError_whenInitializerGuardedByConditionOnlyGenerateHasTakesGeneratedParameters() async {
		// The generated initializer is unconditional, so a hand-written one it would redeclare in any `#if` clause is
		// a redeclaration, and the initializers a declaration reports do not depend on the clauses selected: scan,
		// without `DEBUG`, caches what it reports, and generate, with `DEBUG`, reads the cache.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: the generated initializer, `init(session: Session)`, takes the parameters of an initializer `Screen` declares at line 8, which it would redeclare. Remove that initializer, or change its parameters.
			"""
		}) {
			try await executeSafeDIToolTest(
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
					    public init(detail: Detail) {
					        self.detail = detail
					    }

					    #if DEBUG
					    public init(session: Session) {
					        self.init(detail: Detail(session: session))
					    }
					    #endif

					    @Instantiated let detail: Detail
					}
					""",
					"""
					@Instantiable
					public struct Detail: Instantiable {
					    public init(session: Session) {
					        self.session = session
					    }

					    @Received let session: Session
					}
					""",
					"""
					@Instantiable
					public struct Session: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				buildSettingArguments: ["--build-setting-active-compilation-conditions=[DEBUG]", "--build-setting-other-swift-flags=[]"],
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenNestedSeamsInitializerNamesNestedPassThroughTypeUnqualified() async {
		// The generated tier takes `session: Feature.Session`; the hand-written initializer spells the type as
		// `Session`, as its declaration does, and is compared with its argument types qualified, so it is found.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):2:5: error: SafeDI cannot generate the dependency tree of `Feature.Screen`: the generated initializer, `init(session: Feature.Session)`, takes the parameters of an initializer `Feature.Screen` declares at line 8, which it would redeclare. Remove that initializer, or change its parameters.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(session: Feature.Session, screen: Feature.Screen) {
					        self.session = session
					        self.screen = screen
					    }

					    @Instantiated let session: Feature.Session
					    @Instantiated let screen: Feature.Screen
					}
					""",
					"""
					public enum Feature {
					    @Instantiable(generateDependencyTree: true)
					    public struct Screen: Instantiable {
					        public init(detail: Detail) {
					            self.detail = detail
					        }

					        public init(session: Session) {
					            self.init(detail: Detail(session: session))
					        }

					        @Instantiated let detail: Detail
					    }

					    @Instantiable
					    public struct Detail: Instantiable {
					        public init(session: Session) {
					            self.session = session
					        }

					        @Received let session: Session
					    }

					    @Instantiable
					    public struct Session: Instantiable {
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
	mutating func generate_bindsAliasOfKeywordLabeledParameter_whenAliasOfPassThroughNamedDefaultIsReadOnTwoTierSeam() async throws {
		// The alias's fulfilling property is labeled with a keyword, which the binding spells as a declaration does.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(`default`: Token, screen: Screen) {
				        self.default = `default`
				        self.screen = screen
				    }

				    @Instantiated let `default`: Token
				    @Instantiated let screen: Screen
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(session: Session, analytics: AnyAnalytics) {
				        self.session = session
				        self.analytics = analytics
				    }

				    @Instantiated let session: Session
				    @Instantiated(fulfilledByType: "Internals.Analytics", erasedToConcreteExistential: true) let analytics: AnyAnalytics
				}
				""",
				"""
				@Instantiable
				public struct Session: Instantiable {
				    public init(current: Token?, client: Client) {
				        self.current = current
				        self.client = client
				    }

				    @Received(fulfilledByDependencyNamed: "default", ofType: Token.self, onlyIfAvailable: true) let current: Token?
				    @Instantiated let client: Client
				}
				""",
				"""
				@Instantiable
				public struct Client: Instantiable {
				    public init(current: Token?) {
				        self.current = current
				    }

				    @Received(onlyIfAvailable: true) let current: Token?
				}
				""",
				Self.internalAnalyticsContent(receivingToken: "@Received(onlyIfAvailable: true) let token: Token?", initializerParameter: "token: Token?"),
				Self.anyAnalyticsContent,
				"""
				@Instantiable
				public struct Token: Instantiable {
				    public init() {}
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
			        let `default` = Token()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_7048743525EA5C7B.self
			            return Screen(default: `default`, token: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(default: `default`, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public init(`default`: Token?, token: Token?) {
			        func __safeDI_session() -> Session {
			            #sourceLocation(file: "\(output.fixtures["Session.swift"])", line: 8)
			            let current: Token? = `default`
			            #sourceLocation()
			            let client = Client(current: current)
			            return Session(current: current, client: client)
			        }
			        let session: Session = __safeDI_session()
			        let analytics = AnyAnalytics(Internals.Analytics(token: token))
			        self.init(session: session, analytics: analytics)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_7048743525EA5C7B {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesHeaderOnlyAndCallsHandWrittenInitializer_whenSeamSignatureEqualsItsInitializer() async throws {
		// A seam with no `@Instantiated` dependency and no pass-through would generate an initializer with its own
		// initializer's parameters, so it generates none, and a tree that reaches it calls its own initializer.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(user: User, screen: Screen) {
				        self.user = user
				        self.screen = screen
				    }

				    @Instantiated let user: User
				    @Instantiated let screen: Screen
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(user: User) {
				        self.user = user
				    }

				    @Received let user: User
				}
				""",
				Self.userContent,
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader)
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let user = User()
		        let screen = Screen(user: user)
		        self.init(user: user, screen: screen)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenTwoPassThroughsShareLabelWithDifferentTypes() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `token` as `token: String?` on `Cache` and `token: Token` on `Client`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.
			\(fixtures["Cache.swift"]):7:5: note: `Cache` receives `token: String?` here.
			\(fixtures["Client.swift"]):7:5: note: `Client` receives `token: Token` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(token: Token, screen: Screen) {
					        self.token = token
					        self.screen = screen
					    }

					    @Instantiated let token: Token
					    @Instantiated let screen: Screen
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(cache: Cache, client: Client) {
					        self.cache = cache
					        self.client = client
					    }

					    @Instantiated let cache: Cache
					    @Instantiated let client: Client
					}
					""",
					"""
					@Instantiable
					public struct Cache: Instantiable {
					    public init(token: String?) {
					        self.token = token
					    }

					    @Received(onlyIfAvailable: true) let token: String?
					}
					""",
					"""
					@Instantiable
					public struct Client: Instantiable {
					    public init(token: Token) {
					        self.token = token
					    }

					    @Received let token: Token
					}
					""",
					"""
					@Instantiable
					public struct Token: Instantiable {
					    public init() {}
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
	mutating func generate_listsCollidingReceiversInTreeOrder_whenTheirFilesSortTheOtherWay() async {
		// The error names the receivers, and its notes follow them, in the order the seam's tree declares them, which
		// no file name decides: `Client` is instantiated before `Cache`, though `Cache.swift` sorts first. Found by
		// the graph fuzzer's renaming oracle.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `token` as `token: Token` on `Client` and `token: String?` on `Cache`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.
			\(fixtures["Client.swift"]):7:5: note: `Client` receives `token: Token` here.
			\(fixtures["Cache.swift"]):7:5: note: `Cache` receives `token: String?` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(token: Token, screen: Screen) {
					        self.token = token
					        self.screen = screen
					    }

					    @Instantiated let token: Token
					    @Instantiated let screen: Screen
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(client: Client, cache: Cache) {
					        self.client = client
					        self.cache = cache
					    }

					    @Instantiated let client: Client
					    @Instantiated let cache: Cache
					}
					""",
					"""
					@Instantiable
					public struct Cache: Instantiable {
					    public init(token: String?) {
					        self.token = token
					    }

					    @Received(onlyIfAvailable: true) let token: String?
					}
					""",
					"""
					@Instantiable
					public struct Client: Instantiable {
					    public init(token: Token) {
					        self.token = token
					    }

					    @Received let token: Token
					}
					""",
					"""
					@Instantiable
					public struct Token: Instantiable {
					    public init() {}
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
	mutating func generate_throwsCycleError_whenSeamTreeInstantiatesTypeThatInstantiatesSeam() async {
		// Validation inlines every seam's tree, so a cycle through a seam is rejected as any other.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):7:5: error: Dependency cycle: `Feature` -> `Screen` -> `Feature`. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change one of `feature: Feature`, `screen: Screen` to an instantiator.
			\(fixtures["Feature.swift"]):1:1: note: `Feature` is part of the cycle
			\(fixtures["Screen.swift"]):1:1: note: `Screen` is part of the cycle
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(feature: Feature) {
					        self.feature = feature
					    }

					    @Instantiated let feature: Feature
					}
					""",
					"""
					@Instantiable
					public struct Feature: Instantiable {
					    public init(screen: Screen) {
					        self.screen = screen
					    }

					    @Instantiated let screen: Screen
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(feature: Feature) {
					        self.feature = feature
					    }

					    @Instantiated let feature: Feature
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
	mutating func generate_inlinesRoot_whenAnotherTreeInstantiatesIt() async throws {
		// `isRoot` means what it always has: a root reached from another tree is built inline there.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated let screen: Screen
				}
				""",
				"""
				@Instantiable(isRoot: true)
				public struct Screen: Instantiable {
				    public init(user: User) {
				        self.user = user
				    }

				    @Instantiated let user: User
				}
				""",
				Self.userContent,
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_screen() -> Screen {
		            let user = User()
		            return Screen(user: user)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(screen: screen)
		    }
		}
		""")
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init() {
		        let user = User()
		        self.init(user: user)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsSeamTreeInline_whenGeneratingSeamsMock() async throws {
		// Mocks never call a seam's generated initializer: a mock builds the whole tree beside the mocked type.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateDependencyTree: true, generateMock: true)
				public struct Screen: Instantiable {
				    public init(user: User, cache: Cache) {
				        self.user = user
				        self.cache = cache
				    }

				    @Received let user: User
				    @Instantiated let cache: Cache
				}
				""",
				"""
				@Instantiable
				public struct Cache: Instantiable {
				    public init(database: Database) {
				        self.database = database
				    }

				    @Received let database: Database
				}
				""",
				Self.userContent,
				Self.databaseContent,
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(user: User, database: Database) {
		        let cache = Cache(database: database)
		        self.init(user: user, cache: cache)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_985E03825C6BDB6D {}
		}
		""")
		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            database: (() -> Database)? = nil,
		            cache: ((Database) -> Cache)? = nil,
		            user: (() -> User)? = nil
		        ) {
		            self.database = database
		            self.cache = cache
		            self.user = user
		        }

		        let database: (() -> Database)?
		        let cache: ((Database) -> Cache)?
		        let user: (() -> User)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let database = if let safeDIBuilder = safeDIOverrides.database { safeDIBuilder() } else { Database() }
		        let cache = if let safeDIBuilder = safeDIOverrides.cache { safeDIBuilder(database) } else { Cache(database: database) }
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        return Screen(user: user, cache: cache)
		    }
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scan_namesSeamFileApartFromRootFile_whenTheyShareFileName() async throws {
		// A seam gets a file in the module that declares it, named together with the root files so that no two share
		// an output file.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: [
				"App/Screen.swift": """
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated let screen: Screen
				}
				""",
				"Feature/Screen.swift": """
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(user: User) {
				        self.user = user
				    }

				    @Instantiated let user: User
				}
				""",
				"Feature/User.swift": Self.userContent,
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles.keys.sorted() == ["App_Screen+SafeDI.swift", "Feature_Screen+SafeDI.swift"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamDeclaresInitializerWithGeneratedParameters() async {
		// Swift tells initializers apart by their parameters' labels and types, so the generated initializer would
		// redeclare the hand-written one. The macro cannot report it: it cannot see the pass-through.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: the generated initializer, `init(user: User, database: Database)`, takes the parameters of an initializer `Screen` declares at line 8, which it would redeclare. Remove that initializer, or change its parameters.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
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
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(user: User, cache: Cache) {
					        self.user = user
					        self.cache = cache
					    }

					    public init(user: User, database: Database) {
					        self.user = user
					        cache = Cache(database: database)
					    }

					    @Received let user: User
					    @Instantiated let cache: Cache
					}
					""",
					"""
					@Instantiable
					public struct Cache: Instantiable {
					    public init(database: Database) {
					        self.database = database
					    }

					    @Received let database: Database
					}
					""",
					Self.userContent,
					Self.databaseContent,
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenRootReachesSeamOfModuleWhoseDependencysModuleInfoIsNotGiven() async {
		// A seam's signature is computed from what its module sees, which includes the modules its `.safedi` names,
		// so a caller given only the seam's `.safedi` cannot compute it: reported at the seam, for a seam a tree
		// reaches, with the remedy for each integration.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate a call to the initializer SafeDI generated for `Screen` in module `Feature`: that initializer takes what the type's dependency tree needs from the declarations `Feature` sees, which include module `Core`'s, and this run was not given `Core`'s SafeDI module info. Give this run every module `Feature` depends on: add `Core`'s `Core_safedi` target to this target's `safedi_deps` under Bazel (the `deps` of a hand-written `safedi_compile`), add `Core` to the `dependencies:` of this target's `SafeDI.preCompileScript` under Tuist, or pass its `.safedi` file to `--dependent-module-info-file-path`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Core",
						packageName: "Shop",
						swiftFileContent: [Self.loggerContent],
					),
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContent: [
							"""
							import Core

							@Instantiable(generateDependencyTree: true)
							public struct Screen: Instantiable {
							    public init(cache: Cache) {
							        self.cache = cache
							    }

							    @Instantiated let cache: Cache
							}
							""",
							"""
							import Core

							@Instantiable
							public struct Cache: Instantiable {
							    public init(database: Database, logger: Logger?) {
							        self.database = database
							        self.logger = logger
							    }

							    @Received let database: Database
							    @Received(onlyIfAvailable: true) let logger: Logger?
							}
							""",
							"""
							@Instantiable
							public struct Banner: Instantiable {
							    public init() {}
							}
							""",
							Self.databaseContent,
						],
						dependencies: ["Core"],
					),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [
							"""
							import Feature

							@Instantiable(isRoot: true)
							public struct Root: Instantiable {
							    public init(database: Database, screen: Screen) {
							        self.database = database
							        self.screen = screen
							    }

							    @Instantiated let database: Database
							    @Instantiated let screen: Screen
							}
							""",
						],
						dependencies: ["Feature"],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesTree_whenNoTreeReachesSeamOfModuleWhoseDependencysModuleInfoIsNotGiven() async throws {
		// A seam no tree reaches needs no signature, so the module info its module's dependencies lack is not missed:
		// a module that lists the seam's module without that module's own dependencies generates its other trees.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Core",
					packageName: "Shop",
					swiftFileContent: [Self.loggerContent],
				),
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						"""
						import Core

						@Instantiable(generateDependencyTree: true)
						public struct Screen: Instantiable {
						    public init(cache: Cache) {
						        self.cache = cache
						    }

						    @Instantiated let cache: Cache
						}
						""",
						"""
						import Core

						@Instantiable
						public struct Cache: Instantiable {
						    public init(database: Database, logger: Logger?) {
						        self.database = database
						        self.logger = logger
						    }

						    @Received let database: Database
						    @Received(onlyIfAvailable: true) let logger: Logger?
						}
						""",
						"""
						@Instantiable
						public struct Banner: Instantiable {
						    public init() {}
						}
						""",
						Self.databaseContent,
					],
					dependencies: ["Core"],
				),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContent: [
						"""
						import Feature

						@Instantiable(isRoot: true)
						public struct Root: Instantiable {
						    public init(banner: Banner) {
						        self.banner = banner
						    }

						    @Instantiated let banner: Banner
						}
						""",
					],
					dependencies: ["Feature"],
				),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + Self.importBlock("Core") + "\n" + Self.importBlock("Feature") + "\n\n" + """
		extension Root {
		    public init() {
		        let banner = Banner()
		        self.init(banner: banner)
		    }
		}
		"""])
		#expect(try #require(output.modules["App"]).warnings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_settlesEverySignature_whenTenSeamsEachReachTheNext() async throws {
		// Each seam's parameters depend on the signature of the seam its tree reaches, so the seams are settled inner
		// first: the outermost takes `token`, which only the innermost's tree receives, however long the chain.
		var files = [
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(token: Token, seam0: Seam0) {
			        self.token = token
			        self.seam0 = seam0
			    }

			    @Instantiated let token: Token
			    @Instantiated let seam0: Seam0
			}
			""",
			"""
			@Instantiable
			public struct Token: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public struct Reader: Instantiable {
			    public init(token: Token) {
			        self.token = token
			    }

			    @Received let token: Token
			}
			""",
		]
		for index in 0..<10 {
			let child = index == 9 ? "reader: Reader" : "seam\(index + 1): Seam\(index + 1)"
			let childLabel = index == 9 ? "reader" : "seam\(index + 1)"
			files.append("""
			@Instantiable(generateDependencyTree: true)
			public struct Seam\(index): Instantiable {
			    public init(\(child)) {
			        self.\(childLabel) = \(childLabel)
			    }

			    @Instantiated let \(child)
			}
			""")
		}
		let output = try await executeSafeDIToolTest(
			swiftFileContent: files,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles.keys.sorted() == ["Root+SafeDI.swift"] + (0..<10).map { "Seam\($0)+SafeDI.swift" })
		#expect(output.dependencyTreeFiles["Seam0+SafeDI.swift"] == generatedFileHeader + """
		extension Seam0 {
		    public init(token: Token) {
		        func __safeDI_seam1() -> Seam1 {
		            _ = Seam1.__safeDI_Seam1_1EB503BFA23A82BA.self
		            return Seam1(token: token)
		        }
		        let seam1: Seam1 = __safeDI_seam1()
		        self.init(seam1: seam1)
		    }
		}

		extension Seam0 {
		    public enum __safeDI_Seam0_1EB503BFA23A82BA {}
		}
		""")
		#expect(output.dependencyTreeFiles["Seam9+SafeDI.swift"] == generatedFileHeader + """
		extension Seam9 {
		    public init(token: Token) {
		        let reader = Reader(token: token)
		        self.init(reader: reader)
		    }
		}

		extension Seam9 {
		    public enum __safeDI_Seam9_1EB503BFA23A82BA {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let token = Token()
		        func __safeDI_seam0() -> Seam0 {
		            _ = Seam0.__safeDI_Seam0_1EB503BFA23A82BA.self
		            return Seam0(token: token)
		        }
		        let seam0: Seam0 = __safeDI_seam0()
		        self.init(token: token, seam0: seam0)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsEverySeamsError_whenTwoSeamsFailAndTheirNamesSortAgainstTheirLocations() async {
		// Both seams' errors are reported, in source order: `Zeta` is declared before `Alpha` in one file, though
		// `Alpha` sorts first, and each seam's two collisions are both reported.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Zeta.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Zeta`: its tree receives `token` as `token: Token` on `Client` and `token: String` on `Cache`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.
			\(fixtures["Client.swift"]):8:5: note: `Client` receives `token: Token` here.
			\(fixtures["Cache.swift"]):8:5: note: `Cache` receives `token: String` here.
			\(fixtures["Zeta.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Zeta`: its tree receives `user` as `user: User` on `Client` and `user: String` on `Cache`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.
			\(fixtures["Client.swift"]):9:5: note: `Client` receives `user: User` here.
			\(fixtures["Cache.swift"]):9:5: note: `Cache` receives `user: String` here.
			\(fixtures["Zeta.swift"]):12:1: error: SafeDI cannot generate the dependency tree of `Alpha`: its tree receives `token` as `token: Token` on `Client` and `token: String` on `Cache`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.
			\(fixtures["Client.swift"]):8:5: note: `Client` receives `token: Token` here.
			\(fixtures["Cache.swift"]):8:5: note: `Cache` receives `token: String` here.
			\(fixtures["Zeta.swift"]):12:1: error: SafeDI cannot generate the dependency tree of `Alpha`: its tree receives `user` as `user: User` on `Client` and `user: String` on `Cache`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.
			\(fixtures["Client.swift"]):9:5: note: `Client` receives `user: User` here.
			\(fixtures["Cache.swift"]):9:5: note: `Cache` receives `user: String` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Zeta: Instantiable {
					    public init(client: Client, cache: Cache) {
					        self.client = client
					        self.cache = cache
					    }

					    @Instantiated let client: Client
					    @Instantiated let cache: Cache
					}

					@Instantiable(generateDependencyTree: true)
					public struct Alpha: Instantiable {
					    public init(client: Client, cache: Cache) {
					        self.client = client
					        self.cache = cache
					    }

					    @Instantiated let client: Client
					    @Instantiated let cache: Cache
					}
					""",
					"""
					@Instantiable
					public struct Client: Instantiable {
					    public init(token: Token, user: User) {
					        self.token = token
					        self.user = user
					    }

					    @Received let token: Token
					    @Received let user: User
					}
					""",
					"""
					@Instantiable
					public struct Cache: Instantiable {
					    public init(token: String, user: String) {
					        self.token = token
					        self.user = user
					    }

					    @Received let token: String
					    @Received let user: String
					}
					""",
					"""
					@Instantiable
					public struct Token: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct User: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamInitializerGeneratedInDeclaringModule_whenRootIsInAnotherModule(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Core",
					packageName: "Shop",
					swiftFileContent: [Self.userContent, Self.databaseContent, Self.loggerContent],
				),
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						"""
						import Core

						@Instantiable(generateDependencyTree: true)
						public struct Screen: Instantiable {
						    public init(user: User, cache: Cache) {
						        self.user = user
						        self.cache = cache
						    }

						    @Received let user: User
						    @Instantiated let cache: Cache
						}
						""",
						"""
						import Core

						@Instantiable
						public struct Cache: Instantiable {
						    public init(database: Database, logger: Logger?) {
						        self.database = database
						        self.logger = logger
						    }

						    @Received let database: Database
						    @Received(onlyIfAvailable: true) let logger: Logger?
						}
						""",
					],
					dependencies: ["Core"],
				),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContent: [
						"""
						import Core
						import Feature

						@Instantiable(isRoot: true)
						public struct Root: Instantiable {
						    public init(user: User, database: Database, logger: Logger, screen: Screen) {
						        self.user = user
						        self.database = database
						        self.logger = logger
						        self.screen = screen
						    }

						    @Instantiated let user: User
						    @Instantiated let database: Database
						    @Instantiated let logger: Logger
						    @Instantiated let screen: Screen
						}
						""",
					],
					dependencies: ["Feature", "Core"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		// The initializer the seam's module generates, and the call the root's module generates for it, each from
		// its own computation of the seam's signature, name one enum and pass each parameter.
		let seamCode = """
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
		// The call says what to do when it does not compile: under the SwiftPM plugin, apply the plugin to the seam's
		// target, which the plugin cannot tell is applied; for a module read from its `.safedi`, compile the code its run
		// generated into it, which `generate` cannot tell is compiled.
		let callComment = integration.seamCallComment(type: "Screen", declaringModule: "Feature")
		let rootCode = """
		extension Root {
		    public init() {
		        let user = User()
		        let database = Database()
		        let logger = Logger()
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_154FFE4ADBF72F8B.self\(callComment)
		            return Screen(user: user, database: database, logger: logger)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, database: database, logger: logger, screen: screen)
		    }
		}
		"""
		let expectedGeneratedFiles: [String: [String: String]] = switch integration {
		case .moduleInfo:
			[
				"Core": ["Core.swift": generatedFileHeader],
				"Feature": ["Feature.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + seamCode],
				"App": ["App.swift": generatedFileHeader + Self.importBlock("Core") + "\n" + Self.importBlock("Feature") + "\n\n" + rootCode],
			]
		case .swiftPackagePlugin:
			[
				"Core": [:],
				"Feature": ["Screen+SafeDI.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + seamCode],
				"App": ["Root+SafeDI.swift": generatedFileHeader + Self.importBlock("Core") + "\n" + Self.importBlock("Feature") + "\n\n" + rootCode],
			]
		}
		#expect(output.modules.mapValues(\.generatedFiles) == expectedGeneratedFiles)
		for moduleName in output.moduleNames {
			#expect(try #require(output.modules[moduleName]).warnings == [])
		}
		if compileVerificationIsEnabled {
			let compilation = try #require(output.compilation)
			#expect(compilation.modules.map(\.exitCode) == [0, 0, 0])
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsEachModulesSeams_whenSeamsOfOneModuleReachAnotherModulesSeam(integration: MultiModuleIntegration) async throws {
		// `App` calls two seams of `Feature`, whose trees reach a seam of `Core`: the seams of `Core` are computed
		// before those of `Feature`, from what `Core` sees, and `Feature`'s two from what `Feature` sees, once.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Core",
					packageName: "Shop",
					swiftFileContent: [
						Self.databaseContent,
						"""
						@Instantiable(generateDependencyTree: true)
						public struct Session: Instantiable {
						    public init(store: Store) {
						        self.store = store
						    }

						    @Instantiated let store: Store
						}
						""",
						"""
						@Instantiable
						public struct Store: Instantiable {
						    public init(database: Database) {
						        self.database = database
						    }

						    @Received let database: Database
						}
						""",
					],
				),
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						"""
						import Core

						@Instantiable(generateDependencyTree: true)
						public struct Screen: Instantiable {
						    public init(session: Session) {
						        self.session = session
						    }

						    @Instantiated let session: Session
						}
						""",
						"""
						import Core

						@Instantiable(generateDependencyTree: true)
						public struct Panel: Instantiable {
						    public init(session: Session) {
						        self.session = session
						    }

						    @Instantiated let session: Session
						}
						""",
					],
					dependencies: ["Core"],
				),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContent: [
						"""
						import Core
						import Feature

						@Instantiable(isRoot: true)
						public struct Root: Instantiable {
						    public init(database: Database, screen: Screen, panel: Panel) {
						        self.database = database
						        self.screen = screen
						        self.panel = panel
						    }

						    @Instantiated let database: Database
						    @Instantiated let screen: Screen
						    @Instantiated let panel: Panel
						}
						""",
					],
					dependencies: ["Feature", "Core"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let callComment = integration.seamCallComment(type: "Session", declaringModule: "Core")
		let sessionCode = """
		extension Session {
		    public init(database: Database) {
		        let store = Store(database: database)
		        self.init(store: store)
		    }
		}

		extension Session {
		    public enum __safeDI_Session_FF5D0A1F23864D36 {}
		}
		"""
		func featureSeamCode(_ typeName: String) -> String {
			"""
			extension \(typeName) {
			    public init(database: Database) {
			        func __safeDI_session() -> Session {
			            _ = Session.__safeDI_Session_FF5D0A1F23864D36.self\(callComment)
			            return Session(database: database)
			        }
			        let session: Session = __safeDI_session()
			        self.init(session: session)
			    }
			}

			extension \(typeName) {
			    public enum __safeDI_\(typeName)_FF5D0A1F23864D36 {}
			}
			"""
		}
		let rootCode = """
		extension Root {
		    public init() {
		        let database = Database()
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_FF5D0A1F23864D36.self\(integration.seamCallComment(type: "Screen", declaringModule: "Feature"))
		            return Screen(database: database)
		        }
		        let screen: Screen = __safeDI_screen()
		        func __safeDI_panel() -> Panel {
		            _ = Panel.__safeDI_Panel_FF5D0A1F23864D36.self\(integration.seamCallComment(type: "Panel", declaringModule: "Feature"))
		            return Panel(database: database)
		        }
		        let panel: Panel = __safeDI_panel()
		        self.init(database: database, screen: screen, panel: panel)
		    }
		}
		"""
		let expectedGeneratedFiles: [String: [String: String]] = switch integration {
		case .moduleInfo:
			[
				"Core": ["Core.swift": generatedFileHeader + sessionCode],
				"Feature": ["Feature.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + featureSeamCode("Panel") + "\n\n" + featureSeamCode("Screen")],
				"App": ["App.swift": generatedFileHeader + Self.importBlock("Core") + "\n" + Self.importBlock("Feature") + "\n\n" + rootCode],
			]
		case .swiftPackagePlugin:
			[
				"Core": ["Session+SafeDI.swift": generatedFileHeader + sessionCode],
				"Feature": [
					"Panel+SafeDI.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + featureSeamCode("Panel"),
					"Screen+SafeDI.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + featureSeamCode("Screen"),
				],
				"App": ["Root+SafeDI.swift": generatedFileHeader + Self.importBlock("Core") + "\n" + Self.importBlock("Feature") + "\n\n" + rootCode],
			]
		}
		#expect(output.modules.mapValues(\.generatedFiles) == expectedGeneratedFiles)
		for moduleName in output.moduleNames {
			#expect(try #require(output.modules[moduleName]).warnings == [])
		}
		if compileVerificationIsEnabled {
			let compilation = try #require(output.compilation)
			#expect(compilation.modules.map(\.exitCode) == [0, 0, 0])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_settlesEverySignature_whenNineSeamsFormLazyCycle() async throws {
		// Each seam's tree reaches the next through an `Instantiator`, so the nine form one strongly connected
		// component, and a seam's own dependency reaches the seam before it one computation at a time: the signatures
		// settle on the ninth computation, one more than the eight the limit once allowed every component.
		var files = [
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(\((0..<9).map { "dependency\($0): Dependency\($0)" }.joined(separator: ", ")), seam0: Seam0) {
			\((0..<9).map { "        self.dependency\($0) = dependency\($0)" }.joined(separator: "\n"))
			        self.seam0 = seam0
			    }

			\((0..<9).map { "    @Instantiated let dependency\($0): Dependency\($0)" }.joined(separator: "\n"))
			    @Instantiated let seam0: Seam0
			}
			""",
		]
		for index in 0..<9 {
			let next = (index + 1) % 9
			files.append("""
			@Instantiable
			public struct Dependency\(index): Instantiable {
			    public init() {}
			}
			""")
			files.append("""
			@Instantiable(generateDependencyTree: true)
			public struct Seam\(index): Instantiable {
			    public init(dependency\(index): Dependency\(index), seam\(next)Builder: Instantiator<Seam\(next)>) {
			        self.dependency\(index) = dependency\(index)
			        self.seam\(next)Builder = seam\(next)Builder
			    }

			    @Received let dependency\(index): Dependency\(index)
			    @Instantiated let seam\(next)Builder: Instantiator<Seam\(next)>
			}
			""")
		}
		let output = try await executeSafeDIToolTest(
			swiftFileContent: files,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles.keys.sorted() == ["Root+SafeDI.swift"] + (0..<9).map { "Seam\($0)+SafeDI.swift" })
		#expect(output.dependencyTreeFiles["Seam0+SafeDI.swift"] == generatedFileHeader + """
		extension Seam0 {
		    public init(dependency0: Dependency0, dependency1: Dependency1, dependency2: Dependency2, dependency3: Dependency3, dependency4: Dependency4, dependency5: Dependency5, dependency6: Dependency6, dependency7: Dependency7, dependency8: Dependency8) {
		        func __safeDI_seam1Builder() -> Seam1 {
		            _ = Seam1.__safeDI_Seam1_A845F246C38546F6.self
		            return Seam1(dependency1: dependency1, dependency0: dependency0, dependency2: dependency2, dependency3: dependency3, dependency4: dependency4, dependency5: dependency5, dependency6: dependency6, dependency7: dependency7, dependency8: dependency8)
		        }
		        let seam1Builder = Instantiator<Seam1>(__safeDI_seam1Builder)
		        self.init(dependency0: dependency0, seam1Builder: seam1Builder)
		    }
		}

		extension Seam0 {
		    public enum __safeDI_Seam0_891809A39278C28E {}
		}
		""")
		#expect(output.dependencyTreeFiles["Seam8+SafeDI.swift"] == generatedFileHeader + """
		extension Seam8 {
		    public init(dependency8: Dependency8, dependency0: Dependency0, dependency1: Dependency1, dependency2: Dependency2, dependency3: Dependency3, dependency4: Dependency4, dependency5: Dependency5, dependency6: Dependency6, dependency7: Dependency7) {
		        func __safeDI_seam0Builder() -> Seam0 {
		            _ = Seam0.__safeDI_Seam0_891809A39278C28E.self
		            return Seam0(dependency0: dependency0, dependency1: dependency1, dependency2: dependency2, dependency3: dependency3, dependency4: dependency4, dependency5: dependency5, dependency6: dependency6, dependency7: dependency7, dependency8: dependency8)
		        }
		        let seam0Builder = Instantiator<Seam0>(__safeDI_seam0Builder)
		        self.init(dependency8: dependency8, seam0Builder: seam0Builder)
		    }
		}

		extension Seam8 {
		    public enum __safeDI_Seam8_722067462DEC1DCE {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let dependency0 = Dependency0()
		        let dependency1 = Dependency1()
		        let dependency2 = Dependency2()
		        let dependency3 = Dependency3()
		        let dependency4 = Dependency4()
		        let dependency5 = Dependency5()
		        let dependency6 = Dependency6()
		        let dependency7 = Dependency7()
		        let dependency8 = Dependency8()
		        func __safeDI_seam0() -> Seam0 {
		            _ = Seam0.__safeDI_Seam0_891809A39278C28E.self
		            return Seam0(dependency0: dependency0, dependency1: dependency1, dependency2: dependency2, dependency3: dependency3, dependency4: dependency4, dependency5: dependency5, dependency6: dependency6, dependency7: dependency7, dependency8: dependency8)
		        }
		        let seam0: Seam0 = __safeDI_seam0()
		        self.init(dependency0: dependency0, dependency1: dependency1, dependency2: dependency2, dependency3: dependency3, dependency4: dependency4, dependency5: dependency5, dependency6: dependency6, dependency7: dependency7, dependency8: dependency8, seam0: seam0)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_capsEveryTierAtExtensionsMemberDefault_whenSeamIsNestedInUnspelledEnumDeclaredInExtension() async throws {
		// `Internals` spells no access and is declared in an extension that spells none, so it is internal, as every
		// member of such an extension is, and `Namespace.Internals.Screen` with it: no tier can be wider.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(token: Token, session: Session, screenBuilder: ErasedInstantiator<User, AnyScreen>) {
				        self.token = token
				        self.session = session
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated let token: Token
				    @Instantiated let session: Session
				    @Instantiated(fulfilledByType: "Namespace.Internals.Screen", erasedToConcreteExistential: true) let screenBuilder: ErasedInstantiator<User, AnyScreen>
				}
				""",
				"""
				public enum Namespace {}

				extension Namespace {
				    enum Internals {
				        @Instantiable(generateDependencyTree: true)
				        public struct Screen: Instantiable, ScreenProtocol {
				            public init(user: User, session: Session, tracker: Tracker) {
				                self.user = user
				                self.session = session
				                self.tracker = tracker
				            }

				            @Forwarded let user: User
				            @Received let session: Session
				            @Instantiated let tracker: Tracker
				        }
				    }
				}
				""",
				"""
				public protocol ScreenProtocol {}

				public struct AnyScreen: ScreenProtocol {
				    public init(_ screen: some ScreenProtocol) {}
				}
				""",
				"""
				@Instantiable
				public struct Tracker: Instantiable {
				    public init(token: Token) {
				        self.token = token
				    }

				    @Received let token: Token
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
				public struct Token: Instantiable {
				    public init() {}
				}
				""",
				"""
				public struct User {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Namespace.Internals.Screen {
		    internal init(user: User, session: Session, token: Token) {
		        let tracker = Tracker(token: token)
		        self.init(user: user, session: session, tracker: tracker)
		    }
		}

		extension Namespace.Internals.Screen {
		    public enum __safeDI_Namespace_Internals_Screen_A50891B3B6BDBBCE {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let token = Token()
		        let session = Session()
		        func __safeDI_screenBuilder(user: User) -> Namespace.Internals.Screen {
		            _ = Namespace.Internals.Screen.__safeDI_Namespace_Internals_Screen_A50891B3B6BDBBCE.self
		            return Namespace.Internals.Screen(user: user, session: session, token: token)
		        }
		        let screenBuilder = ErasedInstantiator<User, AnyScreen> {
		            AnyScreen(__safeDI_screenBuilder(user: $0))
		        }
		        self.init(token: token, session: session, screenBuilder: screenBuilder)
		    }
		}
		""")
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_computesEachModulesSeamsOnce_whenRootReachesSeamsOfTwoModulesAndOnesTreeReachesTheOthers(integration: MultiModuleIntegration) async throws {
		// `App` reaches `Analytics`'s seam and `Storage`'s, and `Analytics`'s tree reaches `Storage`'s: `Analytics`,
		// met first by name, waits under `Storage`, which is computed once although `App` reaches it on its own too.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Storage",
					packageName: "Shop",
					swiftFileContent: [
						Self.databaseContent,
						"""
						@Instantiable(generateDependencyTree: true)
						public struct Vault: Instantiable {
						    public init(store: Store) {
						        self.store = store
						    }

						    @Instantiated let store: Store
						}
						""",
						"""
						@Instantiable
						public struct Store: Instantiable {
						    public init(database: Database) {
						        self.database = database
						    }

						    @Received let database: Database
						}
						""",
					],
				),
				ModuleFixture(
					name: "Analytics",
					packageName: "Shop",
					swiftFileContent: [
						"""
						import Storage

						@Instantiable(generateDependencyTree: true)
						public struct Dashboard: Instantiable {
						    public init(vault: Vault) {
						        self.vault = vault
						    }

						    @Instantiated let vault: Vault
						}
						""",
					],
					dependencies: ["Storage"],
				),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContent: [
						"""
						import Analytics
						import Storage

						@Instantiable(isRoot: true)
						public struct Root: Instantiable {
						    public init(database: Database, dashboard: Dashboard, vault: Vault) {
						        self.database = database
						        self.dashboard = dashboard
						        self.vault = vault
						    }

						    @Instantiated let database: Database
						    @Instantiated let dashboard: Dashboard
						    @Instantiated let vault: Vault
						}
						""",
					],
					dependencies: ["Analytics", "Storage"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let vaultCode = """
		extension Vault {
		    public init(database: Database) {
		        let store = Store(database: database)
		        self.init(store: store)
		    }
		}

		extension Vault {
		    public enum __safeDI_Vault_FF5D0A1F23864D36 {}
		}
		"""
		let dashboardCode = """
		extension Dashboard {
		    public init(database: Database) {
		        func __safeDI_vault() -> Vault {
		            _ = Vault.__safeDI_Vault_FF5D0A1F23864D36.self\(integration.seamCallComment(type: "Vault", declaringModule: "Storage"))
		            return Vault(database: database)
		        }
		        let vault: Vault = __safeDI_vault()
		        self.init(vault: vault)
		    }
		}

		extension Dashboard {
		    public enum __safeDI_Dashboard_FF5D0A1F23864D36 {}
		}
		"""
		let rootCode = """
		extension Root {
		    public init() {
		        let database = Database()
		        func __safeDI_dashboard() -> Dashboard {
		            _ = Dashboard.__safeDI_Dashboard_FF5D0A1F23864D36.self\(integration.seamCallComment(type: "Dashboard", declaringModule: "Analytics"))
		            return Dashboard(database: database)
		        }
		        let dashboard: Dashboard = __safeDI_dashboard()
		        func __safeDI_vault() -> Vault {
		            _ = Vault.__safeDI_Vault_FF5D0A1F23864D36.self\(integration.seamCallComment(type: "Vault", declaringModule: "Storage"))
		            return Vault(database: database)
		        }
		        let vault: Vault = __safeDI_vault()
		        self.init(database: database, dashboard: dashboard, vault: vault)
		    }
		}
		"""
		let expectedGeneratedFiles: [String: [String: String]] = switch integration {
		case .moduleInfo:
			[
				"Storage": ["Storage.swift": generatedFileHeader + vaultCode],
				"Analytics": ["Analytics.swift": generatedFileHeader + Self.importBlock("Storage") + "\n\n" + dashboardCode],
				"App": ["App.swift": generatedFileHeader + Self.importBlock("Analytics") + "\n" + Self.importBlock("Storage") + "\n\n" + rootCode],
			]
		case .swiftPackagePlugin:
			[
				"Storage": ["Vault+SafeDI.swift": generatedFileHeader + vaultCode],
				"Analytics": ["Dashboard+SafeDI.swift": generatedFileHeader + Self.importBlock("Storage") + "\n\n" + dashboardCode],
				"App": ["Root+SafeDI.swift": generatedFileHeader + Self.importBlock("Analytics") + "\n" + Self.importBlock("Storage") + "\n\n" + rootCode],
			]
		}
		#expect(output.modules.mapValues(\.generatedFiles) == expectedGeneratedFiles)
		for moduleName in output.moduleNames {
			#expect(try #require(output.modules[moduleName]).warnings == [])
		}
		if compileVerificationIsEnabled {
			let compilation = try #require(output.compilation)
			#expect(compilation.modules.map(\.exitCode) == [0, 0, 0])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsEachModulesSeams_whenTwoReachedModulesNameDependencyThisRunIsNotGiven() async {
		// `App` reaches `Feature`'s seam, whose tree reaches `Core`'s, and both modules name `Base`, whose module info
		// `App` is not given (`Feature`'s build needed it to compute `Core`'s seam, so its `.safedi` names it too):
		// each module's seam is reported, in source order, before the inlined trees are found to need `Database`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Cache.swift"]):3:1: error: SafeDI cannot generate a call to the initializer SafeDI generated for `Cache` in module `Core`: that initializer takes what the type's dependency tree needs from the declarations `Core` sees, which include module `Base`'s, and this run was not given `Base`'s SafeDI module info. Give this run every module `Core` depends on: add `Base`'s `Base_safedi` target to this target's `safedi_deps` under Bazel (the `deps` of a hand-written `safedi_compile`), add `Base` to the `dependencies:` of this target's `SafeDI.preCompileScript` under Tuist, or pass its `.safedi` file to `--dependent-module-info-file-path`.
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate a call to the initializer SafeDI generated for `Screen` in module `Feature`: that initializer takes what the type's dependency tree needs from the declarations `Feature` sees, which include module `Base`'s, and this run was not given `Base`'s SafeDI module info. Give this run every module `Feature` depends on: add `Base`'s `Base_safedi` target to this target's `safedi_deps` under Bazel (the `deps` of a hand-written `safedi_compile`), add `Base` to the `dependencies:` of this target's `SafeDI.preCompileScript` under Tuist, or pass its `.safedi` file to `--dependent-module-info-file-path`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Base",
						packageName: "Shop",
						swiftFileContent: [Self.databaseContent],
					),
					ModuleFixture(
						name: "Core",
						packageName: "Shop",
						swiftFileContent: [
							"""
							import Base

							@Instantiable(generateDependencyTree: true)
							public struct Cache: Instantiable {
							    public init(store: Store) {
							        self.store = store
							    }

							    @Instantiated let store: Store
							}
							""",
							"""
							import Base

							@Instantiable
							public struct Store: Instantiable {
							    public init(database: Database) {
							        self.database = database
							    }

							    @Received let database: Database
							}
							""",
						],
						dependencies: ["Base"],
					),
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContent: [
							"""
							import Core

							@Instantiable(generateDependencyTree: true)
							public struct Screen: Instantiable {
							    public init(cache: Cache) {
							        self.cache = cache
							    }

							    @Instantiated let cache: Cache
							}
							""",
						],
						dependencies: ["Core", "Base"],
					),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [
							"""
							import Feature

							@Instantiable(isRoot: true)
							public struct Root: Instantiable {
							    public init(screen: Screen) {
							        self.screen = screen
							    }

							    @Instantiated let screen: Screen
							}
							""",
						],
						dependencies: ["Feature", "Core"],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Receivers that leave the seam on some path

	/// `Screen`'s tree reaches `Internals.T` under `Internals.A`, which instantiates the `x` that `T` receives, and
	/// under `Internals.B`, which does not: `x` leaves the seam on the second path only.
	private static func sharedReceiverFixture(instantiatingAFirst: Bool, receivingXAsAnotherTypeOnU: Bool) -> [String] {
		let aDeclaration = "@Instantiated(fulfilledByType: \"Internals.A\", erasedToConcreteExistential: true) let a: AnyThing"
		let bDeclaration = "@Instantiated(fulfilledByType: \"Internals.B\", erasedToConcreteExistential: true) let b: AnyThing"
		return [
			"""
			@Instantiable(generateDependencyTree: true)
			public struct Screen: Instantiable {
			    public init(a: AnyThing, b: AnyThing) {
			        self.a = a
			        self.b = b
			    }

			    \(instantiatingAFirst ? aDeclaration : bDeclaration)
			    \(instantiatingAFirst ? bDeclaration : aDeclaration)
			}

			public protocol Thing {}

			public struct AnyThing: Thing {
			    public init(_ thing: some Thing) {}
			}
			""",
			"""
			enum Internals {
			    @Instantiable(isRoot: true)
			    public struct Root: Instantiable {
			        public init(x: X, screen: Screen) {
			            self.x = x
			            self.screen = screen
			        }

			        @Instantiated let x: X
			        @Instantiated let screen: Screen
			    }

			    @Instantiable
			    public struct A: Instantiable, Thing {
			        public init(x: X, t: T) {
			            self.x = x
			            self.t = t
			        }

			        @Instantiated let x: X
			        @Instantiated let t: T
			    }

			    @Instantiable
			    public struct B: Instantiable, Thing {
			        public init(t: T\(receivingXAsAnotherTypeOnU ? ", u: U" : "")) {
			            self.t = t\(receivingXAsAnotherTypeOnU ? "\n            self.u = u" : "")
			        }

			        @Instantiated let t: T\(receivingXAsAnotherTypeOnU ? "\n        @Instantiated let u: U" : "")
			    }

			    @Instantiable
			    public struct T: Instantiable {
			        public init(x: X) {
			            self.x = x
			        }

			        @Received let x: X
			    }
			\(receivingXAsAnotherTypeOnU ? """

			    @Instantiable
			    public struct U: Instantiable {
			        public init(x: Y?) {
			            self.x = x
			        }

			        @Received(onlyIfAvailable: true) let x: Y?
			    }

			    public struct Y {}
			""" : "")

			    @Instantiable
			    public struct X: Instantiable {
			        public init() {}
			    }
			}
			""",
		]
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenInternalReceiverIsReachedUnderParentProvidingLabelBeforeParentThatDoesNot(instantiatingAFirst: Bool) async {
		// `x` leaves the seam through `Internals.T` under `Internals.B`, whichever of `A` and `B` the tree reaches
		// first; `T`'s initializer is internal, so the seam's public tier cannot take `x` and reports it.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `x: Internals.X`, which `Internals.T` receives, and cannot pass `nil` for it, since it is required. `Internals.X`'s own `@Instantiable` declaration is `internal`. Declare `Internals.X` `public`; declare `Screen` `internal`; build `x` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Root.swift"]):39:9: note: `Internals.T` receives `x: Internals.X` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.sharedReceiverFixture(instantiatingAFirst: instantiatingAFirst, receivingXAsAnotherTypeOnU: false),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_listsReceiverReachedUnderParentProvidingLabelFirst_whenLabelCollides(instantiatingAFirst: Bool) async {
		// `Internals.T` receives `x: X` and `Internals.U` receives `x: Y?`: the collision names both, whichever of
		// `A` (which provides `x` to its `T`) and `B` the tree reaches first.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `x` as `x: Internals.X` on `Internals.T` and `x: Y?` on `Internals.U`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.
			\(fixtures["Root.swift"]):41:9: note: `Internals.T` receives `x: Internals.X` here.
			\(fixtures["Root.swift"]):50:9: note: `Internals.U` receives `x: Y?` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.sharedReceiverFixture(instantiatingAFirst: instantiatingAFirst, receivingXAsAnotherTypeOnU: true),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	/// `Screen`'s tree reaches `Detail`, which receives `token`, under `Left` and under `Right`, neither of which
	/// provides it, beside `Summary`, which receives `token` as a `String` when `summaryReceivesString`. `Detail` is
	/// nested in an internal enum when `detailIsInternal`, which caps its initializer at internal.
	private static func receiverUnderTwoParentsFixture(summaryReceivesString: Bool, detailIsInternal: Bool) -> [String] {
		let detailType = detailIsInternal ? "Helpers.Detail" : "Detail"
		return [
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(token: Token, screen: Screen) {
			        self.token = token
			        self.screen = screen
			    }

			    @Instantiated let token: Token
			    @Instantiated let screen: Screen
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public struct Screen: Instantiable {
			    public init(left: Left, right: Right\(summaryReceivesString ? ", summary: Summary" : "")) {
			        self.left = left
			        self.right = right
			\(summaryReceivesString ? "        self.summary = summary\n" : "")    }

			    @Instantiated let left: Left
			    @Instantiated let right: Right
			\(summaryReceivesString ? "    @Instantiated let summary: Summary\n" : "")}
			""",
			"""
			@Instantiable
			public struct Left: Instantiable {
			    public init(detail: \(detailType)) {
			        self.detail = detail
			    }

			    @Instantiated let detail: \(detailType)
			}
			""",
			"""
			@Instantiable
			public struct Right: Instantiable {
			    public init(detail: \(detailType)) {
			        self.detail = detail
			    }

			    @Instantiated let detail: \(detailType)
			}
			""",
			detailIsInternal
				? """
				internal enum Helpers {
				    @Instantiable
				    public struct Detail: Instantiable {
				        public init(token: Token) {
				            self.token = token
				        }

				        @Received let token: Token
				    }
				}
				"""
				: """
				@Instantiable
				public struct Detail: Instantiable {
				    public init(token: Token) {
				        self.token = token
				    }

				    @Received let token: Token
				}
				""",
			"""
			@Instantiable
			public struct Summary: Instantiable {
			    public init(token: String?) {
			        self.token = token
			    }

			    @Received(onlyIfAvailable: true) let token: String?
			}
			""",
			"""
			@Instantiable
			public struct Token: Instantiable {
			    public init() {}
			}
			""",
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_listsReceiverOnce_whenLabelCollidesAndReceiverIsReachedUnderTwoParentsProvidingNothing() async {
		// `Detail`'s receive of `token` leaves the seam on both paths, under `Left` and under `Right`: one declaration,
		// named once in the collision with `Summary`'s receive (only if available, so the inlined validation accepts
		// the tree and the seam's error is the one reported).
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `token` as `token: Token` on `Detail` and `token: String?` on `Summary`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.
			\(fixtures["Detail.swift"]):7:5: note: `Detail` receives `token: Token` here.
			\(fixtures["Summary.swift"]):7:5: note: `Summary` receives `token: String?` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.receiverUnderTwoParentsFixture(summaryReceivesString: true, detailIsInternal: false),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: One label's forms, grouped by what provides them

	/// How a type receives `user`.
	enum UserReceive {
		case required
		case requiredOptional
		case onlyIfAvailable
	}

	/// What the tree that calls `Screen` holds `user` as.
	enum CallerHolding {
		/// `Root` instantiates `user: User`.
		case instance
		/// `Root` instantiates a `Feature` builder; `Feature` forwards `user: User?`.
		case optionalInstance
		/// `Root` instantiates `user` as the wrapper the seam's tree receives.
		case wrapper
		/// `Root` instantiates `user` as the other wrapper kind.
		case otherWrapper
		/// `Root` instantiates a `Feature` builder; `Feature` forwards `user` as the optional form of the wrapper.
		case optionalWrapper
		/// `Root` instantiates `user: User`, whose own tree instantiates `Screen`.
		case instanceWhoseTreeBuildsScreen
		/// No root in the module: the seam's own errors show where the inlined validation would reject every caller.
		case noCaller
	}

	/// `Screen`, a seam, whose tree receives `user` by value (`Detail`, inside a `SendableInstantiator` builder when
	/// `detailInSendableBuilder`), as the non-optional wrapper or its optional form (`Summary`), and as the optional
	/// form of a wrapper of `previewWrapper`'s kind (`Preview`), beside the seam's own receive of it, called from a
	/// tree holding `user` as `caller` says.
	private static func labelFormsFixture(
		detail: UserReceive?,
		summary: UserReceive?,
		preview: UserReceive? = nil,
		previewWrapper: String? = nil,
		own: (receive: UserReceive, asWrapper: Bool)? = nil,
		wrapper: String = "LazilyInstantiated",
		caller: CallerHolding,
		detailInSendableBuilder: Bool = false,
	) -> [String] {
		let otherWrapper = wrapper == "LazilyInstantiated" ? "SendableLazilyInstantiated" : "LazilyInstantiated"
		func receiveDeclaration(_ receive: UserReceive, ofType type: String) -> (parameter: String, declaration: String) {
			switch receive {
			case .required:
				("user: \(type)", "@Received let user: \(type)")
			case .requiredOptional:
				("user: \(type)?", "@Received let user: \(type)?")
			case .onlyIfAvailable:
				("user: \(type)?", "@Received(onlyIfAvailable: true) let user: \(type)?")
			}
		}
		func receiver(named name: String, receive: UserReceive, ofType type: String, sendable: Bool = false) -> String {
			let (parameter, declaration) = receiveDeclaration(receive, ofType: type)
			return """
			@Instantiable
			public struct \(name): Instantiable\(sendable ? ", Sendable" : "") {
			    public init(\(parameter)) {
			        self.user = user
			    }

			    \(declaration)
			}
			"""
		}
		var screenParameters = [String]()
		var screenAssignments = [String]()
		var screenDeclarations = [String]()
		if let own {
			let (parameter, declaration) = receiveDeclaration(own.receive, ofType: own.asWrapper ? "\(wrapper)<User>" : "User")
			screenParameters.append(parameter)
			screenAssignments.append("        self.user = user")
			screenDeclarations.append("    \(declaration)")
		}
		if detail != nil {
			if detailInSendableBuilder {
				screenParameters.append("detailBuilder: SendableInstantiator<Detail>")
				screenAssignments.append("        self.detailBuilder = detailBuilder")
				screenDeclarations.append("    @Instantiated let detailBuilder: SendableInstantiator<Detail>")
			} else {
				screenParameters.append("detail: Detail")
				screenAssignments.append("        self.detail = detail")
				screenDeclarations.append("    @Instantiated let detail: Detail")
			}
		}
		if summary != nil {
			screenParameters.append("summary: Summary")
			screenAssignments.append("        self.summary = summary")
			screenDeclarations.append("    @Instantiated let summary: Summary")
		}
		if preview != nil {
			screenParameters.append("preview: Preview")
			screenAssignments.append("        self.preview = preview")
			screenDeclarations.append("    @Instantiated let preview: Preview")
		}
		var files = [
			"""
			@Instantiable(generateDependencyTree: true)
			public struct Screen: Instantiable {
			    public init(\(screenParameters.joined(separator: ", "))) {
			\(screenAssignments.joined(separator: "\n"))
			    }

			\(screenDeclarations.joined(separator: "\n"))
			}
			""",
		]
		if let detail {
			files.append(receiver(named: "Detail", receive: detail, ofType: "User", sendable: detailInSendableBuilder))
		}
		if let summary {
			files.append(receiver(named: "Summary", receive: summary, ofType: "\(wrapper)<User>"))
		}
		if let preview {
			files.append(receiver(named: "Preview", receive: preview, ofType: "\(previewWrapper ?? wrapper)<User>"))
		}
		let userIsBuiltByRoot = switch caller {
		case .instance:
			"user: User"
		case .wrapper:
			"user: \(wrapper)<User>"
		case .otherWrapper:
			"user: \(otherWrapper)<User>"
		case .optionalInstance, .optionalWrapper, .instanceWhoseTreeBuildsScreen, .noCaller:
			""
		}
		switch caller {
		case .instance, .wrapper, .otherWrapper:
			files.append("""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(\(userIsBuiltByRoot), screen: Screen) {
			        self.user = user
			        self.screen = screen
			    }

			    @Instantiated let \(userIsBuiltByRoot)
			    @Instantiated let screen: Screen
			}
			""")
		case .optionalInstance, .optionalWrapper:
			let forwardedType = caller == .optionalInstance ? "User?" : "\(wrapper)<User>?"
			files.append("""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(featureBuilder: Instantiator<Feature>) {
			        self.featureBuilder = featureBuilder
			    }

			    @Instantiated let featureBuilder: Instantiator<Feature>
			}
			""")
			files.append("""
			@Instantiable
			public struct Feature: Instantiable {
			    public init(user: \(forwardedType), screen: Screen) {
			        self.user = user
			        self.screen = screen
			    }

			    @Forwarded let user: \(forwardedType)
			    @Instantiated let screen: Screen
			}
			""")
		case .instanceWhoseTreeBuildsScreen:
			files.append("""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(user: User) {
			        self.user = user
			    }

			    @Instantiated let user: User
			}
			""")
		case .noCaller:
			break
		}
		switch caller {
		case .instanceWhoseTreeBuildsScreen:
			files.append("""
			@Instantiable
			public final class User: Instantiable {
			    public init(screen: Screen) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Screen
			}
			""")
		case .instance, .optionalInstance, .wrapper, .otherWrapper, .optionalWrapper, .noCaller:
			files.append("""
			@Instantiable
			public final class User: Instantiable, Sendable {
			    public init() {}
			}
			""")
		}
		return files
	}

	private mutating func labelFormsOutput(_ files: [String]) async throws -> TestOutput {
		try await executeSafeDIToolTest(
			swiftFileContent: files,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsInstanceOfRequiredWrapperParameter_whenByValueReceiveIsRequired() async throws {
		// The tree requires the wrapper and the instance: the required wrapper parameter provides the instance to the
		// by-value receiver, which reads it, and the caller passes the wrapper it holds.
		let output = try await labelFormsOutput(Self.labelFormsFixture(detail: .required, summary: .required, caller: .wrapper))
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(user: LazilyInstantiated<User>) {
		        let detail = Detail(user: user.instance)
		        let summary = Summary(user: user)
		        self.init(detail: detail, summary: summary)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_F630901E5C2B99B5 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_user() -> User {
		            User()
		        }
		        let user = LazilyInstantiated<User>(__safeDI_user)
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_F630901E5C2B99B5.self
		            return Screen(user: user)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, screen: screen)
		    }
		}
		""")
	}

	// Kept by hand: the seam corpus draws this shape in 2 graphs and accepts none (census at 3b12802a); delete when the
	// per-shape accepted pin reaches 3.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilForWrapper_whenOnlyWrapperIsReceivedOnlyIfAvailableAndCallerHoldsOtherWrapperKind() async throws {
		// A `SendableLazilyInstantiated` the caller holds is no `LazilyInstantiated`: the optional parameter is passed
		// `nil`, as an only-if-available receive of the wrapper is inline.
		let output = try await labelFormsOutput(Self.labelFormsFixture(detail: nil, summary: .onlyIfAvailable, caller: .otherWrapper))
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(user: LazilyInstantiated<User>?) {
		        let summary = Summary(user: user)
		        self.init(summary: summary)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_71C706F9FE9BEAFE {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        @Sendable func __safeDI_user() -> User {
		            User()
		        }
		        let user = SendableLazilyInstantiated<User>(__safeDI_user)
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_71C706F9FE9BEAFE.self
		            return Screen(user: nil)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, screen: screen)
		    }
		}
		""")
	}

	// Kept by hand: the regression pin of a defect review 4 found (a seam read `user?.instance` where inline passes
	// `nil`), a shape the seam corpus draws in 7 graphs and accepts in none (census at 3b12802a).
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilForInstance_whenByValueReceiveIsOnlyIfAvailableAndCallerForwardsOptionalWrapper() async throws {
		// An optional wrapper offers no instance, inline or across a seam: the optional by-value parameter is passed
		// `nil`.
		let output = try await labelFormsOutput(Self.labelFormsFixture(detail: .onlyIfAvailable, summary: nil, caller: .optionalWrapper))
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(user: User?) {
		        let detail = Detail(user: user)
		        self.init(detail: detail)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_0A0B087775B360DD {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_featureBuilder(user: LazilyInstantiated<User>?) -> Feature {
		            func __safeDI_screen() -> Screen {
		                _ = Screen.__safeDI_Screen_0A0B087775B360DD.self
		                return Screen(user: nil)
		            }
		            let screen: Screen = __safeDI_screen()
		            return Feature(user: user, screen: screen)
		        }
		        let featureBuilder = Instantiator<Feature> {
		            __safeDI_featureBuilder(user: $0)
		        }
		        self.init(featureBuilder: featureBuilder)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilForInstance_whenInstancesOwnTreeBuildsSeam() async throws {
		// Inside the tree that builds `user`, the only-if-available receive of it is passed `nil`, as it is inline.
		let output = try await labelFormsOutput(Self.labelFormsFixture(detail: .onlyIfAvailable, summary: nil, caller: .instanceWhoseTreeBuildsScreen))
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(user: User?) {
		        let detail = Detail(user: user)
		        self.init(detail: detail)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_0A0B087775B360DD {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_user() -> User {
		            func __safeDI_screen() -> Screen {
		                _ = Screen.__safeDI_Screen_0A0B087775B360DD.self
		                return Screen(user: nil)
		            }
		            let screen: Screen = __safeDI_screen()
		            return User(screen: screen)
		        }
		        let user: User = __safeDI_user()
		        self.init(user: user)
		    }
		}
		""")
	}

	// Kept by hand: the seam corpus draws the required variant's shape in 4 graphs and accepts none (census at 3b12802a);
	// delete when the per-shape accepted pin reaches 3.
	@Test(arguments: [UserReceive.required, UserReceive.onlyIfAvailable])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesSeamsOwnByValueReceive_whenByValueReceiveInsideIsRequiredOrOnlyIfAvailable(detail: UserReceive) async throws {
		// The seam's own `@Received let user: User` provides every by-value receive of `user` inside.
		let output = try await labelFormsOutput(Self.labelFormsFixture(detail: detail, summary: nil, own: (.required, asWrapper: false), caller: .instance))
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(user: User) {
		        let detail = Detail(user: user)
		        self.init(user: user, detail: detail)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_38882A8C29DA6D12 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let user = User()
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_38882A8C29DA6D12.self
		            return Screen(user: user)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, screen: screen)
		    }
		}
		""")
	}

	// Kept by hand: the seam corpus draws this shape in 6 graphs and accepts none (census at 3b12802a), and a wrong
	// rejection here is a seam's own error, which no oracle judges; delete when the per-shape accepted pin reaches 3.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_capturesSendableWrapperParameter_whenSendableBuilderInsideSeamReadsItsInstance() async throws {
		// A `SendableLazilyInstantiated` parameter is `Sendable`, so the `@Sendable` builder of `detailBuilder` may
		// capture it to read its instance: no error, and the generated code compiles.
		let output = try await labelFormsOutput(Self.labelFormsFixture(detail: .required, summary: .required, wrapper: "SendableLazilyInstantiated", caller: .wrapper, detailInSendableBuilder: true))
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(user: SendableLazilyInstantiated<User>) {
		        @Sendable func __safeDI_detailBuilder() -> Detail {
		            Detail(user: user.instance)
		        }
		        let detailBuilder = SendableInstantiator<Detail>(__safeDI_detailBuilder)
		        let summary = Summary(user: user)
		        self.init(detailBuilder: detailBuilder, summary: summary)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_307551CFFDF140EB {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        @Sendable func __safeDI_user() -> User {
		            User()
		        }
		        let user = SendableLazilyInstantiated<User>(__safeDI_user)
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_307551CFFDF140EB.self
		            return Screen(user: user)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, screen: screen)
		    }
		}
		""")
	}

	/// `Screen`, a seam whose `Detail` declares an alias `currentUser` of `user` – required, or only if available
	/// when `onlyIfAvailable` – and whose `Summary` receives `user` as the wrapper, required or only if available
	/// as `summary` says, called from a root holding `user: LazilyInstantiated<User>`.
	private static func aliasOfLabelFixture(onlyIfAvailable: Bool, summary: UserReceive) -> [String] {
		let summaryDeclaration = switch summary {
		case .required:
			("user: LazilyInstantiated<User>", "@Received let user: LazilyInstantiated<User>")
		case .requiredOptional:
			("user: LazilyInstantiated<User>?", "@Received let user: LazilyInstantiated<User>?")
		case .onlyIfAvailable:
			("user: LazilyInstantiated<User>?", "@Received(onlyIfAvailable: true) let user: LazilyInstantiated<User>?")
		}
		return [
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(user: LazilyInstantiated<User>, screen: Screen) {
			        self.user = user
			        self.screen = screen
			    }

			    @Instantiated let user: LazilyInstantiated<User>
			    @Instantiated let screen: Screen
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public struct Screen: Instantiable {
			    public init(detail: Detail, summary: Summary) {
			        self.detail = detail
			        self.summary = summary
			    }

			    @Instantiated let detail: Detail
			    @Instantiated let summary: Summary
			}
			""",
			"""
			@Instantiable
			public struct Detail: Instantiable {
			    public init(currentUser: User\(onlyIfAvailable ? "?" : "")) {
			        self.currentUser = currentUser
			    }

			    @Received(fulfilledByDependencyNamed: "user", ofType: User.self\(onlyIfAvailable ? ", onlyIfAvailable: true" : "")) let currentUser: User\(onlyIfAvailable ? "?" : "")
			}
			""",
			"""
			@Instantiable
			public struct Summary: Instantiable {
			    public init(\(summaryDeclaration.0)) {
			        self.user = user
			    }

			    \(summaryDeclaration.1)
			}
			""",
			"""
			@Instantiable
			public final class User: Instantiable, Sendable {
			    public init() {}
			}
			""",
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsAliasFromWrappersInstance_whenTreeRequiresAliasOfLabelReceivedAsRequiredWrapper() async throws {
		// The alias's fulfilling property `user: User` is a by-value form of `user`, which the required wrapper
		// parameter provides: the alias is created from its instance.
		let output = try await labelFormsOutput(Self.aliasOfLabelFixture(onlyIfAvailable: false, summary: .required))
		let detailPath = output.fixtures["Detail.swift"]
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(user: LazilyInstantiated<User>) {
		        func __safeDI_detail() -> Detail {
		            #sourceLocation(file: "\(detailPath)", line: 7)
		            let currentUser: User = user.instance
		            #sourceLocation()
		            return Detail(currentUser: currentUser)
		        }
		        let detail: Detail = __safeDI_detail()
		        let summary = Summary(user: user)
		        self.init(detail: detail, summary: summary)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_F630901E5C2B99B5 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_user() -> User {
		            User()
		        }
		        let user = LazilyInstantiated<User>(__safeDI_user)
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_F630901E5C2B99B5.self
		            return Screen(user: user)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, screen: screen)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsOnlyIfAvailableAliasFromWrappersInstance_whenLabelIsReceivedAsRequiredWrapper() async throws {
		// An only-if-available alias of the instance is created too: a required wrapper's instance is always available.
		let output = try await labelFormsOutput(Self.aliasOfLabelFixture(onlyIfAvailable: true, summary: .required))
		let detailPath = output.fixtures["Detail.swift"]
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(user: LazilyInstantiated<User>) {
		        func __safeDI_detail() -> Detail {
		            #sourceLocation(file: "\(detailPath)", line: 7)
		            let currentUser: User? = user.instance
		            #sourceLocation()
		            return Detail(currentUser: currentUser)
		        }
		        let detail: Detail = __safeDI_detail()
		        let summary = Summary(user: user)
		        self.init(detail: detail, summary: summary)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_F630901E5C2B99B5 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_user() -> User {
		            User()
		        }
		        let user = LazilyInstantiated<User>(__safeDI_user)
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_F630901E5C2B99B5.self
		            return Screen(user: user)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, screen: screen)
		    }
		}
		""")
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenTreeAliasesLabelReceivedAsOptionalWrapper(onlyIfAvailable: Bool) async {
		// The alias's fulfilling property `user: User` is a by-value form, and an optional wrapper provides nothing
		// but itself: two parameters under one label, named with the alias's declaration.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `user` as `user: User` on `Detail` and `user: LazilyInstantiated<User>?` on `Summary`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `user` the same way in every type of the tree, or declare it on `Screen` as the form that provides the others: `@Received let user: LazilyInstantiated<User>`.
			\(fixtures["Detail.swift"]):7:5: note: `Detail` receives `user: User` here.
			\(fixtures["Summary.swift"]):7:5: note: `Summary` receives `user: LazilyInstantiated<User>?` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.aliasOfLabelFixture(onlyIfAvailable: onlyIfAvailable, summary: .onlyIfAvailable),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsInlinedValidationsError_whenCallerHoldsOnlyInstanceOfRequiredWrapper() async {
		// A required wrapper the caller's chain lacks is rejected by the inlined validation, as it is without the
		// seam: the seam never wraps an instance for it.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Summary.swift"]):7:5: error: @Received property `user: LazilyInstantiated<User>` is not @Instantiated or @Forwarded in chain: Root -> Screen -> Summary. Did you mean `user: User`?
			\(fixtures["Summary.swift"]):7:25-7:49: fixit: User
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.labelFormsFixture(detail: .onlyIfAvailable, summary: .required, caller: .instance),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	/// A mix of `user`'s forms the seam supports, as the single-module cell of the same name pins it, built with the
	/// seam and its tree in `Core` and the caller in `App`: `seamCode` is what `Core` generates and `rootCode` what
	/// `App` generates, with `<COMMENT>` where the plugin's call carries its comment and `<DETAIL-PATH>` for
	/// `Detail.swift`'s path as the compiler is handed it; `rootWarning`, with `<ROOT-PATH>` for `Root.swift`'s path,
	/// is the warning `App` reports where the seam's tree reads the instance of the wrapper `Root` instantiates
	/// whenever `Root` is created, as it would were the tree built inline.
	struct LabelFormsCell: Sendable, CustomTestStringConvertible {
		let name: String
		let fixture: [String]
		let seamCode: String
		let rootCode: String
		var rootWarning: String?

		var testDescription: String {
			name
		}
	}

	static let labelFormsCells: [LabelFormsCell] = [
		.init(
			name: "readsInstanceOfRequiredWrapperParameter_whenByValueReceiveIsRequired",
			fixture: Self.labelFormsFixture(detail: .required, summary: .required, caller: .wrapper),
			seamCode: """
			extension Screen {
			    public init(user: LazilyInstantiated<User>) {
			        let detail = Detail(user: user.instance)
			        let summary = Summary(user: user)
			        self.init(detail: detail, summary: summary)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_F630901E5C2B99B5 {}
			}
			""",
			rootCode: """
			extension Root {
			    public init() {
			        func __safeDI_user() -> User {
			            User()
			        }
			        let user = LazilyInstantiated<User>(__safeDI_user)
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_F630901E5C2B99B5.self<COMMENT>
			            return Screen(user: user)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(user: user, screen: screen)
			    }
			}
			""",
			rootWarning: "<ROOT-PATH>:10:5: warning: @Instantiated property `user: LazilyInstantiated<User>` is instantiated whenever `Root` is created: `Detail` is created with `Root` and receives the instance as `user: User`. To instantiate it lazily, receive `user: LazilyInstantiated<User>` on `Detail`.",
		),
	]

	@Test(arguments: labelFormsCells, MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamAcrossModules_whenSeamsTreeReceivesLabelInSupportedForms(cell: LabelFormsCell, integration: MultiModuleIntegration) async throws {
		// A mix of one label's forms, with the seam and its tree in `Core` and the caller in `App`: the seam's module and
		// the caller compute one signature from the declarations each sees, under both integrations, the call passes what
		// the caller's tree holds, and `App` warns where the seam's tree reads the instance. Every other mix, in one
		// module and across modules, is the graph fuzzer's (`addingLabelFormsSeam`).
		func isCallerFile(_ content: String) -> Bool {
			content.contains("public struct Root: Instantiable") || content.contains("public struct Feature: Instantiable")
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Core",
					packageName: "Shop",
					swiftFileContent: cell.fixture.filter { !isCallerFile($0) },
				),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContent: cell.fixture.filter(isCallerFile).map { "import Core\n\n" + $0 },
					dependencies: ["Core"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let callComment = integration.seamCallComment(type: "Screen", declaringModule: "Core")
		let core = try #require(output.modules["Core"])
		let app = try #require(output.modules["App"])
		let seamCode = cell.seamCode.contains("<DETAIL-PATH>")
			? cell.seamCode.replacingOccurrences(of: "<DETAIL-PATH>", with: core.fixtures.compilerPath(of: "Detail.swift"))
			: cell.seamCode
		let rootCode = cell.rootCode.replacingOccurrences(of: "<COMMENT>", with: callComment)
		let expectedGeneratedFiles: [String: [String: String]] = switch integration {
		case .moduleInfo:
			[
				"Core": ["Core.swift": generatedFileHeader + seamCode],
				"App": ["App.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + rootCode],
			]
		case .swiftPackagePlugin:
			[
				"Core": ["Screen+SafeDI.swift": generatedFileHeader + seamCode],
				"App": ["Root+SafeDI.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + rootCode],
			]
		}
		#expect(output.modules.mapValues(\.generatedFiles) == expectedGeneratedFiles)
		#expect(core.warnings == [])
		// A warning cites the path the file was parsed under: the compiler's spelling, normalized.
		let rootPath = NormalizedFilePath(app.fixtures.compilerPath(of: "Root.swift")).path
		#expect(app.warnings.map(\.formatted) == [cell.rootWarning?.replacingOccurrences(of: "<ROOT-PATH>", with: rootPath)].compactMap(\.self))
		if compileVerificationIsEnabled {
			let compilation = try #require(output.compilation)
			#expect(compilation.modules.map(\.exitCode) == [0, 0])
		}
	}

	/// A mix of `user`'s forms that is two parameters under one label: the receives the seam's error names, in tree
	/// order, and the form the remedy says to declare on the seam.
	struct LabelFormsMix: Sendable, CustomTestStringConvertible {
		struct Receive: Sendable {
			let type: String
			let property: String
			let line: Int
		}

		let name: String
		let detail: UserReceive?
		let summary: UserReceive?
		var preview: UserReceive?
		var previewWrapper: String?
		var own: (receive: UserReceive, asWrapper: Bool)?
		var wrapper = "LazilyInstantiated"
		let caller: CallerHolding
		let receives: [Receive]
		/// What the error says to do.
		let remedy: Remedy

		enum Remedy: Sendable {
			/// Receive the label the same way, or declare the form on the seam.
			case declare(String)
			case receiveOneWrapperKind
			case receiveTheSameWay
			case rename

			var text: String {
				switch self {
				case let .declare(providingForm):
					"Receive `user` the same way in every type of the tree, or declare it on `Screen` as the form that provides the others: `@Received let user: \(providingForm)`."
				case .receiveOneWrapperKind:
					"Receive `user` as one wrapper kind in every type of the tree."
				case .receiveTheSameWay:
					"Receive `user` the same way in every type of the tree."
				case .rename:
					"Rename one of the properties, or @Instantiated one of them inside the tree."
				}
			}
		}

		var testDescription: String {
			name
		}
	}

	static let labelFormsMixes: [LabelFormsMix] = {
		let byValue = LabelFormsMix.Receive(type: "Detail", property: "user: User", line: 7)
		let optionalByValue = LabelFormsMix.Receive(type: "Detail", property: "user: User?", line: 7)
		let optionalWrapper = LabelFormsMix.Receive(type: "Summary", property: "user: LazilyInstantiated<User>?", line: 7)
		let optionalSendableWrapper = LabelFormsMix.Receive(type: "Summary", property: "user: SendableLazilyInstantiated<User>?", line: 7)
		return [
			.init(name: "required by value and optional wrapper, instance declared first", detail: .required, summary: .onlyIfAvailable, caller: .instance, receives: [byValue, optionalWrapper], remedy: .declare("LazilyInstantiated<User>")),
			.init(name: "required by value and optional Sendable wrapper, caller holds LazilyInstantiated", detail: .required, summary: .onlyIfAvailable, wrapper: "SendableLazilyInstantiated", caller: .otherWrapper, receives: [byValue, optionalSendableWrapper], remedy: .declare("SendableLazilyInstantiated<User>")),
			// A required `user: User?` beside a wrapper: no form the inlined validation accepts provides both, since the
			// wrapper's instance is non-optional, so the remedy names none.
			.init(name: "required optional by value and optional wrapper, caller forwards an optional instance", detail: .requiredOptional, summary: .onlyIfAvailable, caller: .optionalInstance, receives: [optionalByValue, optionalWrapper], remedy: .receiveTheSameWay),
			.init(name: "seam's own only-if-available by-value receive and required by value inside", detail: .required, summary: nil, own: (.onlyIfAvailable, asWrapper: false), caller: .instance, receives: [.init(type: "Screen", property: "user: User?", line: 8), byValue], remedy: .declare("User")),
			.init(name: "two wrapper kinds", detail: nil, summary: .onlyIfAvailable, preview: .onlyIfAvailable, previewWrapper: "SendableLazilyInstantiated", caller: .wrapper, receives: [optionalWrapper, .init(type: "Preview", property: "user: SendableLazilyInstantiated<User>?", line: 7)], remedy: .receiveOneWrapperKind),
			// An `Instantiator` form is another type than the by-value form or the wrapper's instance: no declaration
			// on the seam provides both, so the remedy is to rename.
			.init(name: "required by value and optional Instantiator", detail: .required, summary: nil, preview: .onlyIfAvailable, previewWrapper: "Instantiator", caller: .instance, receives: [byValue, .init(type: "Preview", property: "user: Instantiator<User>?", line: 7)], remedy: .rename),
			// A required optional wrapper beside a required by-value form. With a caller, the inlined validation rejects the
			// required by-value form first, so this runs in a module with no root.
			.init(name: "required optional wrapper and required by value, no root", detail: .required, summary: .requiredOptional, caller: .noCaller, receives: [byValue, optionalWrapper], remedy: .declare("LazilyInstantiated<User>")),
		]
	}()

	@Test(arguments: labelFormsMixes)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenFormsOfOneLabelAreTwoParameters(mix: LabelFormsMix) async {
		// A by-value form beside an optional wrapper, two wrapper kinds, or the seam's own receive beside a form it
		// does not provide: two parameters under one label, whatever the caller holds, since the seam's signature is
		// computed from its tree alone. One mix for each remedy the error gives; every other mix is the graph fuzzer's
		// (`addingLabelFormsSeam`).
		await assertThrowsError(diagnostics: { fixtures in
			let forms = mix.receives.map { "`\($0.property)` on `\($0.type)`" }.joined(separator: " and ")
			let notes = mix.receives.map { "\n\(fixtures["\($0.type).swift"]):\($0.line):5: note: `\($0.type)` receives `\($0.property)` here." }.joined()
			return "\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `user` as \(forms), and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. \(mix.remedy.text)\(notes)"
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.labelFormsFixture(
					detail: mix.detail,
					summary: mix.summary,
					preview: mix.preview,
					previewWrapper: mix.previewWrapper,
					own: mix.own,
					wrapper: mix.wrapper,
					caller: mix.caller,
				),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_listsReceiverOnce_whenSeamsTreeClosesLazyCycleOnTypeReceivingLabel() async {
		// `Detail` and `Summary` build each other through `Instantiator`s inside the seam, so the generator tree
		// reaches `Detail` twice, the second time as the scope that closes the cycle on `detailBuilder` and generates
		// nothing. The closing scope is built for a property on the stack, so its type is the ancestor's: its receive
		// of `token` is the same declaration, listed once in the collision with `Tracker`'s receive.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `token` as `token: Token` on `Detail` and `token: String` on `Tracker`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.
			\(fixtures["Detail.swift"]):8:5: note: `Detail` receives `token: Token` here.
			\(fixtures["Tracker.swift"]):7:5: note: `Tracker` receives `token: String` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(detailBuilder: Instantiator<Detail>, tracker: Tracker) {
					        self.detailBuilder = detailBuilder
					        self.tracker = tracker
					    }

					    @Instantiated let detailBuilder: Instantiator<Detail>
					    @Instantiated let tracker: Tracker
					}
					""",
					"""
					@Instantiable
					public struct Detail: Instantiable {
					    public init(token: Token, summaryBuilder: Instantiator<Summary>) {
					        self.token = token
					        self.summaryBuilder = summaryBuilder
					    }

					    @Received let token: Token
					    @Instantiated let summaryBuilder: Instantiator<Summary>
					}
					""",
					"""
					@Instantiable
					public struct Summary: Instantiable {
					    public init(detailBuilder: Instantiator<Detail>) {
					        self.detailBuilder = detailBuilder
					    }

					    @Instantiated let detailBuilder: Instantiator<Detail>
					}
					""",
					"""
					@Instantiable
					public struct Tracker: Instantiable {
					    public init(token: String) {
					        self.token = token
					    }

					    @Received let token: String
					}
					""",
					"""
					@Instantiable
					public struct Token: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Alias fallbacks

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsEachAliasFromParameter_whenTwoTypesDeclareTheSameAliasAndOneHasReaderBeneath() async throws {
		// `First` and `Second` both declare the only-if-available alias of `token`; `Reader`, beneath `First`, reads `First`'s binding.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(authToken: Token, token: Token, screen: Screen) {
				        self.authToken = authToken
				        self.token = token
				        self.screen = screen
				    }

				    @Instantiated let authToken: Token
				    @Instantiated let token: Token
				    @Instantiated let screen: Screen
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(first: First, second: Second) {
				        self.first = first
				        self.second = second
				    }

				    @Instantiated let first: First
				    @Instantiated let second: Second
				}
				""",
				"""
				@Instantiable
				public struct First: Instantiable {
				    public init(authToken: Token?, reader: Reader) {
				        self.authToken = authToken
				        self.reader = reader
				    }

				    @Received(fulfilledByDependencyNamed: "token", ofType: Token.self, onlyIfAvailable: true) let authToken: Token?
				    @Instantiated let reader: Reader
				}
				""",
				"""
				@Instantiable
				public struct Second: Instantiable {
				    public init(authToken: Token?) {
				        self.authToken = authToken
				    }

				    @Received(fulfilledByDependencyNamed: "token", ofType: Token.self, onlyIfAvailable: true) let authToken: Token?
				}
				""",
				"""
				@Instantiable
				public struct Reader: Instantiable {
				    public init(authToken: Token?) {
				        self.authToken = authToken
				    }

				    @Received(onlyIfAvailable: true) let authToken: Token?
				}
				""",
				"""
				@Instantiable
				public struct Token: Instantiable {
				    public init() {}
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
			        let authToken = Token()
			        let token = Token()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_029593DA1BB2FBD5.self
			            return Screen(token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(authToken: authToken, token: token, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public init(token: Token?) {
			        func __safeDI_first() -> First {
			            #sourceLocation(file: "\(output.fixtures["First.swift"])", line: 8)
			            let authToken: Token? = token
			            #sourceLocation()
			            let reader = Reader(authToken: authToken)
			            return First(authToken: authToken, reader: reader)
			        }
			        let first: First = __safeDI_first()
			        func __safeDI_second() -> Second {
			            #sourceLocation(file: "\(output.fixtures["Second.swift"])", line: 7)
			            let authToken: Token? = token
			            #sourceLocation()
			            return Second(authToken: authToken)
			        }
			        let second: Second = __safeDI_second()
			        self.init(first: first, second: second)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_029593DA1BB2FBD5 {}
			}
			""",
		])
	}

	/// `Root` holding an erased `anyToken`, a seam `Screen` whose `Session` declares an erased `onlyIfAvailable`
	/// alias `anyToken` of `token` and instantiates a `Reader` that receives `anyToken` only if available.
	private static func erasedAliasWithReaderFixture(seam: Bool) -> [String] {
		[
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(anyToken: AnyToken, screen: Screen) {
			        self.anyToken = anyToken
			        self.screen = screen
			    }

			    @Instantiated(fulfilledByType: "Token", erasedToConcreteExistential: true) let anyToken: AnyToken
			    @Instantiated let screen: Screen
			}
			""",
			"""
			@Instantiable\(seam ? "(generateDependencyTree: true)" : "")
			public struct Screen: Instantiable {
			    public init(session: Session) {
			        self.session = session
			    }

			    @Instantiated let session: Session
			}
			""",
			"""
			@Instantiable
			public struct Session: Instantiable {
			    public init(anyToken: AnyToken?, reader: Reader) {
			        self.anyToken = anyToken
			        self.reader = reader
			    }

			    @Received(fulfilledByDependencyNamed: "token", ofType: Token.self, erasedToConcreteExistential: true, onlyIfAvailable: true) let anyToken: AnyToken?
			    @Instantiated let reader: Reader
			}
			""",
			"""
			@Instantiable
			public struct Reader: Instantiable {
			    public init(anyToken: AnyToken?) {
			        self.anyToken = anyToken
			    }

			    @Received(onlyIfAvailable: true) let anyToken: AnyToken?
			}
			""",
			"""
			@Instantiable
			public struct Token: Instantiable, TokenProtocol {
			    public init() {}
			}

			public protocol TokenProtocol {}

			public struct AnyToken: TokenProtocol {
			    public init(_ token: some TokenProtocol) {}
			}
			""",
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsErasedAliasFromParameter_whenReaderBeneathReadsIt() async throws {
		// An erased only-if-available alias maps the pass-through `token`, and `Reader` reads its binding.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.erasedAliasWithReaderFixture(seam: true),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let anyToken = AnyToken(Token())
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_029593DA1BB2FBD5.self
			            return Screen(token: nil)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(anyToken: anyToken, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public init(token: Token?) {
			        func __safeDI_session() -> Session {
			            #sourceLocation(file: "\(output.fixtures["Session.swift"])", line: 8)
			            let anyToken: AnyToken? = (token as Token?).map { AnyToken($0) }
			            #sourceLocation()
			            let reader = Reader(anyToken: anyToken)
			            return Session(anyToken: anyToken, reader: reader)
			        }
			        let session: Session = __safeDI_session()
			        self.init(session: session)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_029593DA1BB2FBD5 {}
			}
			""",
		])
	}

	// MARK: Tiers and foreign seams

	/// `Screen`, a public seam, reaches `Internals.Panel`, an internal seam whose tree receives `session` from the
	/// public `Detail`, required or only if available.
	private static func nestedSeamFixture(detailReceivesOnlyIfAvailable: Bool) -> [String] {
		[
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
			    public init(panel: AnyPanel) {
			        self.panel = panel
			    }

			    @Instantiated(fulfilledByType: "Internals.Panel", erasedToConcreteExistential: true) let panel: AnyPanel
			}

			public protocol PanelProtocol {}

			public struct AnyPanel: PanelProtocol {
			    public init(_ panel: some PanelProtocol) {}
			}
			""",
			"""
			internal enum Internals {
			    @Instantiable(generateDependencyTree: true)
			    public struct Panel: Instantiable, PanelProtocol {
			        public init(detail: Detail) {
			            self.detail = detail
			        }

			        @Instantiated let detail: Detail
			    }
			}
			""",
			"""
			@Instantiable
			public struct Detail: Instantiable {
			    public init(session: Session\(detailReceivesOnlyIfAvailable ? "?" : "")) {
			        self.session = session
			    }

			    @Received\(detailReceivesOnlyIfAvailable ? "(onlyIfAvailable: true)" : "") let session: Session\(detailReceivesOnlyIfAvailable ? "?" : "")
			}
			""",
			"""
			@Instantiable
			public struct Session: Instantiable {
			    public init() {}
			}
			""",
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesInnerSeamsParameterAtItsReceiversAccess_whenInnerSeamsTypeIsInternal() async throws {
		// `Internals.Panel`'s tiers are capped at internal, but its `session` parameter comes from the public
		// `Detail`, so `Screen`, which passes it on, takes it at public: its public tier takes it rather than
		// reporting that it cannot.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.nestedSeamFixture(detailReceivesOnlyIfAvailable: false),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles["Panel+SafeDI.swift"] == generatedFileHeader + """
		extension Internals.Panel {
		    internal init(session: Session) {
		        let detail = Detail(session: session)
		        self.init(detail: detail)
		    }
		}

		extension Internals.Panel {
		    public enum __safeDI_Internals_Panel_222C5EA02E0FB9FA {}
		}
		""")
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(session: Session) {
		        func __safeDI_panel() -> Internals.Panel {
		            _ = Internals.Panel.__safeDI_Internals_Panel_222C5EA02E0FB9FA.self
		            return Internals.Panel(session: session)
		        }
		        let panel = AnyPanel(__safeDI_panel())
		        self.init(panel: panel)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_13A4BC800B514232 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let session = Session()
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_13A4BC800B514232.self
		            return Screen(session: session)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(session: session, screen: screen)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesInnerSeamsOptionalParameterAtItsReceiversAccess_whenInnerSeamsTypeIsInternal() async throws {
		// As above, with `session` received only if available: `Screen`'s public tier takes it and passes it on
		// rather than passing `nil` for a parameter it dropped.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.nestedSeamFixture(detailReceivesOnlyIfAvailable: true),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles["Panel+SafeDI.swift"] == generatedFileHeader + """
		extension Internals.Panel {
		    internal init(session: Session?) {
		        let detail = Detail(session: session)
		        self.init(detail: detail)
		    }
		}

		extension Internals.Panel {
		    public enum __safeDI_Internals_Panel_3281EFBD25960621 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(session: Session?) {
		        func __safeDI_panel() -> Internals.Panel {
		            _ = Internals.Panel.__safeDI_Internals_Panel_3281EFBD25960621.self
		            return Internals.Panel(session: session)
		        }
		        let panel = AnyPanel(__safeDI_panel())
		        self.init(panel: panel)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_75FDE4A4CAE60A7D {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let session = Session()
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_75FDE4A4CAE60A7D.self
		            return Screen(session: session)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(session: session, screen: screen)
		    }
		}
		""")
	}

	/// `Core`'s seam `Service`, which fulfills `ServiceProtocol`, with `Cache` receiving `logger` only if available
	/// when `cacheReceivesLogger`.
	private static func coreServiceSeamFiles(cacheReceivesLogger: Bool) -> [String] {
		[
			"""
			\(cacheReceivesLogger ? "import Base\n\n" : "")@Instantiable(generateDependencyTree: true, fulfillingAdditionalTypes: [ServiceProtocol.self])
			public struct Service: Instantiable, ServiceProtocol {
			    public init(cache: Cache) {
			        self.cache = cache
			    }

			    @Instantiated let cache: Cache
			}

			public protocol ServiceProtocol {}
			""",
			"""
			\(cacheReceivesLogger ? "import Base\n\n" : "")@Instantiable
			public struct Cache: Instantiable {
			    public init(\(cacheReceivesLogger ? "logger: Logger?" : "")) {\(cacheReceivesLogger ? "\n        self.logger = logger" : "")
			    }
			\(cacheReceivesLogger ? "\n    @Received(onlyIfAvailable: true) let logger: Logger?" : "")
			}
			""",
		]
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamsInitializer_whenRootInAnotherModuleReachesSeamAsItsAdditionalType(integration: MultiModuleIntegration) async throws {
		// `Root` instantiates `Service` as `any ServiceProtocol`, one of its additional types: the seam is
		// found through the key that reached it, so `Root` calls its generated initializer.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Core",
					packageName: "Shop",
					swiftFileContent: Self.coreServiceSeamFiles(cacheReceivesLogger: false),
				),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContent: [
						"""
						import Core

						@Instantiable(isRoot: true)
						public struct Root: Instantiable {
						    public init(service: any ServiceProtocol) {
						        self.service = service
						    }

						    @Instantiated let service: any ServiceProtocol
						}
						""",
					],
					dependencies: ["Core"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let callComment = integration.seamCallComment(type: "Service", declaringModule: "Core")
		let serviceCode = """
		extension Service {
		    public init() {
		        let cache = Cache()
		        self.init(cache: cache)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_CBF29CE484222325 {}
		}
		"""
		let rootCode = """
		extension Root {
		    public init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_CBF29CE484222325.self\(callComment)
		            return Service()
		        }
		        let service: any ServiceProtocol = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""
		let expectedGeneratedFiles: [String: [String: String]] = switch integration {
		case .moduleInfo:
			[
				"Core": ["Core.swift": generatedFileHeader + serviceCode],
				"App": ["App.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + rootCode],
			]
		case .swiftPackagePlugin:
			[
				"Core": ["Service+SafeDI.swift": generatedFileHeader + serviceCode],
				"App": ["Root+SafeDI.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + rootCode],
			]
		}
		#expect(output.modules.mapValues(\.generatedFiles) == expectedGeneratedFiles)
		for moduleName in output.moduleNames {
			#expect(try #require(output.modules[moduleName]).warnings == [])
		}
		if compileVerificationIsEnabled {
			let compilation = try #require(output.compilation)
			#expect(compilation.modules.map(\.exitCode) == [0, 0])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamReachedAsItsAdditionalTypeIsOfModuleWhoseDependencysModuleInfoIsNotGiven() async {
		// As above, under the `.safedi` flow, with `Core` naming `Base`, which `App` is not given: the seam
		// reached as `any ServiceProtocol` is a reached seam, so the missing module info is reported.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Service.swift"]):3:1: error: SafeDI cannot generate a call to the initializer SafeDI generated for `Service` in module `Core`: that initializer takes what the type's dependency tree needs from the declarations `Core` sees, which include module `Base`'s, and this run was not given `Base`'s SafeDI module info. Give this run every module `Core` depends on: add `Base`'s `Base_safedi` target to this target's `safedi_deps` under Bazel (the `deps` of a hand-written `safedi_compile`), add `Base` to the `dependencies:` of this target's `SafeDI.preCompileScript` under Tuist, or pass its `.safedi` file to `--dependent-module-info-file-path`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Base",
						packageName: "Shop",
						swiftFileContent: [Self.loggerContent],
					),
					ModuleFixture(
						name: "Core",
						packageName: "Shop",
						swiftFileContent: Self.coreServiceSeamFiles(cacheReceivesLogger: true),
						dependencies: ["Base"],
					),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [
							"""
							import Core

							@Instantiable(isRoot: true)
							public struct Root: Instantiable {
							    public init(service: any ServiceProtocol) {
							        self.service = service
							    }

							    @Instantiated let service: any ServiceProtocol
							}
							""",
						],
						dependencies: ["Core"],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenItsTreeInstantiatesDeclarationOfModuleInfoNamingNoModule() async {
		// `Base`'s module info was written without `--module-name`, so the modules that call `Cache` compute its
		// signature without `Logger`, which `Store` instantiates: for them `Store`'s `logger` is a hole, whose builder
		// `Cache`'s generated initializer would take, while `Core`, which sees `Logger`, builds it. The calls would not
		// match the initializer, so `Core` reports `Cache`, naming `Logger`.
		await assertThrowsMultiModuleError(inModule: "Core", diagnostics: { fixtures in
			"\(fixtures["Core"]!["Cache.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Cache`: the initializer SafeDI generates for it depends on `Logger`, which is declared in a module whose SafeDI module info names no module, and the modules that call that initializer, which compute its signature from the modules this module's module info names, cannot see that declaration, so their calls would not match the initializer. Generate that module's module info with `--module-name`."
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Base",
						packageName: "Shop",
						swiftFileContent: [Self.loggerContent],
						omitsModuleName: true,
					),
					ModuleFixture(
						name: "Core",
						packageName: "Shop",
						swiftFileContent: [
							"""
							import Base

							@Instantiable(generateDependencyTree: true)
							public struct Cache: Instantiable {
							    public init(store: Store) {
							        self.store = store
							    }

							    @Instantiated let store: Store
							}
							""",
							"""
							import Base

							@Instantiable
							public struct Store: Instantiable {
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
	mutating func generate_throwsError_whenSeamsTreeReachesAdditionalDirectoryDeclarationAsItsAdditionalTypeUnderTargetGraph() async {
		// `Screen` reaches the additional-directory `Detail` as `any DetailProtocol`, one of its additional
		// types: reported by the declaration reached, whichever key reached it.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: the initializer SafeDI generates for it depends on `Detail`, which is declared in a directory this module's `#SafeDIConfiguration` adds, and the modules that call that initializer cannot see that declaration, so their calls would not match the initializer. Declare `Detail` in a file of this module, or of a module it depends on.
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
					    public init(detail: any DetailProtocol) {
					        self.detail = detail
					    }

					    @Instantiated let detail: any DetailProtocol
					}

					public protocol DetailProtocol {}
					""",
					"""
					@Instantiable
					public struct Session: Instantiable {
					    public init() {}
					}
					""",
				],
				additionalDirectorySwiftFileContent: [
					"""
					@Instantiable(fulfillingAdditionalTypes: [DetailProtocol.self])
					public struct Detail: Instantiable, DetailProtocol {
					    public init(session: Session) {
					        self.session = session
					    }

					    @Received let session: Session
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

	// MARK: What a seam's callers see

	/// `Base`, whose module info names no module, declares `Feature.Logger`; `Core` declares `Feature.Screen`, a
	/// seam that receives `logger: Logger`, which the declarations `Core` sees qualify as `Feature.Logger`.
	private static func receivedNestedTypeModules(coreOmitsModuleName: Bool) -> [ModuleFixture] {
		[
			ModuleFixture(
				name: "Base",
				packageName: "Shop",
				swiftFileContent: [
					"""
					public enum Feature {}

					public extension Feature {
					    @Instantiable
					    final class Logger: Instantiable {
					        public init() {}
					    }
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

					public extension Feature {
					    @Instantiable(generateDependencyTree: true)
					    final class Screen: Instantiable {
					        public init(logger: Logger, detail: Detail) {
					            self.logger = logger
					            self.detail = detail
					        }

					        @Received let logger: Logger
					        @Instantiated let detail: Detail
					    }
					}
					""",
					"""
					@Instantiable
					public final class Detail: Instantiable {
					    public init() {}
					}
					""",
				],
				dependencies: ["Base"],
				omitsModuleName: coreOmitsModuleName,
			),
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamReceivesNestedTypeDeclaredInModuleInfoNamingNoModule() async {
		// `Core` computes `Feature.Screen`'s parameter as `logger: Feature.Logger`, qualified by `Base`'s declaration;
		// the modules that call it compute the signature from the modules `Core`'s module info names, which cannot
		// name `Base`, and would spell the parameter `logger: Logger`: the two signatures differ, so `Core`'s run
		// reports it at the seam, naming the declaration the callers cannot see.
		await assertThrowsMultiModuleError(inModule: "Core", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Screen.swift"]):4:5: error: SafeDI cannot generate the dependency tree of `Feature.Screen`: the initializer SafeDI generates for it depends on `Feature.Logger`, which is declared in a module whose SafeDI module info names no module, and the modules that call that initializer, which compute its signature from the modules this module's module info names, cannot see that declaration, so their calls would not match the initializer. Generate that module's module info with `--module-name`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.receivedNestedTypeModules(coreOmitsModuleName: false),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesSeamWithoutCallersViewError_whenSeamsOwnModuleInfoNamesNoModule() async throws {
		// `Core`'s own module info names no module, so every caller builds `Feature.Screen` inline and no caller
		// computes its signature: nothing can disagree with `Core`'s, which is not checked against the callers' view
		// and generates the initializer without an error, whatever `Base`'s module info names.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.receivedNestedTypeModules(coreOmitsModuleName: true),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules.mapValues(\.generatedFiles) == [
			"Base": ["Base.swift": generatedFileHeader],
			"Core": ["Core.swift": generatedFileHeader + Self.importBlock("Base") + "\n\n" + """
			extension Feature.Screen {
			    public convenience init(logger: Feature.Logger) {
			        let detail = Detail()
			        self.init(logger: logger, detail: detail)
			    }
			}

			extension Feature.Screen {
			    public enum __safeDI_Feature_Screen_931B46051C26329C {}
			}
			"""],
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamReceivesNestedTypeDeclaredInAdditionalDirectoryUnderTargetGraph() async {
		// Under the target graph, `Feature.Screen`'s parameter is `logger: Feature.Logger`, qualified by the
		// additional directory's declaration, which the graph attributes to no module; the modules that call the
		// seam compute the signature from the graph's files and would spell it `logger: Logger`.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):2:5: error: SafeDI cannot generate the dependency tree of `Feature.Screen`: the initializer SafeDI generates for it depends on `Feature.Logger`, which is declared in a directory this module's `#SafeDIConfiguration` adds, and the modules that call that initializer cannot see that declaration, so their calls would not match the initializer. Declare `Feature.Logger` in a file of this module, or of a module it depends on.
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
					public extension Feature {
					    @Instantiable(generateDependencyTree: true)
					    final class Screen: Instantiable {
					        public init(logger: Logger, detail: Detail) {
					            self.logger = logger
					            self.detail = detail
					        }

					        @Received let logger: Logger
					        @Instantiated let detail: Detail
					    }
					}
					""",
					"""
					@Instantiable
					public final class Detail: Instantiable {
					    public init() {}
					}
					""",
				],
				additionalDirectorySwiftFileContent: [
					"""
					public enum Feature {}

					public extension Feature {
					    @Instantiable
					    final class Logger: Instantiable {
					        public init() {}
					    }
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
	mutating func generate_throwsError_whenDependentModuleInfoWasWrittenAgainstOtherDeclarationsOfItsDependency() async throws {
		// `Core`'s module info was written by a run that saw `Base` as it was then, in which `Reader` received
		// `token: Token`; `App`'s run reads that module info beside a `Base` in which `Reader` receives
		// `token: String`, and computes `Screen`'s signature from the two: a label collision `Core`'s own run did not
		// have, reported in `App`'s run at the seam, as `Core`'s module info locates it.
		func baseModule(readerReceives type: String) -> ModuleFixture {
			ModuleFixture(
				name: "Base",
				packageName: "Shop",
				swiftFileContent: [
					"""
					@Instantiable
					public struct Reader: Instantiable {
					    public init(token: \(type)) {
					        self.token = token
					    }

					    @Received let token: \(type)
					}
					""",
					"""
					@Instantiable
					public struct Token: Instantiable {
					    public init() {}
					}
					""",
				],
			)
		}
		let coreModule = ModuleFixture(
			name: "Core",
			packageName: "Shop",
			swiftFileContent: [
				"""
				import Base

				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(detail: Detail, reader: Reader) {
				        self.detail = detail
				        self.reader = reader
				    }

				    @Instantiated let detail: Detail
				    @Instantiated let reader: Reader
				}
				""",
				"""
				import Base

				@Instantiable
				public struct Detail: Instantiable {
				    public init(token: Token) {
				        self.token = token
				    }

				    @Received let token: Token
				}
				""",
			],
			dependencies: ["Base"],
		)
		let firstRun = try await executeSafeDIToolMultiModuleTest(
			modules: [baseModule(readerReceives: "Token"), coreModule],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		let core = try #require(firstRun.modules["Core"])
		let coreModuleInfoPath = try #require(core.moduleInfoOutputPath)

		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(core.fixtures["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `token` as `token: Token` on `Detail` and `token: String` on `Reader`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.
			\(core.fixtures["Detail.swift"]):9:5: note: `Detail` receives `token: Token` here.
			\(fixtures["Base"]!["Reader.swift"]):7:5: note: `Reader` receives `token: String` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					baseModule(readerReceives: "String"),
					coreModule,
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [
							"""
							import Base
							import Core

							@Instantiable(isRoot: true)
							public struct Root: Instantiable {
							    public init(token: Token, screen: Screen) {
							        self.token = token
							        self.screen = screen
							    }

							    @Instantiated let token: Token
							    @Instantiated let screen: Screen
							}
							""",
						],
						dependencies: ["Core", "Base"],
					),
				],
				integration: .moduleInfo,
				moduleInfoOverrides: ["Core": coreModuleInfoPath],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsErasedInstantiatorMismatchWithOtherSeamsErrors_whenSeamsTreeDeclaresOne() async {
		// `Screen`'s tree builds `Detail`, which forwards `id`, through an `ErasedInstantiator<(), AnyDetail>`: the
		// mismatch is found when the seam's tree is built for its signature, and is collected with `Panel`'s label
		// collision, in source order, rather than thrown alone.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Panel.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Panel`: its tree receives `token` as `token: Token` on `Cache` and `token: String` on `Tracker`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Rename one of the properties, or @Instantiated one of them inside the tree.
			\(fixtures["Cache.swift"]):7:5: note: `Cache` receives `token: Token` here.
			\(fixtures["Tracker.swift"]):7:5: note: `Tracker` receives `token: String` here.
			\(fixtures["Screen.swift"]):7:5: error: The first generic argument of `detailBuilder: ErasedInstantiator<(), AnyDetail>` on `Screen` must be the @Forwarded properties of `Detail`, which it builds. Declare it as `ErasedInstantiator<String, AnyDetail>`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Panel: Instantiable {
					    public init(cache: Cache, tracker: Tracker) {
					        self.cache = cache
					        self.tracker = tracker
					    }

					    @Instantiated let cache: Cache
					    @Instantiated let tracker: Tracker
					}
					""",
					"""
					@Instantiable
					public struct Cache: Instantiable {
					    public init(token: Token) {
					        self.token = token
					    }

					    @Received let token: Token
					}
					""",
					"""
					@Instantiable
					public struct Tracker: Instantiable {
					    public init(token: String) {
					        self.token = token
					    }

					    @Received let token: String
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(detailBuilder: ErasedInstantiator<(), AnyDetail>) {
					        self.detailBuilder = detailBuilder
					    }

					    @Instantiated(fulfilledByType: "Detail", erasedToConcreteExistential: true) let detailBuilder: ErasedInstantiator<(), AnyDetail>
					}

					public protocol DetailProtocol {}

					public struct AnyDetail: DetailProtocol {
					    public init(_ detail: some DetailProtocol) {}
					}
					""",
					"""
					@Instantiable
					public struct Detail: Instantiable, DetailProtocol {
					    public init(id: String) {
					        self.id = id
					    }

					    @Forwarded let id: String
					}
					""",
					"""
					@Instantiable
					public struct Token: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	/// `Screen`, a public seam, instantiates `Hidden.Detail`, which receives `token` only if available and is nested
	/// in an enum declared at `enclosingAccess`, which caps its initializer there.
	private static func receiverNestedInNarrowTypeFixture(enclosingAccess: String) -> [String] {
		[
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(token: Token, screen: Screen) {
			        self.token = token
			        self.screen = screen
			    }

			    @Instantiated let token: Token
			    @Instantiated let screen: Screen
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public struct Screen: Instantiable {
			    public init(detail: Hidden.Detail) {
			        self.detail = detail
			    }

			    @Instantiated let detail: Hidden.Detail
			}
			""",
			"""
			\(enclosingAccess) enum Hidden {
			    @Instantiable
			    public struct Detail: Instantiable {
			        public init(token: Token?) {
			            self.token = token
			        }

			        @Received(onlyIfAvailable: true) let token: Token?
			    }
			}
			""",
			"""
			@Instantiable
			public struct Token: Instantiable {
			    public init() {}
			}
			""",
		]
	}

	@Test(arguments: ["fileprivate", "private"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamsTreeConstructsTypeNestedInFileprivateOrPrivateType(enclosingAccess: String) async {
		// The seam's generated initializer is in another file of the module, which cannot see into a `fileprivate` or
		// `private` type, so the construction of `Hidden.Detail` is reported as every construction generated code
		// cannot compile is, with the tier `token` would have been taken in never generated. The macro leaves the two
		// levels of an enclosing type to the tool.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):1:1: error: `Hidden`, which encloses `Hidden.Detail`, is `\(enclosingAccess)`, so the code SafeDI generates in another file of this module cannot construct `Hidden.Detail`. Make `Hidden` `internal` to fix.
			\(fixtures["Detail.swift"]):1:1-1:\(enclosingAccess.count + 1): fixit: internal
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.receiverNestedInNarrowTypeFixture(enclosingAccess: enclosingAccess),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: ["fileprivate", "private"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamIsNestedInFileprivateOrPrivateType(enclosingAccess: String) async {
		// The seam's generated initializer is in another file of the module, which cannot see the seam itself, so the
		// seam is reported as a root nested in such a type is, once, at the root's reference to it.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: `Hidden`, which encloses `Hidden.Screen`, is `\(enclosingAccess)`, so the code SafeDI generates in another file of this module cannot construct `Hidden.Screen`. Make `Hidden` `internal` to fix.
			\(fixtures["Screen.swift"]):1:1-1:\(enclosingAccess.count + 1): fixit: internal
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(screen: Hidden.Screen) {
					        self.screen = screen
					    }

					    @Instantiated let screen: Hidden.Screen
					}
					""",
					"""
					\(enclosingAccess) enum Hidden {
					    @Instantiable(generateDependencyTree: true)
					    public struct Screen: Instantiable {
					        public init(token: Token) {
					            self.token = token
					        }

					        @Instantiated let token: Token
					    }
					}
					""",
					"""
					@Instantiable
					public struct Token: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtDeclaration_whenSeamsTreeConstructsInternalTypeOfAnotherModule(integration: MultiModuleIntegration) async {
		// The seam's generated initializer compiles in `Feature`, so each construction in the seam's tree is checked
		// against `Feature`, as a root's tree is: `Core`'s internal `Service` cannot be constructed there.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let servicePath = Self.declarationPath(of: "Service.swift", in: "Core", fixtures: fixtures, under: integration)
			return """
			\(servicePath):2:1: error: `Service` is `internal`, so module `Feature`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` to fix.
			\(servicePath):2:1-2:9: fixit: package
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Core",
						packageName: "Shop",
						swiftFileContent: [
							"""
							@Instantiable
							internal final class Service: Instantiable {
							    package init() {}
							}
							""",
						],
					),
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContent: [
							"""
							import Core

							@Instantiable(generateDependencyTree: true)
							struct Screen: Instantiable {
							    init(service: Service) {
							        self.service = service
							    }

							    @Instantiated let service: Service
							}
							""",
						],
						dependencies: ["Core"],
					),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamsTreeCallsInstantiateMethodOfPrivateExtension() async {
		// An unspelled `instantiate(…)` in a `private` extension is `fileprivate`, which the code SafeDI generates in
		// another file cannot call: the check of every construction reports the extension. `Token`'s own declaration
		// proves it `public`, so `Screen`'s public tier takes it. The macro rejects such a method, so this is the tool's
		// check alone, with no generated code to compile.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):6:1: error: The extension that declares `Detail.instantiate()` is `fileprivate`, so the code SafeDI generates in another file of this module cannot call `Detail.instantiate()`. Make the extension `internal` to fix.
			\(fixtures["Detail.swift"]):6:1-6:8: fixit: internal
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
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
					public struct Detail {
					    public init(token: Token) {}
					}

					@Instantiable
					private extension Detail {
					    static func instantiate(token: Token) -> Detail {
					        Detail(token: token)
					    }
					}
					""",
					"""
					@Instantiable
					public struct Token: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				skipCompileVerification: true,
			)
		}
	}

	// MARK: Receives hidden inside the seam's tree

	/// `Screen`, a seam, instantiates `Panel`, which declares `token: Token` and instantiates `Reader`, which receives
	/// `token` as a `Secret` – only if available, or required when `readerRequiresToken` – so `Panel`'s declaration
	/// hides the label for `Reader`. `Root` holds `token: Secret` when `rootProvidesSecret`.
	private static func hiddenReceiveFixture(seam: Bool, readerRequiresToken: Bool, rootProvidesSecret: Bool) -> [String] {
		[
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(\(rootProvidesSecret ? "token: Secret, " : "")screen: Screen) {
			\(rootProvidesSecret ? "        self.token = token\n" : "")        self.screen = screen
			    }

			\(rootProvidesSecret ? "    @Instantiated let token: Secret\n" : "")    @Instantiated let screen: Screen
			}
			""",
			"""
			@Instantiable\(seam ? "(generateDependencyTree: true)" : "")
			public struct Screen: Instantiable {
			    public init(panel: Panel) {
			        self.panel = panel
			    }

			    @Instantiated let panel: Panel
			}
			""",
			"""
			@Instantiable
			public struct Panel: Instantiable {
			    public init(token: Token, reader: Reader) {
			        self.token = token
			        self.reader = reader
			    }

			    @Instantiated let token: Token
			    @Instantiated let reader: Reader
			}
			""",
			"""
			@Instantiable
			public struct Reader: Instantiable {
			    public init(token: Secret\(readerRequiresToken ? "" : "?")) {
			        self.token = token
			    }

			    @Received\(readerRequiresToken ? "" : "(onlyIfAvailable: true)") let token: Secret\(readerRequiresToken ? "" : "?")
			}
			""",
			"""
			@Instantiable
			public struct Token: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public struct Secret: Instantiable {
			    public init() {}
			}
			""",
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSeamsHiddenError_whenOnlyIfAvailableReceiveIsHiddenInsideSeamAndNoCallerProvidesIt() async throws {
		// `Panel`, between the seam and `Reader`, declares `token: Token`, which hides the label for `Reader`'s
		// `token: Secret?`: the generated initializer passes each dependency by label and is generated before any
		// caller is known, so the seam reports the receive hidden from its own chain, whatever a caller holds.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `token: Secret?` is hidden in chain: Screen -> Panel -> Reader. `Panel` declares `token: Token` with the same label, so the types below `Panel` receive `token: Token` instead. Give `token: Token` on `Panel` a different label to fix.
			\(fixtures["Panel.swift"]):8:5: note: `token: Token` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.hiddenReceiveFixture(seam: true, readerRequiresToken: false, rootProvidesSecret: false),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}

		// The same graph built inline, for comparison: no caller provides `token: Secret`, so `Reader` is passed `nil`.
		let inlineOutput = try await executeSafeDIToolTest(
			swiftFileContent: Self.hiddenReceiveFixture(seam: false, readerRequiresToken: false, rootProvidesSecret: false),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(inlineOutput.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_panel() -> Panel {
		                let token = Token()
		                let reader = Reader(token: nil)
		                return Panel(token: token, reader: reader)
		            }
		            let panel: Panel = __safeDI_panel()
		            return Screen(panel: panel)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(screen: screen)
		    }
		}
		""")
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenCallerProvidesPropertyHiddenInsideSeam(seam: Bool) async {
		// `Root` holds `token: Secret`, which `Panel`'s `token: Token` hides for `Reader`: the root's chain reports it,
		// with or without the seam, and with the seam the seam's own chain reports it too.
		await assertThrowsError(diagnostics: { fixtures in
			seam
				? """
				\(fixtures["Reader.swift"]):7:5: error: @Received property `token: Secret?` is hidden in chain: Screen -> Panel -> Reader. `Panel` declares `token: Token` with the same label, so the types below `Panel` receive `token: Token` instead. Give `token: Token` on `Panel` a different label to fix.
				\(fixtures["Panel.swift"]):8:5: note: `token: Token` is declared here
				"""
				: """
				\(fixtures["Reader.swift"]):7:5: error: @Received property `token: Secret?` is hidden in chain: Root -> Screen -> Panel -> Reader. `Panel` declares `token: Token` with the same label, so the types below `Panel` receive `token: Token` instead. Give `token: Token` on `Panel` a different label to fix.
				\(fixtures["Panel.swift"]):8:5: note: `token: Token` is declared here
				"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.hiddenReceiveFixture(seam: seam, readerRequiresToken: false, rootProvidesSecret: true),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnfulfillableErrorFromRootChainAlone_whenRequiredReceiveIsHiddenInsideSeamAndNoCallerProvidesIt(seam: Bool) async {
		// A required `token: Secret` that `Panel`'s declaration hides, with nothing above providing it: validation
		// reports unfulfillable receives before hidden ones, so the root's chain reports it unfulfillable, with its
		// fix-it, exactly as inline, and the seam's own chain, which reports it hidden, is not reached.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `token: Secret` is not @Instantiated or @Forwarded in chain: Root -> Screen -> Panel -> Reader. Did you mean `token: Token`?
			\(fixtures["Reader.swift"]):7:26-7:32: fixit: Token
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.hiddenReceiveFixture(seam: seam, readerRequiresToken: true, rootProvidesSecret: false),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSeamsHiddenError_whenRequiredReceiveIsHiddenInsideSeamInModuleWithNoRoot() async {
		// With no root, the seam's own chain is the only one, and it reports the receive hidden, with no fix-it.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `token: Secret` is hidden in chain: Screen -> Panel -> Reader. `Panel` declares `token: Token` with the same label, so the types below `Panel` receive `token: Token` instead. Give `token: Token` on `Panel` a different label to fix.
			\(fixtures["Panel.swift"]):8:5: note: `token: Token` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Array(Self.hiddenReceiveFixture(seam: true, readerRequiresToken: true, rootProvidesSecret: false).dropFirst()),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [
		("LazilyInstantiated", "SendableLazilyInstantiated", " A `SendableLazilyInstantiated` requires its instance type, `Cache`, to be `Sendable`."),
		("Instantiator", "SendableInstantiator", " `SendableInstantiator<Cache>` builds `Cache` in a `@Sendable` function, so what the tree of `Cache` receives from outside that function must be `Sendable` too."),
	] as [(String, String, String)])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSendableBuilderInsideSeamReadsOptionalWrapperParameterInlineWouldPassNil(wrapper: String, sendableWrapper: String, trailer: String) async throws {
		// `Detail`, built by a `@Sendable` builder inside the seam, receives `cache` as an optional non-`Sendable`
		// wrapper only if available, and nothing provides it: inline, `Detail` is passed `nil` and nothing is
		// captured; the seam's generated initializer declares the parameter outside every builder function, whatever
		// a caller passes, so the builder would capture it: rejected at the seam's tree (a documented divergence),
		// with the `Sendable` wrapper of the same kind as the remedy.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):7:5: error: @Received property `cache: \(wrapper)<Cache>?` cannot be received inside a `@Sendable` function in chain: Screen -> Detail. SafeDI builds `detailBuilder: SendableInstantiator<Detail>` on `Screen` in a `@Sendable` function, which cannot capture `cache: \(wrapper)<Cache>?`, which the tree of `Screen` receives from outside it, because `\(wrapper)<Cache>` is not `Sendable`. Declare `cache` as `\(sendableWrapper)<Cache>` where it is declared and where it is received as `\(wrapper)<Cache>` to fix.\(trailer)
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.sendableBuilderReadingOptionalWrapperFixture(seam: true, wrapper: wrapper),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}

		// The same graph built inline, for comparison: `Detail` is passed `nil`.
		let inlineOutput = try await executeSafeDIToolTest(
			swiftFileContent: Self.sendableBuilderReadingOptionalWrapperFixture(seam: false, wrapper: wrapper),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(inlineOutput.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_screen() -> Screen {
		            @Sendable func __safeDI_detailBuilder() -> Detail {
		                Detail(cache: nil)
		            }
		            let detailBuilder = SendableInstantiator<Detail>(__safeDI_detailBuilder)
		            return Screen(detailBuilder: detailBuilder)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(screen: screen)
		    }
		}
		""")
	}

	/// `Root` instantiating `screen` alone; `Screen` building `Detail` through a `SendableInstantiator`, and `Detail`
	/// receiving `cache` as the optional `wrapper` only if available, which nothing provides.
	private static func sendableBuilderReadingOptionalWrapperFixture(seam: Bool, wrapper: String) -> [String] {
		[
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(screen: Screen) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Screen
			}
			""",
			"""
			@Instantiable\(seam ? "(generateDependencyTree: true)" : "")
			public struct Screen: Instantiable {
			    public init(detailBuilder: SendableInstantiator<Detail>) {
			        self.detailBuilder = detailBuilder
			    }

			    @Instantiated let detailBuilder: SendableInstantiator<Detail>
			}
			""",
			"""
			@Instantiable
			public struct Detail: Instantiable, @unchecked Sendable {
			    public init(cache: \(wrapper)<Cache>?) {
			        self.cache = cache
			    }

			    @Received(onlyIfAvailable: true) let cache: \(wrapper)<Cache>?
			}
			""",
			"""
			@Instantiable
			public struct Cache: Instantiable, Sendable {
			    public init() {}
			}
			""",
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSeamsHiddenError_whenForwardedPropertyInsideSeamHidesReceiveBeneathIt() async {
		// `Feature`, built by a builder inside the seam, forwards `token: Token`, which hides the label for `Reader`'s
		// `token: Secret?` beneath it: the seam reports the receive hidden from its own chain, where inline passes `nil`.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `token: Secret?` is hidden in chain: Screen -> Instantiator<Feature> -> Reader. `Feature` declares `token: Token` with the same label, so the types below `Feature` receive `token: Token` instead. Give `token: Token` on `Feature` a different label to fix.
			\(fixtures["Feature.swift"]):8:5: note: `token: Token` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(screen: Screen) {
					        self.screen = screen
					    }

					    @Instantiated let screen: Screen
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(featureBuilder: Instantiator<Feature>) {
					        self.featureBuilder = featureBuilder
					    }

					    @Instantiated let featureBuilder: Instantiator<Feature>
					}
					""",
					"""
					@Instantiable
					public struct Feature: Instantiable {
					    public init(token: Token, reader: Reader) {
					        self.token = token
					        self.reader = reader
					    }

					    @Forwarded let token: Token
					    @Instantiated let reader: Reader
					}
					""",
					"""
					@Instantiable
					public struct Reader: Instantiable {
					    public init(token: Secret?) {
					        self.token = token
					    }

					    @Received(onlyIfAvailable: true) let token: Secret?
					}
					""",
					"""
					@Instantiable
					public struct Token: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Secret: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	/// `Screen`, a seam, instantiates `Left`, which declares `token: Token` and instantiates `Reader`, and `Right`,
	/// which instantiates `Reader` and declares nothing; `Reader` receives `token: Secret?` only if available. `Root`
	/// holds `token` of type `rootHolds` when it is not `nil`.
	private static func receiveHiddenOnOnePathFixture(seam: Bool, rootHolds: String?) -> [String] {
		[
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(\(rootHolds.map { "token: \($0), " } ?? "")screen: Screen) {
			\(rootHolds == nil ? "" : "        self.token = token\n")        self.screen = screen
			    }

			\(rootHolds.map { "    @Instantiated let token: \($0)\n" } ?? "")    @Instantiated let screen: Screen
			}
			""",
			"""
			@Instantiable\(seam ? "(generateDependencyTree: true)" : "")
			public struct Screen: Instantiable {
			    public init(left: Left, right: Right) {
			        self.left = left
			        self.right = right
			    }

			    @Instantiated let left: Left
			    @Instantiated let right: Right
			}
			""",
			"""
			@Instantiable
			public struct Left: Instantiable {
			    public init(token: Token, reader: Reader) {
			        self.token = token
			        self.reader = reader
			    }

			    @Instantiated let token: Token
			    @Instantiated let reader: Reader
			}
			""",
			"""
			@Instantiable
			public struct Right: Instantiable {
			    public init(reader: Reader) {
			        self.reader = reader
			    }

			    @Instantiated let reader: Reader
			}
			""",
			"""
			@Instantiable
			public struct Reader: Instantiable {
			    public init(token: Secret?) {
			        self.token = token
			    }

			    @Received(onlyIfAvailable: true) let token: Secret?
			}
			""",
			"""
			@Instantiable
			public struct Token: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public struct Secret: Instantiable {
			    public init() {}
			}
			""",
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSeamsHiddenError_whenReceiveIsHiddenOnOnePathAndReceivedOnAnother() async {
		// `Left` declares `token: Token`, which hides `Reader`'s `token: Secret?` beneath it, while `Right` builds `Reader` too:
		// the receive is hidden on one path, which the seam reports from its own chain, on every path, where inline passes
		// `nil` beneath `Left` and what a caller provides beneath `Right`.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `token: Secret?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `token: Token` with the same label, so the types below `Left` receive `token: Token` instead. Give `token: Token` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `token: Token` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.receiveHiddenOnOnePathFixture(seam: true, rootHolds: nil),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases, [nil, "Secret", "LazilyInstantiated<Secret>"] as [String?])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSeamsHiddenErrorInSeamsModule_whenReceiveIsHiddenOnOnePathWhateverAnotherModuleHolds(integration: MultiModuleIntegration, appHolds: String?) async {
		// The seam's module rejects the hidden receive from the seam's own chain whatever its callers hold, so no
		// caller in another module calls an initializer that would drop the value it holds.
		func isCallerFile(_ content: String) -> Bool {
			content.contains("public struct Root: Instantiable")
		}
		let fixture = Self.receiveHiddenOnOnePathFixture(seam: true, rootHolds: appHolds)
		await assertThrowsMultiModuleError(inModule: "Core", diagnostics: { fixtures in
			// A diagnostic cites the path the file was parsed under: the CSV's under `.moduleInfo`, the compiler's
			// spelling, normalized, under the plugin.
			let path = { (fileName: String) in
				switch integration {
				case .moduleInfo:
					fixtures["Core"]![fileName]
				case .swiftPackagePlugin:
					NormalizedFilePath(fixtures["Core"]!.compilerPath(of: fileName)).path
				}
			}
			return """
			\(path("Reader.swift")):7:5: error: @Received property `token: Secret?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `token: Token` with the same label, so the types below `Left` receive `token: Token` instead. Give `token: Token` on `Left` a different label to fix.
			\(path("Left.swift")):8:5: note: `token: Token` is declared here
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: fixture.filter { !isCallerFile($0) }),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: fixture.filter(isCallerFile).map { "import Core\n\n" + $0 }, dependencies: ["Core"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSeamsHiddenError_whenHidingDeclarationIsInAdditionalDirectoryUnderTargetGraph() async {
		// The hiding declaration is in a directory the configuration adds, which callers under the target graph cannot
		// see: the seam reports the hidden receive from its own chain whatever its callers see, so no caller is left to
		// pass a value the seam's tree would drop.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `token: Secret?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `token: Token` with the same label, so the types below `Left` receive `token: Token` instead. Give `token: Token` on `Left` a different label to fix.
			\(fixtures["AdditionalDirectory/Left.swift"]):8:5: note: `token: Token` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.receiveHiddenOnOnePathFixture(seam: true, rootHolds: nil).filter { !$0.contains("public struct Left: Instantiable") && !$0.contains("public struct Root: Instantiable") } + [
					"""
					#SafeDIConfiguration(
					    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
					)
					""",
				],
				additionalDirectorySwiftFileContent: Self.receiveHiddenOnOnePathFixture(seam: true, rootHolds: nil).filter { $0.contains("public struct Left: Instantiable") },
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				pluginTargetGraph: { inputSwiftFilePaths in
					PluginTargetGraph(
						target: PluginTargetGraph.Target(moduleName: "Core", packageID: "shop", sourceFilePaths: inputSwiftFilePaths, dependencyModuleNames: []),
						dependencyTargets: [],
					)
				},
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToBothReceivers_whenReceiveIsHiddenOnOnePathInlineAndNoCallerProvidesIt() async throws {
		// The graph of the previous test built inline: nothing above provides `token: Secret?`, so both `Reader`s are
		// passed `nil`, and the hiding `token: Token` is reported only where a caller provides the property.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.receiveHiddenOnOnePathFixture(seam: false, rootHolds: nil),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_left() -> Left {
		                let token = Token()
		                let reader = Reader(token: nil)
		                return Left(token: token, reader: reader)
		            }
		            let left: Left = __safeDI_left()
		            func __safeDI_right() -> Right {
		                let reader = Reader(token: nil)
		                return Right(reader: reader)
		            }
		            let right: Right = __safeDI_right()
		            return Screen(left: left, right: right)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(screen: screen)
		    }
		}
		""")
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenCallerProvidesPropertyHiddenOnOnePathInsideSeam(seam: Bool) async {
		// With `Root` holding `token: Secret`, the receive under `Left` is hidden with a provider above: the root's
		// chain reports it, with or without the seam, and with the seam the seam's own chain reports it too.
		await assertThrowsError(diagnostics: { fixtures in
			seam
				? """
				\(fixtures["Reader.swift"]):7:5: error: @Received property `token: Secret?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `token: Token` with the same label, so the types below `Left` receive `token: Token` instead. Give `token: Token` on `Left` a different label to fix.
				\(fixtures["Left.swift"]):8:5: note: `token: Token` is declared here
				"""
				: """
				\(fixtures["Reader.swift"]):7:5: error: @Received property `token: Secret?` is hidden in chain: Root -> Screen -> Left -> Reader. `Left` declares `token: Token` with the same label, so the types below `Left` receive `token: Token` instead. Give `token: Token` on `Left` a different label to fix.
				\(fixtures["Left.swift"]):8:5: note: `token: Token` is declared here
				"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.receiveHiddenOnOnePathFixture(seam: seam, rootHolds: "Secret"),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Aliases of provided properties and parameters hidden beneath a declaration

	/// How `currentUser`, an alias of `user`, is declared in `Screen`'s tree.
	enum AliasOfProvidedProperty {
		/// `Detail`, a child of the seam, instantiates `user: User` and aliases it.
		case onChild
		/// The seam itself instantiates `user: User` and aliases it; `Detail` receives the alias.
		case onSeamRoot
	}

	/// What `Summary`, a second child of the seam, receives under the label `user`, and what `Root` holds for it.
	enum LabelNeighbor {
		case none
		/// `Summary` requires `user: Name`; `Root` instantiates `user: Name` unless the alias is the seam's own.
		case otherType
		/// `Summary` requires `user: Instantiator<User>`; `Root` instantiates it unless the alias is the seam's own.
		case instantiator
		/// `Summary` receives `user: LazilyInstantiated<User>?` only if available; `Root` instantiates the wrapper
		/// unless the alias is the seam's own, whose declaration hides the label beneath it.
		case optionalWrapper
	}

	private static func aliasOfProvidedPropertyFixture(alias: AliasOfProvidedProperty, neighbor: LabelNeighbor, seam: Bool) -> [String] {
		let rootHolding: String? = switch (alias, neighbor) {
		case (_, .none), (.onSeamRoot, _):
			nil
		case (.onChild, .otherType):
			"user: Name"
		case (.onChild, .instantiator):
			"user: Instantiator<User>"
		case (.onChild, .optionalWrapper):
			"user: LazilyInstantiated<User>"
		}
		var files = [
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(\(rootHolding.map { "\($0), " } ?? "")screen: Screen) {
			\(rootHolding == nil ? "" : "        self.user = user\n")        self.screen = screen
			    }

			\(rootHolding.map { "    @Instantiated let \($0)\n" } ?? "")    @Instantiated let screen: Screen
			}
			""",
		]
		let summaryParameter = neighbor == .none ? "" : ", summary: Summary"
		let summaryAssignment = neighbor == .none ? "" : "\n        self.summary = summary"
		let summaryDeclaration = neighbor == .none ? "" : "\n    @Instantiated let summary: Summary"
		switch alias {
		case .onChild:
			files.append("""
			@Instantiable\(seam ? "(generateDependencyTree: true)" : "")
			public struct Screen: Instantiable {
			    public init(detail: Detail\(summaryParameter)) {
			        self.detail = detail\(summaryAssignment)
			    }

			    @Instantiated let detail: Detail\(summaryDeclaration)
			}
			""")
		case .onSeamRoot:
			files.append("""
			@Instantiable\(seam ? "(generateDependencyTree: true)" : "")
			public struct Screen: Instantiable {
			    public init(user: User, currentUser: User, detail: Detail\(summaryParameter)) {
			        self.user = user
			        self.currentUser = currentUser
			        self.detail = detail\(summaryAssignment)
			    }

			    @Instantiated let user: User
			    @Received(fulfilledByDependencyNamed: "user", ofType: User.self) let currentUser: User
			    @Instantiated let detail: Detail\(summaryDeclaration)
			}
			""")
		}
		switch alias {
		case .onChild:
			files.append("""
			@Instantiable
			public struct Detail: Instantiable {
			    public init(user: User, currentUser: User) {
			        self.user = user
			        self.currentUser = currentUser
			    }

			    @Instantiated let user: User
			    @Received(fulfilledByDependencyNamed: "user", ofType: User.self) let currentUser: User
			}
			""")
		case .onSeamRoot:
			files.append("""
			@Instantiable
			public struct Detail: Instantiable {
			    public init(currentUser: User) {
			        self.currentUser = currentUser
			    }

			    @Received let currentUser: User
			}
			""")
		}
		switch neighbor {
		case .none:
			break
		case .otherType:
			files.append("""
			@Instantiable
			public struct Summary: Instantiable {
			    public init(user: Name) {
			        self.user = user
			    }

			    @Received let user: Name
			}
			""")
			files.append("""
			@Instantiable
			public struct Name: Instantiable {
			    public init() {}
			}
			""")
		case .instantiator:
			files.append("""
			@Instantiable
			public struct Summary: Instantiable {
			    public init(user: Instantiator<User>) {
			        self.user = user
			    }

			    @Received let user: Instantiator<User>
			}
			""")
		case .optionalWrapper:
			files.append("""
			@Instantiable
			public struct Summary: Instantiable {
			    public init(user: LazilyInstantiated<User>?) {
			        self.user = user
			    }

			    @Received(onlyIfAvailable: true) let user: LazilyInstantiated<User>?
			}
			""")
		}
		files.append("""
		@Instantiable
		public struct User: Instantiable {
		    public init() {}
		}
		""")
		return files
	}

	/// The alias binding `Detail` builds for `alias`, indented by `indent`, with `<DETAIL-PATH>` for its file.
	private static func aliasOfProvidedPropertyBindings(alias: AliasOfProvidedProperty, indent: String) -> String {
		switch alias {
		case .onChild:
			"""
			\(indent)let user = User()
			\(indent)#sourceLocation(file: "<DETAIL-PATH>", line: 9)
			\(indent)let currentUser: User = user
			\(indent)#sourceLocation()
			\(indent)return Detail(user: user, currentUser: currentUser)
			"""
		case .onSeamRoot:
			""
		}
	}

	struct AliasOfProvidedPropertyCell: Sendable, CustomTestStringConvertible {
		enum Expectation: Sendable {
			/// The seam's generated file, the root's, and the root's with the tree built inline, with `<HASH>`,
			/// `<DETAIL-PATH>` and `<SCREEN-PATH>` to fill in.
			case generates(seam: String, root: String, inlineRoot: String)
			/// The diagnostics with the seam and without it.
			case throwsError(seam: @Sendable (FixturePaths) -> String, inline: @Sendable (FixturePaths) -> String)
			/// The diagnostics with the seam, and the root's generated file with the tree built inline, with
			/// `<SCREEN-PATH>` to fill in.
			case throwsErrorAtSeam(seam: @Sendable (FixturePaths) -> String, inlineRoot: String)
		}

		let alias: AliasOfProvidedProperty
		let neighbor: LabelNeighbor
		let expectation: Expectation

		var testDescription: String {
			"\(alias), \(neighbor)"
		}

		/// Whether the graph generates with the seam.
		var generates: Bool {
			switch expectation {
			case .generates:
				true
			case .throwsError, .throwsErrorAtSeam:
				false
			}
		}
	}

	static let aliasOfProvidedPropertyCells: [AliasOfProvidedPropertyCell] = {
		func childCell(_ alias: AliasOfProvidedProperty, _ neighbor: LabelNeighbor, parameter: String, hash: String, rootBinding: String, rootCall: String, rootInitializer: String) -> AliasOfProvidedPropertyCell {
			let summary = neighbor == .none ? "" : "\n        let summary = Summary(user: user)"
			let initializerCall = neighbor == .none ? "self.init(detail: detail)" : "self.init(detail: detail, summary: summary)"
			let inlineSummary = neighbor == .none ? "" : "\n            let summary = Summary(user: user)"
			let inlineCall = neighbor == .none ? "return Screen(detail: detail)" : "return Screen(detail: detail, summary: summary)"
			return .init(alias: alias, neighbor: neighbor, expectation: .generates(
				seam: """
				extension Screen {
				    public init(\(parameter)) {
				        func __safeDI_detail() -> Detail {
				\(Self.aliasOfProvidedPropertyBindings(alias: alias, indent: "            "))
				        }
				        let detail: Detail = __safeDI_detail()\(summary)
				        \(initializerCall)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_\(hash) {}
				}
				""",
				root: """
				extension Root {
				    public init() {\(rootBinding)
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_\(hash).self
				            return \(rootCall)
				        }
				        let screen: Screen = __safeDI_screen()
				        \(rootInitializer)
				    }
				}
				""",
				inlineRoot: """
				extension Root {
				    public init() {\(rootBinding)
				        func __safeDI_screen() -> Screen {
				            func __safeDI_detail() -> Detail {
				\(Self.aliasOfProvidedPropertyBindings(alias: alias, indent: "                "))
				            }
				            let detail: Detail = __safeDI_detail()\(inlineSummary)
				            \(inlineCall)
				        }
				        let screen: Screen = __safeDI_screen()
				        \(rootInitializer)
				    }
				}
				""",
			))
		}
		let noParameterHash = "CBF29CE484222325"
		let nameBinding = "\n        let user = Name()"
		let instantiatorBinding = """

		        func __safeDI_user() -> User {
		            User()
		        }
		        let user = Instantiator<User>(__safeDI_user)
		"""
		let wrapperBinding = """

		        func __safeDI_user() -> User {
		            User()
		        }
		        let user = LazilyInstantiated<User>(__safeDI_user)
		"""
		var cells = [
			childCell(.onChild, .none, parameter: "", hash: noParameterHash, rootBinding: "", rootCall: "Screen()", rootInitializer: "self.init(screen: screen)"),
			childCell(.onChild, .otherType, parameter: "user: Name", hash: "D6A7623E0B4490E2", rootBinding: nameBinding, rootCall: "Screen(user: user)", rootInitializer: "self.init(user: user, screen: screen)"),
			childCell(.onChild, .instantiator, parameter: "user: Instantiator<User>", hash: "0C022EBEABB7BCBE", rootBinding: instantiatorBinding, rootCall: "Screen(user: user)", rootInitializer: "self.init(user: user, screen: screen)"),
			childCell(.onChild, .optionalWrapper, parameter: "user: LazilyInstantiated<User>?", hash: "71C706F9FE9BEAFE", rootBinding: wrapperBinding, rootCall: "Screen(user: user)", rootInitializer: "self.init(user: user, screen: screen)"),
		]
		let seamRootCell = AliasOfProvidedPropertyCell(alias: .onSeamRoot, neighbor: .none, expectation: .generates(
			seam: """
			extension Screen {
			    public init() {
			        let user = User()
			        #sourceLocation(file: "<SCREEN-PATH>", line: 10)
			        let currentUser: User = user
			        #sourceLocation()
			        let detail = Detail(currentUser: currentUser)
			        self.init(user: user, currentUser: currentUser, detail: detail)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_\(noParameterHash) {}
			}
			""",
			root: """
			extension Root {
			    public init() {
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_\(noParameterHash).self
			            return Screen()
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen)
			    }
			}
			""",
			inlineRoot: """
			extension Root {
			    public init() {
			        func __safeDI_screen() -> Screen {
			            let user = User()
			            #sourceLocation(file: "<SCREEN-PATH>", line: 10)
			            let currentUser: User = user
			            #sourceLocation()
			            let detail = Detail(currentUser: currentUser)
			            return Screen(user: user, currentUser: currentUser, detail: detail)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen)
			    }
			}
			""",
		))
		/// The seam's own `user: User` hides the label beneath it from `Summary`, which requires another type that
		/// nothing above provides: the root's chain reports the receive unfulfillable first, with or without the seam.
		func seamRootErrorCell(_ neighbor: LabelNeighbor, property: String, fixitColumns: String) -> AliasOfProvidedPropertyCell {
			let diagnostics: @Sendable (FixturePaths) -> String = { fixtures in
				"""
				\(fixtures["Summary.swift"]):7:5: error: @Received property `\(property)` is not @Instantiated or @Forwarded in chain: Root -> Screen -> Summary. Did you mean `user: User`?
				\(fixtures["Summary.swift"]):\(fixitColumns): fixit: User
				"""
			}
			return .init(alias: .onSeamRoot, neighbor: neighbor, expectation: .throwsError(seam: diagnostics, inline: diagnostics))
		}
		cells += [
			seamRootCell,
			seamRootErrorCell(.otherType, property: "user: Name", fixitColumns: "7:25-7:29"),
			seamRootErrorCell(.instantiator, property: "user: Instantiator<User>", fixitColumns: "7:25-7:43"),
			// A by-value declaration provides no wrapper form, so `Summary`'s only-if-available receive is hidden: the
			// seam reports it from its own chain, where inline passes `nil`.
			.init(alias: .onSeamRoot, neighbor: .optionalWrapper, expectation: .throwsErrorAtSeam(
				seam: { fixtures in
					"""
					\(fixtures["Summary.swift"]):7:5: error: @Received property `user: LazilyInstantiated<User>?` is hidden in chain: Screen -> Summary. `Screen` declares `user: User` with the same label, so the types below `Screen` receive `user: User` instead. Give `user: User` on `Screen` a different label to fix.
					\(fixtures["Screen.swift"]):10:5: note: `user: User` is declared here
					"""
				},
				inlineRoot: """
				extension Root {
				    public init() {
				        func __safeDI_screen() -> Screen {
				            let user = User()
				            #sourceLocation(file: "<SCREEN-PATH>", line: 11)
				            let currentUser: User = user
				            #sourceLocation()
				            let detail = Detail(currentUser: currentUser)
				            let summary = Summary(user: nil)
				            return Screen(user: user, currentUser: currentUser, detail: detail, summary: summary)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}
				""",
			)),
		]
		return cells
	}()

	@Test(arguments: aliasOfProvidedPropertyCells.filter(\.generates))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesNoParameterForAlias_whenItsScopeProvidesAliasFulfillingProperty(cell: AliasOfProvidedPropertyCell) async throws {
		// An alias of a property the declaring scope itself instantiates or aliases binds to that declaration, so
		// its fulfilling property is no receive that leaves the seam: no parameter, and no collision with another
		// type's receive of the label, which inline accepts.
		try await check(cell)
	}

	@Test(arguments: aliasOfProvidedPropertyCells.filter { !$0.generates })
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorForNeighborReceivingAnotherFormOfLabel_whenSeamDeclaresPropertyItsAliasRenames(cell: AliasOfProvidedPropertyCell) async throws {
		// The seam's own `user: User` is a declaration, which hides the label beneath it from `Summary`'s receive of
		// another form: unfulfillable from the root's chain where nothing above provides that form, with or without
		// the seam, and the seam's hidden-label error where the receive is only if available.
		try await check(cell)
	}

	/// Checks `cell` with the seam and without it.
	private mutating func check(_ cell: AliasOfProvidedPropertyCell) async throws {
		switch cell.expectation {
		case let .generates(seam, root, inlineRoot):
			let output = try await executeSafeDIToolTest(
				swiftFileContent: Self.aliasOfProvidedPropertyFixture(alias: cell.alias, neighbor: cell.neighbor, seam: true),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
			func filled(_ code: String, fixtures: FixturePaths) -> String {
				code.replacingOccurrences(of: "<DETAIL-PATH>", with: fixtures["Detail.swift"])
					.replacingOccurrences(of: "<SCREEN-PATH>", with: fixtures["Screen.swift"])
			}
			#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + filled(seam, fixtures: output.fixtures))
			#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + filled(root, fixtures: output.fixtures))
			let inlineOutput = try await executeSafeDIToolTest(
				swiftFileContent: Self.aliasOfProvidedPropertyFixture(alias: cell.alias, neighbor: cell.neighbor, seam: false),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
			#expect(inlineOutput.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + filled(inlineRoot, fixtures: inlineOutput.fixtures))
		case let .throwsError(seamDiagnostics, inlineDiagnostics):
			for (seam, diagnostics) in [(true, seamDiagnostics), (false, inlineDiagnostics)] {
				await assertThrowsError(diagnostics: diagnostics) {
					try await executeSafeDIToolTest(
						swiftFileContent: Self.aliasOfProvidedPropertyFixture(alias: cell.alias, neighbor: cell.neighbor, seam: seam),
						buildSwiftOutputDirectory: true,
						filesToDelete: &filesToDelete,
					)
				}
			}
		case let .throwsErrorAtSeam(seamDiagnostics, inlineRoot):
			await assertThrowsError(diagnostics: seamDiagnostics) {
				try await executeSafeDIToolTest(
					swiftFileContent: Self.aliasOfProvidedPropertyFixture(alias: cell.alias, neighbor: cell.neighbor, seam: true),
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
			let inlineOutput = try await executeSafeDIToolTest(
				swiftFileContent: Self.aliasOfProvidedPropertyFixture(alias: cell.alias, neighbor: cell.neighbor, seam: false),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
			#expect(inlineOutput.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + inlineRoot.replacingOccurrences(of: "<SCREEN-PATH>", with: inlineOutput.fixtures["Screen.swift"]))
		}
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnfulfillableError_whenAliasOfOwnPropertyIsBesideHiddenRequiredReceiveOfItsProperty(seam: Bool) async {
		// `Detail` aliases its own `user: User`, which is no receive that leaves the seam, and `Reader`, beneath `Right`,
		// which declares `user: Name`, requires `user: User`, which nothing above provides: the root's chain reports it
		// unfulfillable first, with its fix-it, exactly as inline.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User` is not @Instantiated or @Forwarded in chain: Root -> Screen -> Right -> Reader. Did you mean `user: Name`?
			\(fixtures["Reader.swift"]):7:25-7:29: fixit: Name
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(screen: Screen) {
					        self.screen = screen
					    }

					    @Instantiated let screen: Screen
					}
					""",
					"""
					@Instantiable\(seam ? "(generateDependencyTree: true)" : "")
					public struct Screen: Instantiable {
					    public init(detail: Detail, right: Right) {
					        self.detail = detail
					        self.right = right
					    }

					    @Instantiated let detail: Detail
					    @Instantiated let right: Right
					}
					""",
					"""
					@Instantiable
					public struct Detail: Instantiable {
					    public init(user: User, currentUser: User) {
					        self.user = user
					        self.currentUser = currentUser
					    }

					    @Instantiated let user: User
					    @Received(fulfilledByDependencyNamed: "user", ofType: User.self) let currentUser: User
					}
					""",
					"""
					@Instantiable
					public struct Right: Instantiable {
					    public init(user: Name, reader: Reader) {
					        self.user = user
					        self.reader = reader
					    }

					    @Instantiated let user: Name
					    @Instantiated let reader: Reader
					}
					""",
					"""
					@Instantiable
					public struct Reader: Instantiable {
					    public init(user: User) {
					        self.user = user
					    }

					    @Received let user: User
					}
					""",
					"""
					@Instantiable
					public struct User: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Name: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	/// `Screen`, a seam, takes `token: LazilyInstantiated<Secret>` – as its own `@Received` property, or as a
	/// pass-through `Summary` requires – and instantiates `Left`, which declares `token: Token` and instantiates
	/// `Reader`, which receives `token: Secret?` only if available: hidden beneath `Left`, while the required wrapper
	/// provides the instance everywhere else.
	private static func hiddenInstanceOfRequiredWrapperFixture(wrapperIsOwn: Bool) -> [String] {
		var files = [
			wrapperIsOwn
				? """
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(token: LazilyInstantiated<Secret>, left: Left) {
				        self.token = token
				        self.left = left
				    }

				    @Received let token: LazilyInstantiated<Secret>
				    @Instantiated let left: Left
				}
				"""
				: """
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(left: Left, summary: Summary) {
				        self.left = left
				        self.summary = summary
				    }

				    @Instantiated let left: Left
				    @Instantiated let summary: Summary
				}
				""",
			"""
			@Instantiable
			public struct Left: Instantiable {
			    public init(token: Token, reader: Reader) {
			        self.token = token
			        self.reader = reader
			    }

			    @Instantiated let token: Token
			    @Instantiated let reader: Reader
			}
			""",
			"""
			@Instantiable
			public struct Reader: Instantiable {
			    public init(token: Secret?) {
			        self.token = token
			    }

			    @Received(onlyIfAvailable: true) let token: Secret?
			}
			""",
			"""
			@Instantiable
			public struct Token: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public struct Secret: Instantiable {
			    public init() {}
			}
			""",
		]
		if !wrapperIsOwn {
			files.append("""
			@Instantiable
			public struct Summary: Instantiable {
			    public init(token: LazilyInstantiated<Secret>) {
			        self.token = token
			    }

			    @Received let token: LazilyInstantiated<Secret>
			}
			""")
		}
		return files
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenReceivedPropertyError_whenRequiredWrapperParameterProvidesInstanceBeneathDeclarationOfItsLabel(wrapperIsOwn: Bool) async {
		// A required wrapper parameter provides `token: Secret` as a declaration above the seam would, so a receive of
		// it beneath `Left`, which declares `token: Token`, is hidden: every caller, which must pass the wrapper, gets
		// the same error inline, and no parameter could reach `Reader` by its label.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `token: Secret?` is hidden in chain: Screen -> Left -> Reader. `Left` declares `token: Token` with the same label, so the types below `Left` receive `token: Token` instead. Give `token: Token` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `token: Token` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.hiddenInstanceOfRequiredWrapperFixture(wrapperIsOwn: wrapperIsOwn),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSeamsHiddenError_whenAliasFulfillingPropertyIsHiddenBeneathDeclarationOfItsLabel() async {
		// An alias whose fulfilling property a declaration between the seam and the alias hides is a hidden receive too:
		// the seam reports it from its own chain.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Detail.swift"]):7:5: error: @Received property `token: Secret` is hidden in chain: Screen -> Left -> Detail. `Left` declares `token: Token` with the same label, so the types below `Left` receive `token: Token` instead. Give `token: Token` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `token: Token` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(left: Left, right: Right) {
					        self.left = left
					        self.right = right
					    }

					    @Instantiated let left: Left
					    @Instantiated let right: Right
					}
					""",
					"""
					@Instantiable
					public struct Left: Instantiable {
					    public init(token: Token, detail: Detail) {
					        self.token = token
					        self.detail = detail
					    }

					    @Instantiated let token: Token
					    @Instantiated let detail: Detail
					}
					""",
					"""
					@Instantiable
					public struct Detail: Instantiable {
					    public init(authToken: Secret?) {
					        self.authToken = authToken
					    }

					    @Received(fulfilledByDependencyNamed: "token", ofType: Secret.self, onlyIfAvailable: true) let authToken: Secret?
					}
					""",
					"""
					@Instantiable
					public struct Right: Instantiable {
					    public init(reader: Reader) {
					        self.reader = reader
					    }

					    @Instantiated let reader: Reader
					}
					""",
					"""
					@Instantiable
					public struct Reader: Instantiable {
					    public init(token: Secret?) {
					        self.token = token
					    }

					    @Received(onlyIfAvailable: true) let token: Secret?
					}
					""",
					"""
					@Instantiable
					public struct Token: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Secret: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	/// `Screen`, a seam, forwards `user: User` and instantiates `Summary`, which receives `user` as `receive`; `Root`
	/// builds `Screen` through an `Instantiator<Screen>` and holds nothing of `user`.
	private static func seamForwardingPropertyFixture(seam: Bool, summaryReceive: String, summaryType: String, rootHoldsName: Bool = false) -> [String] {
		[
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(\(rootHoldsName ? "user: Name, " : "")screenBuilder: Instantiator<Screen>) {
			        \(rootHoldsName ? "self.user = user\n        " : "")self.screenBuilder = screenBuilder
			    }

			    \(rootHoldsName ? "@Instantiated let user: Name\n    " : "")@Instantiated let screenBuilder: Instantiator<Screen>
			}
			""",
			"""
			@Instantiable\(seam ? "(generateDependencyTree: true)" : "")
			public struct Screen: Instantiable {
			    public init(user: User, summary: Summary) {
			        self.user = user
			        self.summary = summary
			    }

			    @Forwarded let user: User
			    @Instantiated let summary: Summary
			}
			""",
			"""
			@Instantiable
			public struct Summary: Instantiable {
			    public init(user: \(summaryType)) {
			        self.user = user
			    }

			    \(summaryReceive) let user: \(summaryType)
			}
			""",
			"""
			@Instantiable
			public struct User: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public struct Name: Instantiable {
			    public init() {}
			}
			""",
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesSeamsOwnForwardedProperty_whenTreeReceivesItInSameForm() async throws {
		// The seam's own forwarded `user: User` is a declaration, which provides the receive beneath it of the same form.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.seamForwardingPropertyFixture(seam: true, summaryReceive: "@Received", summaryType: "User"),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(user: User) {
		        let summary = Summary(user: user)
		        self.init(user: user, summary: summary)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_38882A8C29DA6D12 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_screenBuilder(user: User) -> Screen {
		            _ = Screen.__safeDI_Screen_38882A8C29DA6D12.self
		            return Screen(user: user)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(user: $0)
		        }
		        self.init(screenBuilder: screenBuilder)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSeamsHiddenError_whenTreeReceivesSeamsOwnForwardedPropertyInAnotherForm() async throws {
		// The seam's own forwarded `user: User` is a declaration, which hides its label beneath it: `Summary`'s
		// `user: LazilyInstantiated<User>?`, a form a by-value declaration does not provide, is hidden, which the seam
		// reports from its own chain. Inline, `Summary` is passed `nil`.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Summary.swift"]):7:5: error: @Received property `user: LazilyInstantiated<User>?` is hidden in chain: Screen -> Summary. `Screen` declares `user: User` with the same label, so the types below `Screen` receive `user: User` instead. Give `user: User` on `Screen` a different label to fix.
			\(fixtures["Screen.swift"]):8:5: note: `user: User` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.seamForwardingPropertyFixture(seam: true, summaryReceive: "@Received(onlyIfAvailable: true)", summaryType: "LazilyInstantiated<User>?"),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		let inlineOutput = try await executeSafeDIToolTest(
			swiftFileContent: Self.seamForwardingPropertyFixture(seam: false, summaryReceive: "@Received(onlyIfAvailable: true)", summaryType: "LazilyInstantiated<User>?"),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(inlineOutput.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_screenBuilder(user: User) -> Screen {
		            let summary = Summary(user: nil)
		            return Screen(user: user, summary: summary)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(user: $0)
		        }
		        self.init(screenBuilder: screenBuilder)
		    }
		}
		""")
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnfulfillableError_whenSeamsOwnForwardedPropertyHidesRequiredReceiveOfAnotherType(seam: Bool) async {
		// `Summary` requires `user: Name` beneath the seam's forwarded `user: User`, which hides the label beneath it,
		// and nothing above provides `user: Name`: the root's chain reports it unfulfillable first, with its fix-it,
		// exactly as inline.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Summary.swift"]):7:5: error: @Received property `user: Name` is not @Instantiated or @Forwarded in chain: Root -> Instantiator<Screen> -> Summary. Did you mean `user: User`?
			\(fixtures["Summary.swift"]):7:25-7:29: fixit: User
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.seamForwardingPropertyFixture(seam: seam, summaryReceive: "@Received", summaryType: "Name"),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenSeamsOwnForwardedPropertyHidesRequiredReceiveRootProvides(seam: Bool) async {
		// With `Root` holding `user: Name`, the receive is hidden with a provider above: the root's chain reports it,
		// with or without the seam, and with the seam the seam's own chain reports it too.
		await assertThrowsError(diagnostics: { fixtures in
			seam
				? """
				\(fixtures["Summary.swift"]):7:5: error: @Received property `user: Name` is hidden in chain: Screen -> Summary. `Screen` declares `user: User` with the same label, so the types below `Screen` receive `user: User` instead. Give `user: User` on `Screen` a different label to fix.
				\(fixtures["Screen.swift"]):8:5: note: `user: User` is declared here
				"""
				: """
				\(fixtures["Summary.swift"]):7:5: error: @Received property `user: Name` is hidden in chain: Root -> Instantiator<Screen> -> Summary. `Screen` declares `user: User` with the same label, so the types below `Screen` receive `user: User` instead. Give `user: User` on `Screen` a different label to fix.
				\(fixtures["Screen.swift"]):8:5: note: `user: User` is declared here
				"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.seamForwardingPropertyFixture(seam: seam, summaryReceive: "@Received", summaryType: "Name", rootHoldsName: true),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSeamsHiddenError_whenSeamsOwnForwardedPropertyHidesRequiredReceiveInModuleWithNoRoot() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Summary.swift"]):7:5: error: @Received property `user: Name` is hidden in chain: Screen -> Summary. `Screen` declares `user: User` with the same label, so the types below `Screen` receive `user: User` instead. Give `user: User` on `Screen` a different label to fix.
			\(fixtures["Screen.swift"]):8:5: note: `user: User` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Array(Self.seamForwardingPropertyFixture(seam: true, summaryReceive: "@Received", summaryType: "Name").dropFirst()),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Seams that reach one another settle

	/// `A` and `B`, seams in a lazy cycle, each instantiate a leaf that requires `token` (`Detail`, `Other`) and a
	/// builder of the other; each declares the builder first when `declaresBuilderFirst`. `Root` instantiates `token`
	/// and `a`.
	private static func lazyCycleOfSeamsFixture(declaresBuilderFirst: Bool) -> [String] {
		func seam(_ name: String, builder: String, builtType: String, leafLabel: String, leafType: String) -> String {
			let parameters = declaresBuilderFirst ? "\(builder): Instantiator<\(builtType)>, \(leafLabel): \(leafType)" : "\(leafLabel): \(leafType), \(builder): Instantiator<\(builtType)>"
			let assignments = declaresBuilderFirst ? "        self.\(builder) = \(builder)\n        self.\(leafLabel) = \(leafLabel)" : "        self.\(leafLabel) = \(leafLabel)\n        self.\(builder) = \(builder)"
			let declarations = declaresBuilderFirst
				? "    @Instantiated let \(builder): Instantiator<\(builtType)>\n    @Instantiated let \(leafLabel): \(leafType)"
				: "    @Instantiated let \(leafLabel): \(leafType)\n    @Instantiated let \(builder): Instantiator<\(builtType)>"
			return """
			@Instantiable(generateDependencyTree: true)
			public struct \(name): Instantiable {
			    public init(\(parameters)) {
			\(assignments)
			    }

			\(declarations)
			}
			"""
		}
		func leaf(_ name: String) -> String {
			"""
			@Instantiable
			public struct \(name): Instantiable {
			    public init(token: Token) {
			        self.token = token
			    }

			    @Received let token: Token
			}
			"""
		}
		return [
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(token: Token, a: A) {
			        self.token = token
			        self.a = a
			    }

			    @Instantiated let token: Token
			    @Instantiated let a: A
			}
			""",
			seam("A", builder: "bBuilder", builtType: "B", leafLabel: "detail", leafType: "Detail"),
			seam("B", builder: "aBuilder", builtType: "A", leafLabel: "other", leafType: "Other"),
			leaf("Detail"),
			leaf("Other"),
			"""
			@Instantiable
			public struct Token: Instantiable {
			    public init() {}
			}
			""",
		]
	}

	static let lazyCycleOfSeamsHash = "1EB503BFA23A82BA"

	/// The generated files of `lazyCycleOfSeamsFixture`: `A`'s and `B`'s initializers each take `token` and build the
	/// other's builder, in the order each declares its properties.
	private static func lazyCycleOfSeamsCode(declaresBuilderFirst: Bool) -> (a: String, b: String, root: String) {
		func seamCode(_ name: String, builder: String, builtType: String, leafLabel: String, leafType: String) -> String {
			let builderCode = """
			        func __safeDI_\(builder)() -> \(builtType) {
			            _ = \(builtType).__safeDI_\(builtType)_\(lazyCycleOfSeamsHash).self
			            return \(builtType)(token: token)
			        }
			        let \(builder) = Instantiator<\(builtType)>(__safeDI_\(builder))

			"""
			let leafCode = "        let \(leafLabel) = \(leafType)(token: token)\n"
			let initializerCall = declaresBuilderFirst ? "self.init(\(builder): \(builder), \(leafLabel): \(leafLabel))" : "self.init(\(leafLabel): \(leafLabel), \(builder): \(builder))"
			return """
			extension \(name) {
			    public init(token: Token) {
			\(declaresBuilderFirst ? builderCode + leafCode : leafCode + builderCode)        \(initializerCall)
			    }
			}

			extension \(name) {
			    public enum __safeDI_\(name)_\(lazyCycleOfSeamsHash) {}
			}
			"""
		}
		return (
			a: seamCode("A", builder: "bBuilder", builtType: "B", leafLabel: "detail", leafType: "Detail"),
			b: seamCode("B", builder: "aBuilder", builtType: "A", leafLabel: "other", leafType: "Other"),
			root: """
			extension Root {
			    public init() {
			        let token = Token()
			        func __safeDI_a() -> A {
			            _ = A.__safeDI_A_\(lazyCycleOfSeamsHash).self<COMMENT>
			            return A(token: token)
			        }
			        let a: A = __safeDI_a()
			        self.init(token: token, a: a)
			    }
			}
			""",
		)
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_settlesSeamsInLazyCycle_whenEachReceivesOneLabelThroughALeafAndCarriesTheOthersReceivers(declaresBuilderFirst: Bool) async throws {
		// Each seam's `token` parameter carries the receivers of the other's, which the walk meets in the order each
		// tree declares them, so the receivers' order flips on every pass: the settle loop compares what the loop
		// solves for – each parameter and its receivers as a set – so the component settles after the pass that adds
		// nothing, in either declaration order.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.lazyCycleOfSeamsFixture(declaresBuilderFirst: declaresBuilderFirst),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		let code = Self.lazyCycleOfSeamsCode(declaresBuilderFirst: declaresBuilderFirst)
		#expect(output.dependencyTreeFiles["A+SafeDI.swift"] == generatedFileHeader + code.a)
		#expect(output.dependencyTreeFiles["B+SafeDI.swift"] == generatedFileHeader + code.b)
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + code.root.replacingOccurrences(of: "<COMMENT>", with: ""))
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_settlesSeamsInLazyCycleAcrossModules_whenEachReceivesOneLabelThroughALeaf(integration: MultiModuleIntegration) async throws {
		// The seams in `Core`, the root in `App`: the caller computes the settled signatures from `Core`'s declarations
		// the same way.
		let fixture = Self.lazyCycleOfSeamsFixture(declaresBuilderFirst: true)
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: fixture.filter { !$0.contains("public struct Root: Instantiable") }),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: fixture.filter { $0.contains("public struct Root: Instantiable") }.map { "import Core\n\n" + $0 }, dependencies: ["Core"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let code = Self.lazyCycleOfSeamsCode(declaresBuilderFirst: true)
		let callComment = integration.seamCallComment(type: "A", declaringModule: "Core")
		let rootCode = code.root.replacingOccurrences(of: "<COMMENT>", with: callComment)
		let expectedGeneratedFiles: [String: [String: String]] = switch integration {
		case .moduleInfo:
			[
				"Core": ["Core.swift": generatedFileHeader + code.a + "\n\n" + code.b],
				"App": ["App.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + rootCode],
			]
		case .swiftPackagePlugin:
			[
				"Core": ["A+SafeDI.swift": generatedFileHeader + code.a, "B+SafeDI.swift": generatedFileHeader + code.b],
				"App": ["Root+SafeDI.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + rootCode],
			]
		}
		#expect(output.modules.mapValues(\.generatedFiles) == expectedGeneratedFiles)
		if compileVerificationIsEnabled {
			let compilation = try #require(output.compilation)
			#expect(compilation.modules.map(\.exitCode) == [0, 0])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSignaturesDidNotSettleError_whenSeamsThatReachOneAnotherNeedMorePassesThanTheLimit() async {
		// No input reaches the limit, so the test lowers it to one pass: the first pass gives `A` and `B` their `token`
		// parameter, which changes both signatures, so their component, which settles within the real limit (above), is
		// reported at the seam declared first.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["A.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `A`: the generated initializers of `A`, `B`, which reach one another, took a parameter from one another on every pass up to the limit. This is a defect in SafeDI; report it with these types' declarations.
			"""
		}) {
			try await DependencyTreeGenerator.$seamSignatureComputationLimitOverride.withValue(1) {
				try await executeSafeDIToolTest(
					swiftFileContent: Self.lazyCycleOfSeamsFixture(declaresBuilderFirst: true),
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	/// `Screen` and `Panel`, seams in a lazy cycle: `Screen` instantiates `Detail`, which declares the `onlyIfAvailable`
	/// alias `authToken` of `token`, read by `Reader` beneath it, and a `Panel` builder; `Panel` instantiates `Consumer`,
	/// which requires `token`, unless `panelRequiresToken` is false, and a `Screen` builder. `Root` instantiates `token`
	/// and `screen`.
	private static func vanishingAliasFallbackFixture(panelRequiresToken: Bool) -> [String] {
		[
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(token: Token, screen: Screen) {
			        self.token = token
			        self.screen = screen
			    }

			    @Instantiated let token: Token
			    @Instantiated let screen: Screen
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public struct Screen: Instantiable {
			    public init(detail: Detail, panelBuilder: Instantiator<Panel>) {
			        self.detail = detail
			        self.panelBuilder = panelBuilder
			    }

			    @Instantiated let detail: Detail
			    @Instantiated let panelBuilder: Instantiator<Panel>
			}
			""",
			"""
			@Instantiable
			public struct Detail: Instantiable {
			    public init(authToken: Token?, reader: Reader) {
			        self.authToken = authToken
			        self.reader = reader
			    }

			    @Received(fulfilledByDependencyNamed: "token", ofType: Token.self, onlyIfAvailable: true) let authToken: Token?
			    @Instantiated let reader: Reader
			}
			""",
			"""
			@Instantiable
			public struct Reader: Instantiable {
			    public init(authToken: Token?) {
			        self.authToken = authToken
			    }

			    @Received(onlyIfAvailable: true) let authToken: Token?
			}
			""",
			panelRequiresToken
				? """
				@Instantiable(generateDependencyTree: true)
				public struct Panel: Instantiable {
				    public init(consumer: Consumer, screenBuilder: Instantiator<Screen>) {
				        self.consumer = consumer
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated let consumer: Consumer
				    @Instantiated let screenBuilder: Instantiator<Screen>
				}
				"""
				: """
				@Instantiable(generateDependencyTree: true)
				public struct Panel: Instantiable {
				    public init(screenBuilder: Instantiator<Screen>) {
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated let screenBuilder: Instantiator<Screen>
				}
				""",
			"""
			@Instantiable
			public struct Consumer: Instantiable {
			    public init(token: Token) {
			        self.token = token
			    }

			    @Received let token: Token
			}
			""",
			"""
			@Instantiable
			public struct Token: Instantiable {
			    public init() {}
			}
			""",
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_settlesSeamsInLazyCycle_whenAliasFallbackWouldVanishAsItsParameterTurnsRequired() async throws {
		// `Panel`'s leaf requires `token`, which `Screen`'s tree receives through `Panel`'s call, so `Screen`'s `token`
		// is required and non-optional and `Detail`'s alias takes no fallback. Settled in one phase at a time – the
		// parameters first, then the fallbacks from the settled optionality – the component reaches that signature;
		// found together, a fallback appeared in the pass that still built `Screen`'s tree from an optional `token`,
		// then vanished, and bounced between the two seams forever.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.vanishingAliasFallbackFixture(panelRequiresToken: true),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		let detailPath = output.fixtures["Detail.swift"]
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(token: Token) {
		        func __safeDI_detail() -> Detail {
		            #sourceLocation(file: "\(detailPath)", line: 8)
		            let authToken: Token? = token
		            #sourceLocation()
		            let reader = Reader(authToken: authToken)
		            return Detail(authToken: authToken, reader: reader)
		        }
		        let detail: Detail = __safeDI_detail()
		        func __safeDI_panelBuilder() -> Panel {
		            _ = Panel.__safeDI_Panel_1EB503BFA23A82BA.self
		            return Panel(token: token)
		        }
		        let panelBuilder = Instantiator<Panel>(__safeDI_panelBuilder)
		        self.init(detail: detail, panelBuilder: panelBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_1EB503BFA23A82BA {}
		}
		""")
		#expect(output.dependencyTreeFiles["Panel+SafeDI.swift"] == generatedFileHeader + """
		extension Panel {
		    public init(token: Token) {
		        let consumer = Consumer(token: token)
		        func __safeDI_screenBuilder() -> Screen {
		            _ = Screen.__safeDI_Screen_1EB503BFA23A82BA.self
		            return Screen(token: token)
		        }
		        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		        self.init(consumer: consumer, screenBuilder: screenBuilder)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_1EB503BFA23A82BA {}
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasFromParameter_whenAliasOfOptionalParameterIsReadBeneathItInLazyCycleOfSeams() async throws {
		// The seams reach one another through instantiators and settle in one phase; `Reader` beneath `Detail`'s alias of the
		// pass-through `token` reads the alias's binding.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.vanishingAliasFallbackFixture(panelRequiresToken: false),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Panel+SafeDI.swift": generatedFileHeader + """
			extension Panel {
			    public init(token: Token?) {
			        func __safeDI_screenBuilder() -> Screen {
			            _ = Screen.__safeDI_Screen_029593DA1BB2FBD5.self
			            return Screen(token: token)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        self.init(screenBuilder: screenBuilder)
			    }
			}

			extension Panel {
			    public enum __safeDI_Panel_029593DA1BB2FBD5 {}
			}
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let token = Token()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_029593DA1BB2FBD5.self
			            return Screen(token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(token: token, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    public init(token: Token?) {
			        func __safeDI_detail() -> Detail {
			            #sourceLocation(file: "\(output.fixtures["Detail.swift"])", line: 8)
			            let authToken: Token? = token
			            #sourceLocation()
			            let reader = Reader(authToken: authToken)
			            return Detail(authToken: authToken, reader: reader)
			        }
			        let detail: Detail = __safeDI_detail()
			        func __safeDI_panelBuilder() -> Panel {
			            _ = Panel.__safeDI_Panel_029593DA1BB2FBD5.self
			            return Panel(token: token)
			        }
			        let panelBuilder = Instantiator<Panel>(__safeDI_panelBuilder)
			        self.init(detail: detail, panelBuilder: panelBuilder)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_029593DA1BB2FBD5 {}
			}
			""",
		])
	}

	// MARK: What a seam's callers see: the call shape

	/// `Feature`'s seam `Cache` instantiates `Store`, declared in `Feature`, and `Logger`, declared in `Base`, whose
	/// module info names no module; both receive `token: Token`, which `Core` declares. `Cache` is nested in the
	/// internal enum `Internals`, so its effective access is `internal`, when `cacheIsInternal`; `Store` is nested in
	/// the internal enum `Helpers`, so its initializer's effective access is `internal` however it is spelled, when
	/// `storeIsInternal`. `Logger`'s initializer is `public`.
	private static func sharedReceiveModules(cacheIsInternal: Bool = false, storeIsInternal: Bool = false) -> [ModuleFixture] {
		func nested(_ declaration: String, in enumName: String?) -> String {
			guard let enumName else { return declaration }
			return "internal enum \(enumName) {\n" + declaration.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? "" : "    \($0)" }.joined(separator: "\n") + "\n}"
		}
		let storeType = storeIsInternal ? "Helpers.Store" : "Store"
		return [
			ModuleFixture(
				name: "Base",
				packageName: "Shop",
				swiftFileContent: [
					"""
					import Core

					@Instantiable
					public struct Logger: Instantiable {
					    public init(token: Token) {
					        self.token = token
					    }

					    @Received let token: Token
					}
					""",
				],
				dependencies: ["Core"],
				omitsModuleName: true,
			),
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"import Base\nimport Core\n\n" + nested("""
					@Instantiable(generateDependencyTree: true)
					public struct Cache: Instantiable {
					    public init(store: \(storeType), logger: Logger) {
					        self.store = store
					        self.logger = logger
					    }

					    @Instantiated let store: \(storeType)
					    @Instantiated let logger: Logger
					}
					""", in: cacheIsInternal ? "Internals" : nil),
					"import Core\n\n" + nested("""
					@Instantiable
					public struct Store: Instantiable {
					    public init(token: Token) {
					        self.token = token
					    }

					    @Received let token: Token
					}
					""", in: storeIsInternal ? "Helpers" : nil),
				],
				dependencies: ["Base", "Core"],
			),
		]
	}

	private static let coreTokenModule = ModuleFixture(
		name: "Core",
		packageName: "Shop",
		swiftFileContent: [
			"""
			@Instantiable
			public struct Token: Instantiable {
			    public init() {}
			}
			""",
		],
	)

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenUnseenDeclarationReceivesWhatSeenDeclarationReceives() async {
		// `Logger`, which the callers cannot see and `Cache` instantiates, receives `token` as `Store` does: the parameter
		// agrees, but for the callers `logger` is a hole, whose builder `Cache`'s initializer would take, so `Feature`
		// reports `Cache`, naming `Logger`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"\(fixtures["Feature"]!["Cache.swift"]):4:1: error: SafeDI cannot generate the dependency tree of `Cache`: the initializer SafeDI generates for it depends on `Logger`, which is declared in a module whose SafeDI module info names no module, and the modules that call that initializer, which compute its signature from the modules this module's module info names, cannot see that declaration, so their calls would not match the initializer. Generate that module's module info with `--module-name`."
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [Self.coreTokenModule] + Self.sharedReceiveModules() + [
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [
							"""
							import Core
							import Feature

							@Instantiable(isRoot: true)
							public struct Root: Instantiable {
							    public init(token: Token, cache: Cache) {
							        self.token = token
							        self.cache = cache
							    }

							    @Instantiated let token: Token
							    @Instantiated let cache: Cache
							}
							""",
						],
						dependencies: ["Core", "Feature"],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenUnseenDeclarationReceivesWhatSeenDeclarationReceivesUnderTargetGraph() async {
		// As the previous test under the target graph: `Logger` is declared in a directory the configuration adds.
		await assertThrowsError(diagnostics: { fixtures in
			"\(fixtures["Cache.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Cache`: the initializer SafeDI generates for it depends on `Logger`, which is declared in a directory this module's `#SafeDIConfiguration` adds, and the modules that call that initializer cannot see that declaration, so their calls would not match the initializer. Declare `Logger` in a file of this module, or of a module it depends on."
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					#SafeDIConfiguration(
					    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
					)
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Cache: Instantiable {
					    public init(store: Store, logger: Logger) {
					        self.store = store
					        self.logger = logger
					    }

					    @Instantiated let store: Store
					    @Instantiated let logger: Logger
					}
					""",
					"""
					@Instantiable
					public struct Store: Instantiable {
					    public init(token: Token) {
					        self.token = token
					    }

					    @Received let token: Token
					}
					""",
					"""
					@Instantiable
					public struct Token: Instantiable {
					    public init() {}
					}
					""",
				],
				additionalDirectorySwiftFileContent: [
					"""
					@Instantiable
					public struct Logger: Instantiable {
					    public init(token: Token) {
					        self.token = token
					    }

					    @Received let token: Token
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				pluginTargetGraph: { inputSwiftFilePaths in
					PluginTargetGraph(
						target: PluginTargetGraph.Target(moduleName: "Core", packageID: "shop", sourceFilePaths: inputSwiftFilePaths, dependencyModuleNames: []),
						dependencyTargets: [],
					)
				},
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenUnseenReceiverOfInternalSeamIsInstantiatedInItsTree() async {
		// `Logger`'s `public init` proves `token` public, `Helpers.Store`'s initializer, internal by nesting, internal: the
		// parameter's tier access is `internal` in both views, capped at the seam's type, but for the callers, who cannot
		// see `Logger`, `logger` is a hole, so `Feature` reports `Internals.Cache`, naming `Logger`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"\(fixtures["Feature"]!["Cache.swift"]):5:5: error: SafeDI cannot generate the dependency tree of `Internals.Cache`: the initializer SafeDI generates for it depends on `Logger`, which is declared in a module whose SafeDI module info names no module, and the modules that call that initializer, which compute its signature from the modules this module's module info names, cannot see that declaration, so their calls would not match the initializer. Generate that module's module info with `--module-name`."
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [Self.coreTokenModule] + Self.sharedReceiveModules(cacheIsInternal: true, storeIsInternal: true),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsOnlySeamWhoseCallersViewComputationThrows_whenAnotherSeamReachesNothingUnseen() async {
		// `Screen`'s `Detail` receives `logger: Logger` and `Panel` `logger: Feature.Logger`, one type in this run's
		// view, which qualifies `Logger` by `Base`'s declaration, and two in the callers', which cannot: their
		// computation of `Screen` throws, and `Screen` alone is reported. `Cache` instantiates `Store` and nothing
		// unseen.
		await assertThrowsMultiModuleError(inModule: "Core", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: the initializer SafeDI generates for it depends on `Feature.Logger`, which is declared in a module whose SafeDI module info names no module, and the modules that call that initializer, which compute its signature from the modules this module's module info names, cannot see that declaration, so their calls would not match the initializer. Generate that module's module info with `--module-name`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Base",
						packageName: "Shop",
						swiftFileContent: [
							"""
							public enum Feature {}

							public extension Feature {
							    @Instantiable
							    final class Logger: Instantiable {
							        public init() {}
							    }
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

							@Instantiable(generateDependencyTree: true)
							public final class Screen: Instantiable {
							    public init(detail: Feature.Detail, panel: Panel) {
							        self.detail = detail
							        self.panel = panel
							    }

							    @Instantiated let detail: Feature.Detail
							    @Instantiated let panel: Panel
							}
							""",
							"""
							import Base

							extension Feature {
							    @Instantiable
							    public final class Detail: Instantiable {
							        public init(logger: Logger) {
							            self.logger = logger
							        }

							        @Received let logger: Logger
							    }
							}
							""",
							"""
							import Base

							@Instantiable
							public final class Panel: Instantiable {
							    public init(logger: Feature.Logger) {
							        self.logger = logger
							    }

							    @Received let logger: Feature.Logger
							}
							""",
							"""
							@Instantiable(generateDependencyTree: true)
							public final class Cache: Instantiable {
							    public init(store: Store) {
							        self.store = store
							    }

							    @Instantiated let store: Store
							}
							""",
							"""
							@Instantiable
							public final class Store: Instantiable {
							    public init() {}
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
	mutating func generate_namesUnseenReceiver_whenUnseenTypeFulfillingItsParameterIsDeclaredBeforeIt() async {
		// `Token` and `Zeta`, which receives `token`, are both unseen by the callers, and `Token` is declared first: the
		// receiver is named, since `Token`'s absence alone changes nothing a caller passes.
		await assertThrowsMultiModuleError(inModule: "Core", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Cache.swift"]):4:1: error: SafeDI cannot generate the dependency tree of `Cache`: the initializer SafeDI generates for it depends on `Zeta`, which is declared in a module whose SafeDI module info names no module, and the modules that call that initializer, which compute its signature from the modules this module's module info names, cannot see that declaration, so their calls would not match the initializer. Generate that module's module info with `--module-name`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "AModels", packageName: "Shop", swiftFileContent: [seamFixtureType(named: "Token", declarations: [])], omitsModuleName: true),
					ModuleFixture(
						name: "BFeature",
						packageName: "Shop",
						swiftFileContent: ["import AModels\n\n" + seamFixtureType(named: "Zeta", declarations: ["@Received let token: Token"])],
						dependencies: ["AModels"],
						omitsModuleName: true,
					),
					ModuleFixture(
						name: "Core",
						packageName: "Shop",
						swiftFileContent: ["import AModels\nimport BFeature\n\n" + seamFixtureType(named: "Cache", isSeam: true, declarations: ["@Instantiated let zeta: Zeta"])],
						dependencies: ["AModels", "BFeature"],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesUnseenReceiverOfRedeclaredInitializersParameter_whenCallersGeneratedInitializerWouldRedeclareOne() async {
		// Without `Logger`, which the callers cannot see, `Cache`'s generated initializer would take `token` alone, which
		// the initializer `Cache` declares takes, so the callers' computation throws naming `token`: `Logger`, its unseen
		// receiver, is named, not `Alpha`, declared before it, whose `name` the error does not name.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Cache.swift"]):5:1: error: SafeDI cannot generate the dependency tree of `Cache`: the initializer SafeDI generates for it depends on `Logger`, which is declared in a module whose SafeDI module info names no module, and the modules that call that initializer, which compute its signature from the modules this module's module info names, cannot see that declaration, so their calls would not match the initializer. Generate that module's module info with `--module-name`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: [seamFixtureType(named: "Token", declarations: []), seamFixtureType(named: "Name", declarations: [])]),
					ModuleFixture(name: "ABase", packageName: "Shop", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "Alpha", declarations: ["@Received let name: Name"])], dependencies: ["Core"], omitsModuleName: true),
					ModuleFixture(name: "BBase", packageName: "Shop", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "Logger", declarations: ["@Received let token: Token", "@Received let name: Name"])], dependencies: ["Core"], omitsModuleName: true),
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContent: [
							"""
							import ABase
							import BBase
							import Core

							@Instantiable(generateDependencyTree: true)
							public struct Cache: Instantiable {
							    public init(store: Store, logger: Logger, alpha: Alpha) {
							        self.store = store
							        self.logger = logger
							        self.alpha = alpha
							    }

							    public init(token: Token) {
							        self.init(store: Store(token: token), logger: Logger(token: token, name: Name()), alpha: Alpha(name: Name()))
							    }

							    @Instantiated let store: Store
							    @Instantiated let logger: Logger
							    @Instantiated let alpha: Alpha
							}
							""",
							"import Core\n\n" + seamFixtureType(named: "Store", declarations: ["@Received let token: Token"]),
						],
						dependencies: ["ABase", "BBase", "Core"],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsSeamReachingSeamCallersCannotCompute_whenCallersComputationOfReachedSeamThrowsOrDiffers(callersComputationThrows: Bool) async {
		// The callers cannot see `Base`'s `Feature.Logger`, so they qualify `Detail`'s `logger` otherwise: beside
		// `Panel`'s `logger: Feature.Logger` their computation of `Screen` throws, and without `Panel` it merely differs.
		// Either way `Outer`, which passes `Screen`'s parameter through, is reported on its own call shape too.
		await assertThrowsMultiModuleError(inModule: "Core", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Outer.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Outer`: the initializer SafeDI generates for it depends on `Feature.Logger`, which is declared in a module whose SafeDI module info names no module, and the modules that call that initializer, which compute its signature from the modules this module's module info names, cannot see that declaration, so their calls would not match the initializer. Generate that module's module info with `--module-name`.
			\(fixtures["Core"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: the initializer SafeDI generates for it depends on `Feature.Logger`, which is declared in a module whose SafeDI module info names no module, and the modules that call that initializer, which compute its signature from the modules this module's module info names, cannot see that declaration, so their calls would not match the initializer. Generate that module's module info with `--module-name`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Base",
						packageName: "Shop",
						swiftFileContent: [
							"""
							public enum Feature {}

							public extension Feature {
							    @Instantiable
							    final class Logger: Instantiable {
							        public init() {}
							    }
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

							extension Feature {
							    @Instantiable
							    public final class Detail: Instantiable {
							        public init(logger: Logger) {
							            self.logger = logger
							        }

							        @Received let logger: Logger
							    }
							}
							""",
							"import Base\n\n" + seamFixtureType(named: "Outer", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let screen: Screen"]),
							"import Base\n\n" + seamFixtureType(named: "Screen", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let detail: Feature.Detail"] + (callersComputationThrows ? ["@Instantiated let panel: Panel"] : [])),
						] + (callersComputationThrows ? ["import Base\n\n" + seamFixtureType(named: "Panel", isFinalClass: true, declarations: ["@Received let logger: Feature.Logger"])] : []),
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
	mutating func generate_namesUnseenDeclarationWhoseReceiveChangesSignature_whenSeamReachesSeveral() async {
		// `Cache` instantiates `Alpha` and `Zeta`, both unseen by the callers: the callers' view leaves both out and
		// takes no `token`, which `Zeta` receives, so `Zeta` is named, not `Alpha`, which sorts first and changes
		// nothing a caller passes.
		await assertThrowsMultiModuleError(inModule: "Core", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Cache.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Cache`: the initializer SafeDI generates for it depends on `Zeta`, which is declared in a module whose SafeDI module info names no module, and the modules that call that initializer, which compute its signature from the modules this module's module info names, cannot see that declaration, so their calls would not match the initializer. Generate that module's module info with `--module-name`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Base",
						packageName: "Shop",
						swiftFileContent: [
							"""
							@Instantiable
							public final class Alpha: Instantiable {
							    public init() {}
							}
							""",
							"""
							@Instantiable
							public final class Zeta: Instantiable {
							    public init(token: String) {
							        self.token = token
							    }

							    @Received let token: String
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

							@Instantiable(generateDependencyTree: true)
							public final class Cache: Instantiable {
							    public init(zeta: Zeta, alpha: Alpha) {
							        self.zeta = zeta
							        self.alpha = alpha
							    }

							    @Instantiated let zeta: Zeta
							    @Instantiated let alpha: Alpha
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
	mutating func generate_namesUnseenDeclarationDeclaredFirst_whenSeveralUnseenDeclarationsReceiveTheParameter() async {
		// Six unseen types receive `token`, declared in one file in an order that neither their names nor the
		// seam's tree keeps – `Echo` is declared first, `Alpha` sorts first, and `Cache` instantiates `Bravo` first –
		// so the one named is the one declared first.
		await assertThrowsMultiModuleError(inModule: "Core", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Cache.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Cache`: the initializer SafeDI generates for it depends on `Echo`, which is declared in a module whose SafeDI module info names no module, and the modules that call that initializer, which compute its signature from the modules this module's module info names, cannot see that declaration, so their calls would not match the initializer. Generate that module's module info with `--module-name`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Base",
						packageName: "Shop",
						swiftFileContent: [
							"""
							@Instantiable
							public final class Echo: Instantiable {
							    public init(token: String) {
							        self.token = token
							    }

							    @Received let token: String
							}

							@Instantiable
							public final class Alpha: Instantiable {
							    public init(token: String) {
							        self.token = token
							    }

							    @Received let token: String
							}

							@Instantiable
							public final class Foxtrot: Instantiable {
							    public init(token: String) {
							        self.token = token
							    }

							    @Received let token: String
							}

							@Instantiable
							public final class Charlie: Instantiable {
							    public init(token: String) {
							        self.token = token
							    }

							    @Received let token: String
							}

							@Instantiable
							public final class Delta: Instantiable {
							    public init(token: String) {
							        self.token = token
							    }

							    @Received let token: String
							}

							@Instantiable
							public final class Bravo: Instantiable {
							    public init(token: String) {
							        self.token = token
							    }

							    @Received let token: String
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

							@Instantiable(generateDependencyTree: true)
							public final class Cache: Instantiable {
							    public init(bravo: Bravo, delta: Delta, charlie: Charlie, foxtrot: Foxtrot, alpha: Alpha, echo: Echo) {
							        self.bravo = bravo
							        self.delta = delta
							        self.charlie = charlie
							        self.foxtrot = foxtrot
							        self.alpha = alpha
							        self.echo = echo
							    }

							    @Instantiated let bravo: Bravo
							    @Instantiated let delta: Delta
							    @Instantiated let charlie: Charlie
							    @Instantiated let foxtrot: Foxtrot
							    @Instantiated let alpha: Alpha
							    @Instantiated let echo: Echo
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
	mutating func generate_namesUnseenDeclarationTheSeamReaches_whenEveryReceiverOfTheParameterIsSeen() async {
		// `Cache` reaches `Reader`, which receives `token`, only through `Bridge`, which the callers cannot see: the
		// callers' view leaves `Bridge` out and takes no `token`, but `Reader` and `Token` are `Common`'s, which the
		// callers see, so the declaration named is the one the tree reaches that they cannot see.
		await assertThrowsMultiModuleError(inModule: "Core", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Cache.swift"]):4:1: error: SafeDI cannot generate the dependency tree of `Cache`: the initializer SafeDI generates for it depends on `Bridge`, which is declared in a module whose SafeDI module info names no module, and the modules that call that initializer, which compute its signature from the modules this module's module info names, cannot see that declaration, so their calls would not match the initializer. Generate that module's module info with `--module-name`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Common",
						packageName: "Shop",
						swiftFileContent: [
							"""
							@Instantiable
							public final class Reader: Instantiable {
							    public init(token: Token) {
							        self.token = token
							    }

							    @Received let token: Token
							}
							""",
							"""
							@Instantiable
							public final class Token: Instantiable {
							    public init() {}
							}
							""",
						],
					),
					ModuleFixture(
						name: "Base",
						packageName: "Shop",
						swiftFileContent: [
							"""
							import Common

							@Instantiable
							public final class Bridge: Instantiable {
							    public init(reader: Reader) {
							        self.reader = reader
							    }

							    @Instantiated let reader: Reader
							}
							""",
						],
						dependencies: ["Common"],
						omitsModuleName: true,
					),
					ModuleFixture(
						name: "Core",
						packageName: "Shop",
						swiftFileContent: [
							"""
							import Base
							import Common

							@Instantiable(generateDependencyTree: true)
							public final class Cache: Instantiable {
							    public init(bridge: Bridge) {
							        self.bridge = bridge
							    }

							    @Instantiated let bridge: Bridge
							}
							""",
						],
						dependencies: ["Base", "Common"],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	/// How `Feature.Screen`, `Core`'s seam, names `Logger`, which `Base` declares nested in `Feature`.
	enum NestedTypeUse: String {
		/// The seam's own `@Forwarded let logger: Logger`, built through an `Instantiator<Feature.Screen>` by `Detail`.
		case forwarded
		/// The seam's own alias `logger` of `log`, `ofType: Logger.self`.
		case alias
		/// `Panel`, inside the seam's tree, receives `logger: Logger`.
		case receivedInsideTree
	}

	/// `Core`'s files for `NestedTypeUse`: `Feature.Screen` in a file named `Screen.swift`, with `Detail` and `Panel`.
	private static func nestedTypeUseFiles(_ use: NestedTypeUse) -> [String] {
		let screen = switch use {
		case .forwarded:
			"""
			public extension Feature {
			    @Instantiable(generateDependencyTree: true)
			    final class Screen: Instantiable {
			        public init(logger: Logger, detail: Detail) {
			            self.logger = logger
			            self.detail = detail
			        }

			        @Forwarded let logger: Logger
			        @Instantiated let detail: Detail
			    }
			}
			"""
		case .alias:
			"""
			public extension Feature {
			    @Instantiable(generateDependencyTree: true)
			    final class Screen: Instantiable {
			        public init(logger: Logger, detail: Detail) {
			            self.logger = logger
			            self.detail = detail
			        }

			        @Received(fulfilledByDependencyNamed: "log", ofType: Logger.self) let logger: Logger
			        @Instantiated let detail: Detail
			    }
			}
			"""
		case .receivedInsideTree:
			"""
			public extension Feature {
			    @Instantiable(generateDependencyTree: true)
			    final class Screen: Instantiable {
			        public init(panel: Panel, detail: Detail) {
			            self.panel = panel
			            self.detail = detail
			        }

			        @Instantiated let panel: Panel
			        @Instantiated let detail: Detail
			    }
			}
			"""
		}
		return [
			screen,
			"""
			@Instantiable
			public final class Detail: Instantiable {
			    public init() {}
			}
			""",
			"""
			extension Feature {
			    @Instantiable
			    public final class Panel: Instantiable {
			        public init(logger: Logger) {
			            self.logger = logger
			        }

			        @Received let logger: Logger
			    }
			}
			""",
		]
	}

	@Test(arguments: [NestedTypeUse.forwarded, .alias, .receivedInsideTree])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamNamesNestedTypeOfModuleInfoNamingNoModule(use: NestedTypeUse) async {
		// A forwarded property, an alias's `ofType:`, and a receive inside the tree each put `Logger` in a parameter's
		// type, which this run qualifies as `Feature.Logger` by `Base`'s declaration and the callers cannot: the
		// call shapes differ, and the declaration that fulfills the parameter's type is named.
		await assertThrowsMultiModuleError(inModule: "Core", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Screen.swift"]):4:5: error: SafeDI cannot generate the dependency tree of `Feature.Screen`: the initializer SafeDI generates for it depends on `Feature.Logger`, which is declared in a module whose SafeDI module info names no module, and the modules that call that initializer, which compute its signature from the modules this module's module info names, cannot see that declaration, so their calls would not match the initializer. Generate that module's module info with `--module-name`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Base",
						packageName: "Shop",
						swiftFileContent: [
							"""
							public enum Feature {}

							public extension Feature {
							    @Instantiable
							    final class Logger: Instantiable {
							        public init() {}
							    }
							}
							""",
						],
						omitsModuleName: true,
					),
					ModuleFixture(
						name: "Core",
						packageName: "Shop",
						swiftFileContent: Self.nestedTypeUseFiles(use).map { "import Base\n\n" + $0 },
						dependencies: ["Base"],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [NestedTypeUse.forwarded, .alias, .receivedInsideTree])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamNamesNestedTypeOfAdditionalDirectoryUnderTargetGraph(use: NestedTypeUse) async {
		// As the previous test under the target graph: `Feature.Logger` is declared in a directory the configuration
		// adds, which the callers' graph leaves out.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):2:5: error: SafeDI cannot generate the dependency tree of `Feature.Screen`: the initializer SafeDI generates for it depends on `Feature.Logger`, which is declared in a directory this module's `#SafeDIConfiguration` adds, and the modules that call that initializer cannot see that declaration, so their calls would not match the initializer. Declare `Feature.Logger` in a file of this module, or of a module it depends on.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					#SafeDIConfiguration(
					    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
					)
					""",
				] + Self.nestedTypeUseFiles(use),
				additionalDirectorySwiftFileContent: [
					"""
					public enum Feature {}

					public extension Feature {
					    @Instantiable
					    final class Logger: Instantiable {
					        public init() {}
					    }
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
	mutating func generate_throwsError_whenItsTreeInstantiatesAdditionalDirectoryDeclarationUnderTargetGraph() async {
		// The callers cannot see `Logger`, declared in a directory the configuration adds, which `Store` instantiates: for
		// them `Store`'s `logger` is a hole, so `Core` reports `Cache`, naming `Logger`.
		await assertThrowsError(diagnostics: { fixtures in
			"\(fixtures["Cache.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Cache`: the initializer SafeDI generates for it depends on `Logger`, which is declared in a directory this module's `#SafeDIConfiguration` adds, and the modules that call that initializer cannot see that declaration, so their calls would not match the initializer. Declare `Logger` in a file of this module, or of a module it depends on."
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					#SafeDIConfiguration(
					    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
					)
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Cache: Instantiable {
					    public init(store: Store) {
					        self.store = store
					    }

					    @Instantiated let store: Store
					}
					""",
					"""
					@Instantiable
					public struct Store: Instantiable {
					    public init(logger: Logger) {
					        self.logger = logger
					    }

					    @Instantiated let logger: Logger
					}
					""",
				],
				additionalDirectorySwiftFileContent: [Self.loggerContent],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				pluginTargetGraph: { inputSwiftFilePaths in
					PluginTargetGraph(
						target: PluginTargetGraph.Target(moduleName: "Core", packageID: "shop", sourceFilePaths: inputSwiftFilePaths, dependencyModuleNames: []),
						dependencyTargets: [],
					)
				},
			)
		}
	}

	// MARK: A2' neighbors: required optional wrappers, forwarded wrappers, nested seams, nested and existential types

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsInstanceOfSeamsOwnForwardedWrapper_whenByValueReceiveInsideIsRequired() async throws {
		// The seam's own forwarded `user: LazilyInstantiated<User>` is a parameter as declared, and provides the
		// instance to `Detail` as a received wrapper does.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(screenBuilder: Instantiator<Screen>) {
				        self.screenBuilder = screenBuilder
				    }

				    @Instantiated let screenBuilder: Instantiator<Screen>
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    public init(user: LazilyInstantiated<User>, detail: Detail) {
				        self.user = user
				        self.detail = detail
				    }

				    @Forwarded let user: LazilyInstantiated<User>
				    @Instantiated let detail: Detail
				}
				""",
				"""
				@Instantiable
				public struct Detail: Instantiable {
				    public init(user: User) {
				        self.user = user
				    }

				    @Received let user: User
				}
				""",
				"""
				@Instantiable
				public final class User: Instantiable, Sendable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(user: LazilyInstantiated<User>) {
		        let detail = Detail(user: user.instance)
		        self.init(user: user, detail: detail)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_F630901E5C2B99B5 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_screenBuilder(user: LazilyInstantiated<User>) -> Screen {
		            _ = Screen.__safeDI_Screen_F630901E5C2B99B5.self
		            return Screen(user: user)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(user: $0)
		        }
		        self.init(screenBuilder: screenBuilder)
		    }
		}
		""")
	}

	/// `Screen`, a seam, instantiates `Inner`, a seam whose `Summary` receives `user` as `summaryReceive`, beside its
	/// own receive of `user` as `ownReceive` or its `Detail`'s required `user: User`; `Root` holds `user` as `rootHolding`.
	private static func nestedSeamsFixture(ownReceive: String?, detailReceivesUser: Bool, summaryReceive: (declaration: String, type: String), rootHolding: String) -> [String] {
		var screenParameters = [String]()
		var screenAssignments = [String]()
		var screenDeclarations = [String]()
		if let ownReceive {
			screenParameters.append("user: \(ownReceive.split(separator: ":").last!.trimmingCharacters(in: .whitespaces))")
			screenAssignments.append("        self.user = user")
			screenDeclarations.append("    \(ownReceive)")
		}
		if detailReceivesUser {
			screenParameters.append("detail: Detail")
			screenAssignments.append("        self.detail = detail")
			screenDeclarations.append("    @Instantiated let detail: Detail")
		}
		screenParameters.append("inner: Inner")
		screenAssignments.append("        self.inner = inner")
		screenDeclarations.append("    @Instantiated let inner: Inner")
		return [
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(user: \(rootHolding), screen: Screen) {
			        self.user = user
			        self.screen = screen
			    }

			    @Instantiated let user: \(rootHolding)
			    @Instantiated let screen: Screen
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public struct Screen: Instantiable {
			    public init(\(screenParameters.joined(separator: ", "))) {
			\(screenAssignments.joined(separator: "\n"))
			    }

			\(screenDeclarations.joined(separator: "\n"))
			}
			""",
			"""
			@Instantiable
			public struct Detail: Instantiable {
			    public init(user: User) {
			        self.user = user
			    }

			    @Received let user: User
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public struct Inner: Instantiable {
			    public init(summary: Summary) {
			        self.summary = summary
			    }

			    @Instantiated let summary: Summary
			}
			""",
			"""
			@Instantiable
			public struct Summary: Instantiable {
			    public init(user: \(summaryReceive.type)) {
			        self.user = user
			    }

			    \(summaryReceive.declaration) let user: \(summaryReceive.type)
			}
			""",
			"""
			@Instantiable
			public final class User: Instantiable, Sendable {
			    public init() {}
			}
			""",
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenOuterSeamsByValueReceiveIsBesideNestedSeamsOptionalWrapperParameter() async {
		// `Inner`'s parameter `user: LazilyInstantiated<User>?`, received only if available, carries `Summary`'s receive,
		// which the outer tree receives through `Inner`'s call beside `Detail`'s `user: User`: a collision at `Screen`,
		// naming `Summary`, the receiver inside the nested seam, not `Inner`.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `user` as `user: User` on `Detail` and `user: LazilyInstantiated<User>?` on `Summary`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `user` the same way in every type of the tree, or declare it on `Screen` as the form that provides the others: `@Received let user: LazilyInstantiated<User>`.
			\(fixtures["Detail.swift"]):7:5: note: `Detail` receives `user: User` here.
			\(fixtures["Summary.swift"]):7:5: note: `Summary` receives `user: LazilyInstantiated<User>?` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.nestedSeamsFixture(ownReceive: nil, detailReceivesUser: true, summaryReceive: ("@Received(onlyIfAvailable: true)", "LazilyInstantiated<User>?"), rootHolding: "User"),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsInstanceOfSeamsOwnWrapperReceive_whenNestedSeamsParameterIsByValue() async throws {
		// `Inner`'s parameter `user: User` carries `Summary`'s receive, which the outer seam's own `user:
		// LazilyInstantiated<User>` provides: the call to `Inner` reads the instance.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.nestedSeamsFixture(ownReceive: "@Received let user: LazilyInstantiated<User>", detailReceivesUser: false, summaryReceive: ("@Received", "User"), rootHolding: "LazilyInstantiated<User>"),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Inner+SafeDI.swift"] == generatedFileHeader + """
		extension Inner {
		    public init(user: User) {
		        let summary = Summary(user: user)
		        self.init(summary: summary)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_38882A8C29DA6D12 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(user: LazilyInstantiated<User>) {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_38882A8C29DA6D12.self
		            return Inner(user: user.instance)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(user: user, inner: inner)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_F630901E5C2B99B5 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_user() -> User {
		            User()
		        }
		        let user = LazilyInstantiated<User>(__safeDI_user)
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_F630901E5C2B99B5.self
		            return Screen(user: user)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, screen: screen)
		    }
		}
		""")
		#expect(output.warnings.map(\.formatted) == ["\(output.fixtures["Root.swift"]):8:5: warning: @Instantiated property `user: LazilyInstantiated<User>` is instantiated whenever `Root` is created: `Summary` is created with `Root` and receives the instance as `user: User`. To instantiate it lazily, receive `user: LazilyInstantiated<User>` on `Summary`."])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesInstanceOfWrapperOfNestedType_whenByValueReceiveIsRequired() async throws {
		// The wrapper's instance type is the nested `Feature.User`, which `Detail` alone receives, by value: the
		// parameter is by value, and the caller reads the instance of the wrapper it holds.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(user: LazilyInstantiated<Feature.User>, screen: Screen) {
				        self.user = user
				        self.screen = screen
				    }

				    @Instantiated let user: LazilyInstantiated<Feature.User>
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
				    public init(user: Feature.User) {
				        self.user = user
				    }

				    @Received let user: Feature.User
				}
				""",
				"""
				public enum Feature {}

				extension Feature {
				    @Instantiable
				    public final class User: Instantiable, Sendable {
				        public init() {}
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(user: Feature.User) {
		        let detail = Detail(user: user)
		        self.init(detail: detail)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_D9635D61408B693A {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_user() -> Feature.User {
		            Feature.User()
		        }
		        let user = LazilyInstantiated<Feature.User>(__safeDI_user)
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_D9635D61408B693A.self
		            return Screen(user: user.instance)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, screen: screen)
		    }
		}
		""")
	}

	/// `Root` instantiates `logger: LazilyInstantiated<any Logger>`, fulfilled by `ConsoleLogger`, and `Screen`, a seam,
	/// whose `Detail` receives `logger: any Logger`, `Summary` the wrapper as `summaryReceive`, and `Preview`
	/// `logger: Logger?` only if available, spelled without `any`.
	private static func existentialWrapperFixture(summaryReceive: (declaration: String, type: String)) -> [String] {
		[
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(logger: LazilyInstantiated<any Logger>, screen: Screen) {
			        self.logger = logger
			        self.screen = screen
			    }

			    @Instantiated(fulfilledByType: "ConsoleLogger") let logger: LazilyInstantiated<any Logger>
			    @Instantiated let screen: Screen
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public struct Screen: Instantiable {
			    public init(detail: Detail, summary: Summary, preview: Preview) {
			        self.detail = detail
			        self.summary = summary
			        self.preview = preview
			    }

			    @Instantiated let detail: Detail
			    @Instantiated let summary: Summary
			    @Instantiated let preview: Preview
			}
			""",
			"""
			@Instantiable
			public struct Detail: Instantiable {
			    public init(logger: any Logger) {
			        self.logger = logger
			    }

			    @Received let logger: any Logger
			}
			""",
			"""
			@Instantiable
			public struct Summary: Instantiable {
			    public init(logger: \(summaryReceive.type)) {
			        self.logger = logger
			    }

			    \(summaryReceive.declaration) let logger: \(summaryReceive.type)
			}
			""",
			"""
			@Instantiable
			public struct Preview: Instantiable {
			    public init(logger: Logger?) {
			        self.logger = logger
			    }

			    @Received(onlyIfAvailable: true) let logger: Logger?
			}
			""",
			"""
			public protocol Logger: Sendable {}

			@Instantiable(fulfillingAdditionalTypes: [Logger.self])
			public final class ConsoleLogger: Instantiable, Logger {
			    public init() {}
			}
			""",
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOneExistentialWrapperParameter_whenByValueReceivesSpellTheExistentialWithAndWithoutAny() async throws {
		// `any Logger` and `Logger` are one type: the required wrapper provides the instance to both by-value receivers,
		// and the guard hashes the type spelled without `any`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.existentialWrapperFixture(summaryReceive: ("@Received", "LazilyInstantiated<any Logger>")),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(logger: LazilyInstantiated<any Logger>) {
		        let detail = Detail(logger: logger.instance)
		        let summary = Summary(logger: logger)
		        let preview = Preview(logger: logger.instance)
		        self.init(detail: detail, summary: summary, preview: preview)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_756559A0816FE635 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_logger() -> ConsoleLogger {
		            ConsoleLogger()
		        }
		        let logger = LazilyInstantiated<any Logger>(__safeDI_logger)
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_756559A0816FE635.self
		            return Screen(logger: logger)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(logger: logger, screen: screen)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsProvidingFormAsReceiverDoes_whenExistentialWrapperReceivedOnlyIfAvailableCollidesWithByValueReceives() async {
		// The remedy spells the providing form as `Summary` spells its receive, `any` included.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its tree receives `logger` as `logger: any Logger` on `Detail` and `logger: LazilyInstantiated<any Logger>?` on `Summary` and `logger: Logger?` on `Preview`, and the generated initializer takes each property the tree receives from outside the seam as one parameter named after it. Receive `logger` the same way in every type of the tree, or declare it on `Screen` as the form that provides the others: `@Received let logger: LazilyInstantiated<any Logger>`.
			\(fixtures["Detail.swift"]):7:5: note: `Detail` receives `logger: any Logger` here.
			\(fixtures["Summary.swift"]):7:5: note: `Summary` receives `logger: LazilyInstantiated<any Logger>?` here.
			\(fixtures["Preview.swift"]):7:5: note: `Preview` receives `logger: Logger?` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.existentialWrapperFixture(summaryReceive: ("@Received(onlyIfAvailable: true)", "LazilyInstantiated<any Logger>?")),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Divergences from building the tree inline, pinned beside the inline output

	/// `Root` builds `Feature` through a builder; `Feature` forwards `token: Token?` and instantiates `Screen`, a seam
	/// when `seam`, whose `Detail` declares the `onlyIfAvailable` alias `authToken` of `token`.
	private static func aliasOfOptionalParameterFixture(seam: Bool) -> [String] {
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
			    public init(token: Token?, screen: Screen) {
			        self.token = token
			        self.screen = screen
			    }

			    @Forwarded let token: Token?
			    @Instantiated let screen: Screen
			}
			""",
			"""
			@Instantiable\(seam ? "(generateDependencyTree: true)" : "")
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
			    public init(authToken: Token?) {
			        self.authToken = authToken
			    }

			    @Received(fulfilledByDependencyNamed: "token", ofType: Token.self, onlyIfAvailable: true) let authToken: Token?
			}
			""",
			"""
			public struct Token {}
			""",
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasFromOptionalFormOfFulfillingProperty_whenCallerHoldsOnlyThatForm() async throws {
		// The caller's tree holds only `token: Token?`. `Detail`'s `onlyIfAvailable` alias of `token: Token` reads that
		// optional form, inline as through the seam, which binds the alias from its parameter: both are non-`nil` where the
		// caller's `token` is.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.aliasOfOptionalParameterFixture(seam: true),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		let detailPath = output.fixtures["Detail.swift"]
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(token: Token?) {
		        func __safeDI_detail() -> Detail {
		            #sourceLocation(file: "\(detailPath)", line: 7)
		            let authToken: Token? = token
		            #sourceLocation()
		            return Detail(authToken: authToken)
		        }
		        let detail: Detail = __safeDI_detail()
		        self.init(detail: detail)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_029593DA1BB2FBD5 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_featureBuilder(token: Token?) -> Feature {
		            func __safeDI_screen() -> Screen {
		                _ = Screen.__safeDI_Screen_029593DA1BB2FBD5.self
		                return Screen(token: token)
		            }
		            let screen: Screen = __safeDI_screen()
		            return Feature(token: token, screen: screen)
		        }
		        let featureBuilder = Instantiator<Feature> {
		            __safeDI_featureBuilder(token: $0)
		        }
		        self.init(featureBuilder: featureBuilder)
		    }
		}
		""")
		let inlineOutput = try await executeSafeDIToolTest(
			swiftFileContent: Self.aliasOfOptionalParameterFixture(seam: false),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(inlineOutput.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_featureBuilder(token: Token?) -> Feature {
		            func __safeDI_screen() -> Screen {
		                func __safeDI_detail() -> Detail {
		                    #sourceLocation(file: "\(inlineOutput.fixtures["Detail.swift"])", line: 7)
		                    let authToken: Token? = token
		                    #sourceLocation()
		                    return Detail(authToken: authToken)
		                }
		                let detail: Detail = __safeDI_detail()
		                return Screen(detail: detail)
		            }
		            let screen: Screen = __safeDI_screen()
		            return Feature(token: token, screen: screen)
		        }
		        let featureBuilder = Instantiator<Feature> {
		            __safeDI_featureBuilder(token: $0)
		        }
		        self.init(featureBuilder: featureBuilder)
		    }
		}
		""")
	}

	/// `Root` instantiates `user: LazilyInstantiated<User>` and `Screen`, a seam when `seam`, which builds `Detail`,
	/// which requires `user: User`, through an `Instantiator`.
	private static func instanceReadInsideBuilderFixture(seam: Bool) -> [String] {
		[
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(user: LazilyInstantiated<User>, screen: Screen) {
			        self.user = user
			        self.screen = screen
			    }

			    @Instantiated let user: LazilyInstantiated<User>
			    @Instantiated let screen: Screen
			}
			""",
			"""
			@Instantiable\(seam ? "(generateDependencyTree: true)" : "")
			public struct Screen: Instantiable {
			    public init(detailBuilder: Instantiator<Detail>) {
			        self.detailBuilder = detailBuilder
			    }

			    @Instantiated let detailBuilder: Instantiator<Detail>
			}
			""",
			"""
			@Instantiable
			public struct Detail: Instantiable {
			    public init(user: User) {
			        self.user = user
			    }

			    @Received let user: User
			}
			""",
			"""
			@Instantiable
			public final class User: Instantiable, Sendable {
			    public init() {}
			}
			""",
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsWrappersInstanceAtSeamCall_whenTreeReadsInstanceInsideBuilder() async throws {
		// The third documented divergence: the seam's by-value parameter is filled with `.instance` at the call, when
		// `Root` is created, where inline reads it inside the builder, when `Detail` is built. Neither run warns that
		// `user` is instantiated whenever `Root` is created: the analysis reads the inlined scopes, where a builder
		// defers the read.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.instanceReadInsideBuilderFixture(seam: true),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    public init(user: User) {
		        func __safeDI_detailBuilder() -> Detail {
		            Detail(user: user)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_38882A8C29DA6D12 {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_user() -> User {
		            User()
		        }
		        let user = LazilyInstantiated<User>(__safeDI_user)
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_38882A8C29DA6D12.self
		            return Screen(user: user.instance)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, screen: screen)
		    }
		}
		""")
		#expect(output.warnings.map(\.formatted) == [])
		let inlineOutput = try await executeSafeDIToolTest(
			swiftFileContent: Self.instanceReadInsideBuilderFixture(seam: false),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(inlineOutput.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_user() -> User {
		            User()
		        }
		        let user = LazilyInstantiated<User>(__safeDI_user)
		        func __safeDI_screen() -> Screen {
		            func __safeDI_detailBuilder() -> Detail {
		                Detail(user: user.instance)
		            }
		            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		            return Screen(detailBuilder: detailBuilder)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, screen: screen)
		    }
		}
		""")
		#expect(inlineOutput.warnings.map(\.formatted) == [])
	}

	// MARK: The Manual's worked example

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_matchesManualsWorkedExample_whenSeamReceivesAndInstantiates() async throws {
		// The Manual's seam section shows a fixture and what SafeDI generates for it; both are read from the Manual, so
		// neither can drift from the tool.
		let manual = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Documentation/Manual.md"), encoding: .utf8)
		let section = try #require(manual.components(separatedBy: "## Generating a dependency tree per module").dropFirst().first)
			.components(separatedBy: "\n#").first ?? ""
		let codeBlocks = section.components(separatedBy: "```swift\n").dropFirst().map { $0.components(separatedBy: "\n```").first ?? "" }
		// The fourth block illustrates the access a parameter is taken at, and is not generated from these fixtures; the
		// two after it show a seam's builder for a hole, which `SafeDIToolSeamBuilderParameterTests` reads.
		#expect(codeBlocks.count == 6)
		let fixture = try #require(codeBlocks.first).replacingOccurrences(of: "// In module Feature.\n", with: "")
		let generated = try #require(codeBlocks.dropFirst().first)
		let callerBlock = try #require(codeBlocks.dropFirst(2).first)
		let supportingTypes = """
		public struct User {
		    public init() {}
		}

		public struct Database {
		    public init() {}
		}

		public struct Logger {
		    public init() {}
		}
		"""
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [fixture, supportingTypes],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + generated)

		// The third block is the call a root in module App generates under the SwiftPM plugin: `Root` holds `user`
		// and `database`, not `logger`. Compared without its leading comment and its indentation.
		let appOutput = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [fixture, supportingTypes]),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContent: [
						"""
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
						""",
						"""
						import Feature

						@Instantiable
						extension User: Instantiable {
						    public static func instantiate() -> User {
						        User()
						    }
						}

						@Instantiable
						extension Database: Instantiable {
						    public static func instantiate() -> Database {
						        Database()
						    }
						}
						""",
					],
					dependencies: ["Feature"],
				),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		let rootCode = try #require(appOutput.modules["App"]).generatedFiles["Root+SafeDI.swift"] ?? ""
		let callLines = rootCode.components(separatedBy: "\n").drop { !$0.contains("func __safeDI_screen() -> Screen {") }.prefix(4)
		let callerLines = callerBlock.components(separatedBy: "\n").drop { $0.hasPrefix("//") }
		#expect(callLines.map { $0.trimmingCharacters(in: .whitespaces) } == callerLines.map { $0.trimmingCharacters(in: .whitespaces) })
	}

	// MARK: Private

	/// The path of `fileName` in `moduleName`, as a diagnostic spells it under `integration`.
	private static func declarationPath(of fileName: String, in moduleName: String, fixtures: [String: FixturePaths], under integration: MultiModuleIntegration) -> String {
		switch integration {
		case .moduleInfo:
			fixtures[moduleName]![fileName]
		case .swiftPackagePlugin:
			NormalizedFilePath(fixtures[moduleName]!.compilerPath(of: fileName)).path
		}
	}

	private static func importBlock(_ moduleName: String) -> String {
		"""
		#if canImport(\(moduleName))
		import \(moduleName)
		#endif
		"""
	}

	private static let userContent = """
	@Instantiable
	public struct User: Instantiable {
	    public init() {}
	}
	"""

	private static let databaseContent = """
	@Instantiable
	public struct Database: Instantiable {
	    public init() {}
	}
	"""

	private static let loggerContent = """
	@Instantiable
	public struct Logger: Instantiable {
	    public init() {}
	}
	"""

	/// A type nested in an internal enum, whose initializer is therefore `internal` however it is spelled. It is
	/// erased to `AnyAnalytics` where it is instantiated, so that the instantiating type's `public` initializer can
	/// take it. The file is named `Analytics.swift`, after the `@Instantiable` type it declares.
	private static func internalAnalyticsContent(receivingToken tokenDeclaration: String, initializerParameter: String) -> String {
		"""
		internal enum Internals {
		    @Instantiable
		    public struct Analytics: Instantiable, AnalyticsProtocol {
		        public init(\(initializerParameter)) {
		            self.token = token
		        }

		        \(tokenDeclaration)
		    }
		}
		"""
	}

	private static let anyAnalyticsContent = """
	public protocol AnalyticsProtocol {}

	public struct AnyAnalytics: AnalyticsProtocol {
	    public init(_ analytics: some AnalyticsProtocol) {}
	}
	"""

	private var filesToDelete: [URL]
}
