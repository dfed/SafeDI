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

/// A seam parameter is as visible as the narrowest type it names, as far as SafeDI can prove it from the declarations it
/// records: a type's own `@Instantiable` declaration, the initializers, `instantiate(…)` and mock methods that take it
/// as a dependency, and a short list of standard types. The generated initializer's widest tier is at the seam type's
/// access, with a narrower tier for each narrower parameter; a required parameter narrower than the seam's type is an
/// error at the seam, and a caller holding a value the tier it can call omits is an error at the caller.
struct SafeDIToolSeamAccessProofTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Fixtures

	/// A public seam `Service` that instantiates `Badge`, whose initializer, at `badgeInitializerAccess`, receives
	/// `receive`; `extraFiles` declare the received type and anything else; `Root` holds `rootHolds`.
	private static func badgeFixture(badgeInitializerAccess: String, receive: String, extraFiles: [String], rootHolds: [String]? = nil) -> [String] {
		let receivedProperty = receive[receive.range(of: " let ")!.upperBound...]
		let label = String(receivedProperty.prefix { $0 != ":" })
		let type = receivedProperty.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
		return [
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
			"""
			@Instantiable
			public struct Badge: Instantiable {
			    \(badgeInitializerAccess)init(\(label): \(type)) {
			        self.\(label) = \(label)
			    }

			    \(receive)
			}
			""",
		] + (rootHolds.map { [seamFixtureType(named: "Root", isRoot: true, declarations: $0.map { "@Instantiated let \($0)" } + ["@Instantiated let service: Service"])] } ?? []) + extraFiles
	}

	/// `Core`, in package `Shop`, which declares the `package` namespace `Rack`, and `Gear`, which does not run SafeDI and
	/// declares `Rack.Shelf` in an extension of it, before `Feature`, which declares `featureFiles` and the
	/// `@Instantiable extension Rack.Shelf` with `shelfExtensionBody`: SafeDI reads `Rack`'s declaration and none of
	/// `Rack.Shelf`'s, so nothing bounds the extension exactly, and it counts as `internal`, raised by the mentions.
	private static func rackShelfModules(shelfExtensionBody: String = "    public static func instantiate() -> Rack.Shelf {\n        Rack.Shelf()\n    }", featureFiles: [String], featureFilesByPath: [String: String] = [:]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: ["package enum Rack {}"]),
			ModuleFixture(name: "Gear", packageName: "Shop", swiftFileContent: ["import Core\n\nextension Rack {\n    public struct Shelf {\n        public init() {}\n    }\n}"], dependencies: ["Core"], runsSafeDI: false),
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: featureFiles.map { "import Core\nimport Gear\n\n" + $0 } + ["import Core\nimport Gear\n\n@Instantiable\nextension Rack.Shelf: Instantiable {\n\(shelfExtensionBody)\n}"],
				swiftFileContentByFilePath: featureFilesByPath.mapValues { "import Core\nimport Gear\n\n" + $0 },
				dependencies: ["Core", "Gear"],
			),
		]
	}

	// MARK: R1: a type's own declaration proves it

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPublicTypeOnPublicTier_whenInternalInitializerReceivesIt() async throws {
		// B1.1, B2.5: `Analytics`'s own declaration proves it `public`, whatever access `Badge`'s initializer has.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.badgeFixture(badgeInitializerAccess: "", receive: "@Received(onlyIfAvailable: true) let analytics: Analytics?", extraFiles: [seamFixtureType(named: "Analytics", declarations: [])], rootHolds: ["analytics: Analytics"]),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let analytics = Analytics()
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_FAC13A1F2502EB27.self
			            return Service(__safeDI_analytics: analytics)
			        }
			        let service: Service = __safeDI_service()
			        self.init(analytics: analytics, service: service)
			    }
			}
			""",
			"Service+SafeDI.swift": generatedFileHeader + """
			extension Service {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_analytics: @autoclosure @escaping () -> Analytics?) {
			        let analytics = LazilyInstantiated<Analytics?>(__safeDI_analytics)
			        let badge = Badge(analytics: analytics.instance)
			        self.init(badge: badge)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_FAC13A1F2502EB27 {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesInternalTier_whenInternalTypeIsReceivedOnlyIfAvailable() async throws {
		// B1.3: `Token`'s own declaration proves it `internal`: the `public` tier passes `nil` for it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.badgeFixture(badgeInitializerAccess: "", receive: "@Received(onlyIfAvailable: true) let token: Token?", extraFiles: ["@Instantiable\nstruct Token: Instantiable {\n    init() {}\n}"], rootHolds: []),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_58FC2EE92E8FE413.self
			            return Service(__safeDI_token: nil)
			        }
			        let service: Service = __safeDI_service()
			        self.init(service: service)
			    }
			}
			""",
			"Service+SafeDI.swift": generatedFileHeader + """
			extension Service {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public init() {
			        self.init(__safeDI_token: nil)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    internal init(__safeDI_token: @autoclosure @escaping () -> Token?) {
			        let token = LazilyInstantiated<Token?>(__safeDI_token)
			        let badge = Badge(token: token.instance)
			        self.init(badge: badge)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_58FC2EE92E8FE413 {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicTierCannotTakeRequiredInternalType() async {
		// B1.2: cause (i), remedies in order.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `session: Session`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Session`'s own `@Instantiable` declaration is `internal`. Declare `Session` `public`; declare `Service` `internal`; build `session` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Service`.
			\(fixtures["Badge.swift"]):7:5: note: `Badge` receives `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.badgeFixture(badgeInitializerAccess: "", receive: "@Received let session: Session", extraFiles: ["@Instantiable\nstruct Session: Instantiable {\n    init() {}\n}"]),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: R4: the members that mention a type prove it

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenEveryMemberMentioningPlainTypeIsNarrower() async {
		// B1.13: cause (ii), every proving declaration listed in source order.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `token: [3 of Int]`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in this module or on a type that receives it is `internal` (`Badge.init(token:)`, `Vault.init(token:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `internal`; build `token` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Service`.
			\(fixtures["Badge.swift"]):7:5: note: `Badge` receives `token: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.badgeFixture(badgeInitializerAccess: "", receive: "@Received let token: [3 of Int]", extraFiles: [
					"@Instantiable\npublic struct Vault: Instantiable {\n    init(token: [3 of Int]) {\n        self.token = token\n    }\n\n    @Received let token: [3 of Int]\n}",
				]),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenOnlyInitializerInInactiveClauseMentionsTypePublicly() async {
		// B1.15, B5.1, R7: of `Badge`'s initializers, only the one SafeDI constructs it with proves; the public one in the
		// inactive clause proves nothing.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `token: [3 of Int]`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in this module or on a type that receives it is `internal` (`Badge.init(token:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `internal`; build `token` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Service`.
			\(fixtures["Badge.swift"]):13:5: note: `Badge` receives `token: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    #if FLAG
					    public init(token: [3 of Int]) {
					        self.token = token
					    }
					    #else
					    init(token: [3 of Int]) {
					        self.token = token
					    }
					    #endif

					    @Received let token: [3 of Int]
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
	mutating func generate_takesTypeOnPublicTier_whenOnlyMockOnlyFakesMockMentionsItPublicly(integration: MultiModuleIntegration) async throws {
		// B1.10, B5.4, B5.7: the public mock of a `mockOnly` fake in `#if DEBUG` is the only public mention of `Token`. Its
		// `token` is a dependency, so the mock proves `Token` `public`, in a release build too, which does not compile the
		// fake: the generated files are the same, and the `public` tier compiles without it.
		func modules(isReleaseConfiguration: Bool) -> [ModuleFixture] {
			let feature = Self.mockConditionFeature(fakeCondition: "DEBUG", featureMockCondition: nil)
			let app = Self.mockConditionApp(appMockCondition: nil)
			return [
				ModuleFixture(name: feature.name, packageName: feature.packageName, swiftFileContent: feature.swiftFileContent, isReleaseConfiguration: isReleaseConfiguration),
				ModuleFixture(name: app.name, packageName: app.packageName, swiftFileContent: app.swiftFileContent, dependencies: app.dependencies, isReleaseConfiguration: isReleaseConfiguration),
			]
		}
		let debugOutput = try await executeSafeDIToolMultiModuleTest(modules: modules(isReleaseConfiguration: false), integration: integration, filesToDelete: &filesToDelete)
		let releaseOutput = try await executeSafeDIToolMultiModuleTest(modules: modules(isReleaseConfiguration: true), integration: integration, filesToDelete: &filesToDelete)
		let seamFile = generatedFileHeader + """
		extension Service {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_token: @autoclosure @escaping () -> Token) {
		        let token = LazilyInstantiated<Token>(__safeDI_token)
		        let badge = Badge(token: token.instance)
		        self.init(badge: badge)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_F2F345803C710CE2 {}
		}
		"""
		switch integration {
		case .moduleInfo:
			#expect(releaseOutput.modules["Feature"]?.generatedFiles == ["Feature.swift": seamFile])
		case .swiftPackagePlugin:
			#expect(releaseOutput.modules["Feature"]?.generatedFiles == ["Service+SafeDI.swift": seamFile])
		}
		#expect(releaseOutput.modules["Feature"]?.generatedFiles == debugOutput.modules["Feature"]?.generatedFiles)
		#expect(releaseOutput.modules["App"]?.generatedFiles == debugOutput.modules["App"]?.generatedFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPlainTypeOnPublicTier_whenPublicMemberMentionsIt() async throws {
		// B1.12: one public mention among narrower ones proves the type `public`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.badgeFixture(badgeInitializerAccess: "", receive: "@Received let token: Token", extraFiles: [
				"public struct Token {\n    public init() {}\n}",
				"@Instantiable\npublic struct Vault: Instantiable {\n    public init(token: Token) {\n        self.token = token\n    }\n\n    @Received let token: Token\n}",
			]),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Service+SafeDI.swift": generatedFileHeader + """
			extension Service {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_token: @autoclosure @escaping () -> Token) {
			        let token = LazilyInstantiated<Token>(__safeDI_token)
			        let badge = Badge(token: token.instance)
			        self.init(badge: badge)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_F2F345803C710CE2 {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesStandardTypesOnPublicTier_whenInternalInitializerRequiresThem() async throws {
		// B2.20: standard types count as `public`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"import Foundation\n\n" + seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
				"""
				import Foundation

				@Instantiable
				public struct Badge: Instantiable {
				    init(launchDate: Date, names: [String], retries: Int) {
				        self.launchDate = launchDate
				        self.names = names
				        self.retries = retries
				    }

				    @Received let launchDate: Date
				    @Received let names: [String]
				    @Received let retries: Int
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Service+SafeDI.swift": generatedFileHeader + """
			#if canImport(Foundation)
			import Foundation
			#endif

			extension Service {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_launchDate: @autoclosure @escaping () -> Date, __safeDI_names: @autoclosure @escaping () -> [String], __safeDI_retries: @autoclosure @escaping () -> Int) {
			        let launchDate = LazilyInstantiated<Date>(__safeDI_launchDate)
			        let names = LazilyInstantiated<[String]>(__safeDI_names)
			        let retries = LazilyInstantiated<Int>(__safeDI_retries)
			        let badge = Badge(launchDate: launchDate.instance, names: names.instance, retries: retries.instance)
			        self.init(badge: badge)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_C4A4DABA7CC5162D {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenRequiredAliasesFulfillingTypeIsUnproven() async {
		// B2.14: D1, an alias's fulfilling type that no recorded member mentions is `internal`.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `session: [3 of Int]`, which `Consumer` receives through its alias `auth` (`fulfilledByDependencyNamed: "session"`), and cannot pass `nil` for it, since it is required. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and no initializer, `instantiate(…)` or mock method SafeDI records mentions it (`Consumer`'s initializer mentions only `any Auth`). Declare `@Received let session: [3 of Int]` on `Screen`, so that its initializer, which the compiler checks, states how visible `[3 of Int]` is (the compiler may then require `Screen`'s initializer, and so the seam, to be narrower); mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Screen` `internal`; receive `auth` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Consumer.swift"]):7:5: note: `Consumer` receives `session: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let consumer: Consumer"]),
					"public protocol Auth {}",
					"""
					@Instantiable
					public struct Consumer: Instantiable {
					    public init(auth: any Auth) {
					        self.auth = auth
					    }

					    @Received(fulfilledByDependencyNamed: "session", ofType: [3 of Int].self) let auth: any Auth
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
	mutating func generate_takesAliasesFulfillingTypeOnPublicTier_whenItsPlainDeclarationIsPublic(integration: MultiModuleIntegration) async throws {
		// B2.14's twin, found by the seam corpus (seeds 714 and 756): `Session`'s own `public` declaration proves it, though
		// only the alias's `ofType:` mentions it, under every integration, including one that keeps only the plain
		// declarations a declaration mentions.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let consumer: Consumer"]),
					"public protocol Auth {}\n\npublic struct Session: Auth {\n    public init() {}\n}",
					"""
					@Instantiable
					public struct Consumer: Instantiable {
					    public init(auth: any Auth) {
					        self.auth = auth
					    }

					    @Received(fulfilledByDependencyNamed: "session", ofType: Session.self) let auth: any Auth
					}
					""",
				]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let fixtures = try #require(output.modules["Feature"]).fixtures
		func seamFile(consumerPath: String) -> String {
			generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_session: @autoclosure @escaping () -> Session) {
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        func __safeDI_consumer() -> Consumer {
			            #sourceLocation(file: "\(consumerPath)", line: 7)
			            let auth: any Auth = session.instance
			            #sourceLocation()
			            return Consumer(auth: auth)
			        }
			        let consumer: Consumer = __safeDI_consumer()
			        self.init(consumer: consumer)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_1E2B55CC1D77755A {}
			}
			"""
		}
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": seamFile(consumerPath: fixtures["Consumer.swift"])])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == ["Screen+SafeDI.swift": seamFile(consumerPath: fixtures.compilerPath(of: "Consumer.swift"))])
		}
	}

	// MARK: R1: extensions

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypeOnPublicTier_whenPublicInitializerRaisesExtensionBasedTypeThatMentionsIt() async throws {
		// B1.8: `Screen`'s public initializer mentions `Shelf`, raising the unspelled extension's bound to `public`, so
		// `Shelf`'s public `instantiate(theme:)` proves `Theme` `public`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let shelf: Shelf"]),
				"""
				public struct Theme {
				    public init() {}
				}

				public struct Shelf {
				    let theme: Theme
				}

				@Instantiable
				extension Shelf: Instantiable {
				    public static func instantiate(theme: Theme) -> Shelf {
				        Shelf(theme: theme)
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_theme: @autoclosure @escaping () -> Theme) {
			        let theme = LazilyInstantiated<Theme>(__safeDI_theme)
			        let shelf: Shelf = Shelf.instantiate(theme: theme.instance)
			        self.init(shelf: shelf)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_BC9F4F791E8F6B4E {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypeOnPublicTier_whenTypeInExtensionOfSeamMentionsIt() async throws {
		// B1.4l: `Helper` is declared inside an extension of `Service`, whose own declaration bounds it: exactly
		// `public`, so its public initializer proves `Theme` `public`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    init(helper: Service.Helper) {
				        self.helper = helper
				    }

				    @Instantiated let helper: Service.Helper
				}

				extension Service {
				    @Instantiable
				    public struct Helper: Instantiable {
				        public init(theme: Theme) {
				            self.theme = theme
				        }

				        @Received let theme: Theme
				    }
				}
				""",
				"public struct Theme {\n    public init() {}\n}",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Service+SafeDI.swift": generatedFileHeader + """
			extension Service {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_theme: @autoclosure @escaping () -> Theme) {
			        let theme = LazilyInstantiated<Theme>(__safeDI_theme)
			        let helper = Service.Helper(theme: theme.instance)
			        self.init(helper: helper)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_BC9F4F791E8F6B4E {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenTypeInUnspelledExtensionOfSeamSpellsNoLevel() async {
		// B1.4l2: cause (vii), the entry's own term.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `theme: [3 of Int]`, which `Service.Helper` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `internal` as far as SafeDI can tell: `Service.Helper`'s initializer, which mentions it, is declared inside an extension of `Service` that spells no access level, and `Helper` spells none. Declare `Helper` `public`, or spell the extension's access level (`public extension Service { … }`); mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `internal`; build `theme` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Service`.
			\(fixtures["Service.swift"]):17:9: note: `Service.Helper` receives `theme: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Service: Instantiable {
					    init(helper: Service.Helper) {
					        self.helper = helper
					    }

					    @Instantiated let helper: Service.Helper
					}

					extension Service {
					    @Instantiable
					    struct Helper: Instantiable {
					        public init(theme: [3 of Int]) {
					            self.theme = theme
					        }

					        @Received let theme: [3 of Int]
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
	mutating func generate_takesSeamInUnspelledExtensionOfNamespaceDeclaredInPlatformBlock() async throws {
		// IF14 (B1.4f): `Checkout` is declared inside a platform block, every clause of which SafeDI reads, so its `public`
		// declaration bounds `Checkout.Service` exactly, and the seam's public tier takes `theme`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				#if canImport(Foundation)
				public enum Checkout {}
				#endif

				extension Checkout {
				    @Instantiable(generateDependencyTree: true)
				    public struct Service: Instantiable {
				        public init(theme: Theme, badge: Badge) {
				            self.theme = theme
				            self.badge = badge
				        }

				        @Received let theme: Theme
				        @Instantiated let badge: Badge
				    }
				}
				""",
				platformConditionedDeclaration("public struct Theme {\n    public init() {}\n}"),
				seamFixtureType(named: "Badge", declarations: []),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Service+SafeDI.swift": generatedFileHeader + """
			extension Checkout.Service {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_theme theme: Theme) {
			        let badge = Badge()
			        self.init(theme: theme, badge: badge)
			    }
			}

			extension Checkout.Service {
			    public enum __safeDI_Checkout_Service_DD923990A48765D6 {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingNamespace_whenItIsPackage() async {
		// IF14 (R6(4)): `Outer`, declared `package` inside a platform block, bounds `Outer.Vault` exactly, so `Service`'s
		// public initializer cannot take `vault`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `vault: Outer.Vault`, which `Service` receives, and cannot pass `nil` for it, since it is required. `Outer.Vault` is `package`: it is declared inside an extension of `Outer`, whose own declaration is `package`. Declare `Outer` `public`; declare `Service` `package`; receive `vault` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Service.swift"]):8:5: note: `Service` receives `vault: Outer.Vault` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						"""
						#if canImport(Foundation)
						package enum Outer {}
						#endif

						extension Outer {
						    @Instantiable
						    public struct Vault: Instantiable {
						        public init() {}
						    }
						}
						""",
						"@Instantiable(generateDependencyTree: true)\npublic struct Service: Instantiable {\n    package init(vault: Outer.Vault, badge: Badge) {\n        self.vault = vault\n        self.badge = badge\n    }\n\n    @Received let vault: Outer.Vault\n    @Instantiated let badge: Badge\n}",
						seamFixtureType(named: "Badge", declarations: []),
					]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesNoMention_whenUnlabeledDefaultValuedMockArgumentNamesType() async throws {
		// B1.26b: an argument bound to no dependency mentions nothing, labeled or not.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.badgeFixture(badgeInitializerAccess: "", receive: "@Received(onlyIfAvailable: true) let configuration: Configuration?", extraFiles: [
				"struct Configuration {\n    init() {}\n}",
				"""
				public struct Settings {
				    public struct Configuration {
				        public init() {}
				    }
				}

				@Instantiable
				extension Settings: Instantiable {
				    public static func instantiate() -> Settings {
				        Settings()
				    }

				    public static func mock(_ configuration: Configuration = .init()) -> Settings {
				        Settings()
				    }
				}
				""",
			]),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Service+SafeDI.swift": generatedFileHeader + """
			extension Service {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public init() {
			        self.init(__safeDI_configuration: nil)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    internal init(__safeDI_configuration: @autoclosure @escaping () -> Configuration?) {
			        let configuration = LazilyInstantiated<Configuration?>(__safeDI_configuration)
			        let badge = Badge(configuration: configuration.instance)
			        self.init(badge: badge)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_80F0B4AC7EFD985F {}
			}
			""",
		])
	}

	// MARK: R6: tiers

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesPublicTierCallingInternalInitializer_whenSeamsOwnInitializerIsNarrowerThanEveryParameter() async throws {
		// B3.7, B3.10: the widest tier is at the seam type's access, whatever its own initializer's.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Screen: Instantiable {
				    init(token: Token, detail: Detail) {
				        self.token = token
				        self.detail = detail
				    }

				    @Received let token: Token
				    @Instantiated let detail: Detail
				}
				""",
				seamFixtureType(named: "Detail", declarations: ["@Received let session: Session"]),
				seamFixtureType(named: "Token", declarations: []),
				seamFixtureType(named: "Session", declarations: []),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: Token", "@Instantiated let session: Session", "@Instantiated let screen: Screen"]),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let token = Token()
			        let session = Session()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_BA2713BBB287D267.self
			            return Screen(__safeDI_token: token, __safeDI_session: session)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(token: token, session: session, screen: screen)
			    }
			}
			""",
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_token token: Token, __safeDI_session: @autoclosure @escaping () -> Session) {
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        let detail = Detail(session: session.instance)
			        self.init(token: token, detail: detail)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_BA2713BBB287D267 {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_chainsThreeTiers_whenParametersAreProvenAtThreeLevels() async throws {
		// B1.4j's chain, R6(1): `flag` is proven `public` by `Service`'s own initializer, `session` and `theme` `package`
		// by their declaration and by `Badge`'s initializer, and `token` `internal` by its declaration: a tier at each
		// level, each wider one passing `nil` for what it omits to the next narrower one, which `App`, in the same
		// package, calls passing what it holds.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"package struct Theme {\n    package init() {}\n}\n\npublic struct Flag {\n    public init() {}\n}",
					"@Instantiable\npackage struct Session: Instantiable {\n    package init() {}\n}",
					"@Instantiable\nstruct Token: Instantiable {\n    init() {}\n}",
					"@Instantiable\npublic struct Badge: Instantiable {\n    package init(session: Session?, theme: Theme?) {\n        self.session = session\n        self.theme = theme\n    }\n\n    @Received(onlyIfAvailable: true) let session: Session?\n    @Received(onlyIfAvailable: true) let theme: Theme?\n}",
					"@Instantiable\npublic struct Tag: Instantiable {\n    init(token: Token?) {\n        self.token = token\n    }\n\n    @Received(onlyIfAvailable: true) let token: Token?\n}",
					"@Instantiable(generateDependencyTree: true)\npublic struct Service: Instantiable {\n    public init(flag: Flag?, badge: Badge, tag: Tag) {\n        self.flag = flag\n        self.badge = badge\n        self.tag = tag\n    }\n\n    @Received(onlyIfAvailable: true) let flag: Flag?\n    @Instantiated let badge: Badge\n    @Instantiated let tag: Tag\n}",
				]),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [
					"""
					import Feature
					import SafeDI

					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    package init(session: Session, theme: LazilyInstantiated<Theme>, flag: Flag, service: Service) {
					        self.session = session
					        self.theme = theme
					        self.flag = flag
					        self.service = service
					    }

					    @Instantiated let session: Session
					    @Instantiated let theme: LazilyInstantiated<Theme>
					    @Instantiated let flag: Flag
					    @Instantiated let service: Service
					}

					@Instantiable
					extension Theme: Instantiable {
					    package static func instantiate() -> Theme {
					        Theme()
					    }
					}

					@Instantiable
					extension Flag: Instantiable {
					    public static func instantiate() -> Flag {
					        Flag()
					    }
					}
					""",
				], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			extension Service {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_flag flag: Flag?) {
			        self.init(__safeDI_flag: flag, __safeDI_session: nil, __safeDI_theme: nil)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    package init(__safeDI_flag flag: Flag?, __safeDI_session: @autoclosure @escaping () -> Session?, __safeDI_theme: @autoclosure @escaping () -> Theme?) {
			        self.init(__safeDI_flag: flag, __safeDI_session: __safeDI_session(), __safeDI_theme: __safeDI_theme(), __safeDI_token: nil)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    internal init(__safeDI_flag flag: Flag?, __safeDI_session: @autoclosure @escaping () -> Session?, __safeDI_theme: @autoclosure @escaping () -> Theme?, __safeDI_token: @autoclosure @escaping () -> Token?) {
			        let session = LazilyInstantiated<Session?>(__safeDI_session)
			        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
			        let token = LazilyInstantiated<Token?>(__safeDI_token)
			        let badge = Badge(session: session.instance, theme: theme.instance)
			        let tag = Tag(token: token.instance)
			        self.init(flag: flag, badge: badge, tag: tag)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_55FE9472957FCF19 {}
			}
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			extension Root {
			    public init() {
			        let session = Session()
			        func __safeDI_theme() -> Theme {
			            Theme.instantiate()
			        }
			        let theme = LazilyInstantiated<Theme>(__safeDI_theme)
			        let flag: Flag = Flag.instantiate()
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_55FE9472957FCF19.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Service(__safeDI_flag: flag, __safeDI_session: session, __safeDI_theme: theme.instance)
			        }
			        let service: Service = __safeDI_service()
			        self.init(session: session, theme: theme, flag: flag, service: service)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicSeamsOwnRequiredReceiveIsNarrower() async {
		// B3.13: the seam's own required `@Received` property narrower than its type.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `session: Session`, which `Service` receives, and cannot pass `nil` for it, since it is required. `Session`'s own `@Instantiable` declaration is `internal`. Declare `Session` `public`; declare `Service` `internal`; receive `session` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Service`.
			\(fixtures["Service.swift"]):8:5: note: `Service` receives `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Service: Instantiable {
					    init(session: Session, badge: Badge) {
					        self.session = session
					        self.badge = badge
					    }

					    @Received let session: Session
					    @Instantiated let badge: Badge
					}
					""",
					"@Instantiable\nstruct Session: Instantiable {\n    init() {}\n}",
					seamFixtureType(named: "Badge", declarations: []),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicSeamsOwnForwardedPropertyIsNarrower() async {
		// B2.2: an own `@Forwarded` property's remedies have no only-if-available form.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `theme: [3 of Int]`, which `Service`'s own initializer takes, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in this module or on a type that receives it is `internal` (`Service.init(theme:badge:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `internal`; or declare the dependency tree on an `internal` type that instantiates `Service`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Service: Instantiable {
					    init(theme: [3 of Int], badge: Badge) {
					        self.theme = theme
					        self.badge = badge
					    }

					    @Forwarded let theme: [3 of Int]
					    @Instantiated let badge: Badge
					}
					""",
					seamFixtureType(named: "Badge", declarations: []),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypeOnPublicTier_whenTypeIsNestedInTypeInExtensionOfSeam() async throws {
		// B1.4t: `Deep` is declared inside an extension of `Service.Helper`, itself bounded by `Service`: exact `public`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    init(deep: Service.Helper.Deep) {
				        self.deep = deep
				    }

				    @Instantiated let deep: Service.Helper.Deep
				}

				extension Service {
				    @Instantiable
				    public struct Helper: Instantiable {
				        public init() {}
				    }
				}

				extension Service.Helper {
				    @Instantiable
				    public struct Deep: Instantiable {
				        public init(theme: Theme) {
				            self.theme = theme
				        }

				        @Received let theme: Theme
				    }
				}
				""",
				"public struct Theme {\n    public init() {}\n}",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Service+SafeDI.swift": generatedFileHeader + """
			extension Service {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_theme: @autoclosure @escaping () -> Theme) {
			        let theme = LazilyInstantiated<Theme>(__safeDI_theme)
			        let deep = Service.Helper.Deep(theme: theme.instance)
			        self.init(deep: deep)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_BC9F4F791E8F6B4E {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsExtensionsModifierAsDefaultOnly_whenTypeInExtensionOfSeamSpellsItsOwnLevel() async throws {
		// B1.4u: an extension's modifier is the default of the declarations inside it, never a cap: `Helper` spells
		// `public` inside an `internal extension Service`, so it is exactly `public`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    init(helper: Service.Helper) {
				        self.helper = helper
				    }

				    @Instantiated let helper: Service.Helper
				}

				internal extension Service {
				    @Instantiable
				    public struct Helper: Instantiable {
				        public init(theme: Theme) {
				            self.theme = theme
				        }

				        @Received let theme: Theme
				    }
				}
				""",
				"public struct Theme {\n    public init() {}\n}",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Service+SafeDI.swift": generatedFileHeader + """
			extension Service {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_theme: @autoclosure @escaping () -> Theme) {
			        let theme = LazilyInstantiated<Theme>(__safeDI_theme)
			        let helper = Service.Helper(theme: theme.instance)
			        self.init(helper: helper)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_BC9F4F791E8F6B4E {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_capsMockAtItsEntrysProof_whenMockMentionsTypeOfDependency() async throws {
		// B1.36b's twin: SafeDI reads `Rack`'s declaration and none of `Rack.Shelf`'s, which `Gear` declares, so nothing raises
		// the extension-based `Rack.Shelf`, its `package` mock proves its dependency-bound `theme` only at `internal`, and
		// `Service`'s tier that takes `theme` is `internal`. `Hub.Theme`, which SafeDI proves only by mentions
		// (`hubTheme(named:declarations:)`), is mentioned by nothing wider, so a mock its entry did not cap would prove it
		// `package`, and that tier `package`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				hubsModule,
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: ["package enum Rack {}"]),
				ModuleFixture(name: "Gear", packageName: "Shop", swiftFileContent: ["import Core\n\nextension Rack {\n    public struct Shelf {\n        public init() {}\n    }\n}"], dependencies: ["Core"], runsSafeDI: false),
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: Self.badgeFixture(badgeInitializerAccess: "", receive: "@Received(onlyIfAvailable: true) let theme: Hub.Theme?", extraFiles: []).map { "import Hubs\n\n" + $0 } + [
						hubTheme(),
						"import Core\nimport Gear\nimport Hubs\n\n@Instantiable\nextension Rack.Shelf: Instantiable {\n    static func instantiate(theme: Hub.Theme) -> Rack.Shelf {\n        Rack.Shelf()\n    }\n\n    package static func mock(theme: Hub.Theme) -> Rack.Shelf {\n        Rack.Shelf()\n    }\n}",
					],
					dependencies: ["Core", "Gear", "Hubs"],
				),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Gear)
		import Gear
		#endif
		#if canImport(Hubs)
		import Hubs
		#endif

		extension Service {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_theme: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    internal init(__safeDI_theme: @autoclosure @escaping () -> Hub.Theme?) {
		        let theme = LazilyInstantiated<Hub.Theme?>(__safeDI_theme)
		        let badge = Badge(theme: theme.instance)
		        self.init(badge: badge)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_C770BA85936CC78A {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_capsMockAtItsEntrysRaisedProof_whenPackageInitializerMentionsExtensionBasedType() async throws {
		// B1.36b: `Rack`'s `package` initializer, which no tree reaches, raises the extension-based `Shelf` to `package`,
		// so `Shelf`'s public mock proves its dependency-bound `theme` at `package`, never at `public`: `Theme` is
		// `package`, and a `public` tier taking it would not compile.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					package struct Theme {
					    package init() {}
					}

					package struct Shelf {
					    let theme: Theme
					}

					@Instantiable
					extension Shelf: Instantiable {
					    static func instantiate(theme: Theme) -> Shelf {
					        Shelf(theme: theme)
					    }

					    public static func mock(theme: Theme) -> Shelf {
					        Shelf(theme: theme)
					    }
					}
					""",
					"@Instantiable\npublic struct Rack: Instantiable {\n    package init(shelf: Shelf) {\n        self.shelf = shelf\n    }\n\n    @Instantiated let shelf: Shelf\n}",
					"@Instantiable\npublic struct Badge: Instantiable {\n    init(theme: Theme?) {\n        self.theme = theme\n    }\n\n    @Received(onlyIfAvailable: true) let theme: Theme?\n}",
					seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
				]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service"])], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + Self.twoTierService])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_5CF188DE6A83E906.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Service()
			        }
			        let service: Service = __safeDI_service()
			        self.init(service: service)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_capsMergedMockAtItsEntrysProof_whenMockOnlyDeclarationSpellsWiderLevel() async throws {
		// B1.37: the `mockOnly` declaration of `Outer.Shelf` spells `public`, but its merged entry is the extension-based
		// declaration of a nested type, which starts at `internal` and nothing raises: the mock's dependency-bound `token`
		// proves `internal`, so the `public` tier passes `nil`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.badgeFixture(badgeInitializerAccess: "", receive: "@Received(onlyIfAvailable: true) let token: Token?", extraFiles: [
				"""
				struct Token {
				    init() {}
				}

				enum Outer {
				    @Instantiable(mockOnly: true)
				    public struct Shelf {
				        let token: Token

				        public static func mock(token: Token = Token()) -> Shelf {
				            Shelf(token: token)
				        }
				    }
				}

				@Instantiable
				extension Outer.Shelf: Instantiable {
				    static func instantiate(token: Token) -> Outer.Shelf {
				        Outer.Shelf(token: token)
				    }
				}
				""",
			]),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Service+SafeDI.swift": generatedFileHeader + """
			extension Service {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public init() {
			        self.init(__safeDI_token: nil)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    internal init(__safeDI_token: @autoclosure @escaping () -> Token?) {
			        let token = LazilyInstantiated<Token?>(__safeDI_token)
			        let badge = Badge(token: token.instance)
			        self.init(badge: badge)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_58FC2EE92E8FE413 {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsGenericParameterAsModuleLevelType_whenGenericDeclarationsMemberNamesIt() async throws {
		// B1.33e: `Cache`'s initializer names its generic parameter `Key`, which the proof reads as the module-level
		// `Key`, whose own `internal` declaration proves it exactly, so the mention raises nothing and `key` is on the
		// `internal` tier alone.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.badgeFixture(badgeInitializerAccess: "", receive: "@Received(onlyIfAvailable: true) let key: Key?", extraFiles: [
				"struct Key {}",
				"""
				@Instantiable(generateMock: true)
				public struct Cache<Key: Hashable>: Instantiable {
				    public init(key: Key) {
				        self.key = key
				    }

				    @Forwarded let key: Key
				}
				""",
			]),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Service+SafeDI.swift"] == generatedFileHeader + """
		extension Service {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_key: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    internal init(__safeDI_key: @autoclosure @escaping () -> Key?) {
		        let key = LazilyInstantiated<Key?>(__safeDI_key)
		        let badge = Badge(key: key.instance)
		        self.init(badge: badge)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_F7E1C338C4CDCECF {}
		}
		""")
	}

	@Test(arguments: [
		// B1.33f: a type declared in the body of a generic type.
		"public struct Box<Key> {\n    @Instantiable\n    public struct Slot: Instantiable {\n        public init(key: Key) {\n            self.key = key\n        }\n\n        @Forwarded let key: Key\n    }\n}",
		// B1.33g: a type declared in a spelled extension of a generic type.
		"public struct Box<Key> {}\n\npublic extension Box {\n    @Instantiable\n    struct Slot: Instantiable {\n        public init(key: Key) {\n            self.key = key\n        }\n\n        @Forwarded let key: Key\n    }\n}",
		// B1.33h: an `@Instantiable` extension of a generic type.
		"public struct Container<Key>: Instantiable {}\n\n@Instantiable(conformsElsewhere: true)\npublic extension Container {\n    static func instantiate(key: Key) -> Container {\n        Container()\n    }\n}",
		// B1.33k: a type declared in an extension of a generic `@Instantiable` type, which bounds it exactly.
		"@Instantiable(generateMock: true)\npublic struct Cache<Key>: Instantiable {\n    public init() {}\n}\n\nextension Cache {\n    @Instantiable(generateMock: true)\n    public struct Inner: Instantiable {\n        public init(key: Key) {\n            self.key = key\n        }\n\n        @Received let key: Key\n    }\n}",
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsGenericParameterAsModuleLevelType_whenGenericParameterClauseInScopeBindsIt(genericDeclaration: String) async throws {
		// B1.33f–h, B1.33k: a member's `key: Key` names the generic parameter of an enclosing type, or of the type an
		// extension extends, which the proof reads as the module-level `Key`, whose `internal` declaration proves it
		// exactly, as for the declaration's own generic parameter (B1.33e).
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.badgeFixture(badgeInitializerAccess: "", receive: "@Received(onlyIfAvailable: true) let key: Key?", extraFiles: ["struct Key {}", genericDeclaration]),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Service+SafeDI.swift"] == generatedFileHeader + """
		extension Service {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_key: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    internal init(__safeDI_key: @autoclosure @escaping () -> Key?) {
		        let key = LazilyInstantiated<Key?>(__safeDI_key)
		        let badge = Badge(key: key.instance)
		        self.init(badge: badge)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_F7E1C338C4CDCECF {}
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_listsEveryProvingDeclaration_whenFirstOneIsCappedByItsOwnType() async {
		// Regression: `Archive`'s public initializer is capped by its internal type, and its file sorts first; every
		// declaration that proves `Key` at `internal` is still listed, `Host`'s too.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `key: [3 of Int]`, which `Archive` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in this module or on a type that receives it is `internal` (`Archive.init(key:)`, `Host.init(key:service:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `internal`; build `key` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Service`.
			\(fixtures["Archive.swift"]):7:5: note: `Archive` receives `key: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let archive: Archive"]),
					"@Instantiable\nstruct Archive: Instantiable {\n    public init(key: [3 of Int]) {\n        self.key = key\n    }\n\n    @Received let key: [3 of Int]\n}",
					"@Instantiable\nstruct Host: Instantiable {\n    init(key: [3 of Int], service: Service) {\n        self.key = key\n        self.service = service\n    }\n\n    @Forwarded let key: [3 of Int]\n    @Instantiated let service: Service\n}",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_listsEveryProvingDeclaration_whenFirstOneIsBoundedByExtension() async {
		// Regression: `Settings.Helper`'s public initializer is capped by `Settings`, and its file sorts first; the cause
		// still lists every declaration that proves `Tone`, rather than explaining the first one's extension.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Seam.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Seam`: its generated `public` initializer, which `Seam`'s `public` access requires, cannot take `tone: [3 of Int]`, which `Settings.Helper` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in this module or on a type that receives it is `internal` (`Settings.Helper.init(tone:)`, `Host.init(tone:seam:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Seam` `internal`; build `tone` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Seam`.
			\(fixtures["Helper.swift"]):8:9: note: `Settings.Helper` receives `tone: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					seamFixtureType(named: "Seam", isSeam: true, declarations: ["@Instantiated let helper: Settings.Helper"]) + "\n\n@Instantiable\nstruct Settings: Instantiable {\n    init() {}\n}",
					"extension Settings {\n    @Instantiable\n    public struct Helper: Instantiable {\n        public init(tone: [3 of Int]) {\n            self.tone = tone\n        }\n\n        @Received let tone: [3 of Int]\n    }\n}",
					"@Instantiable\nstruct Host: Instantiable {\n    init(tone: [3 of Int], seam: Seam) {\n        self.tone = tone\n        self.seam = seam\n    }\n\n    @Forwarded let tone: [3 of Int]\n    @Instantiated let seam: Seam\n}",
				],
				swiftFileContentByFilePath: [:],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: R4 and R6(4): what the proof reads, and the causes the shared formatter words

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_provesParameterFromTypesInsideComposition() async throws {
		// R4: the proof descends into a composition, finding the internal `Auth` there, so the parameter is taken only by
		// an `internal` tier.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.badgeFixture(badgeInitializerAccess: "", receive: "@Received(onlyIfAvailable: true) let auth: (any Auth & Sendable)?", extraFiles: ["protocol Auth {}"]),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Service+SafeDI.swift": generatedFileHeader + """
			extension Service {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public init() {
			        self.init(__safeDI_auth: nil)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    internal init(__safeDI_auth: @autoclosure @escaping () -> (any (Auth & Sendable))?) {
			        let auth = LazilyInstantiated<(any (Auth & Sendable))?>(__safeDI_auth)
			        let badge = Badge(auth: auth.instance)
			        self.init(badge: badge)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_8A0B331F6E66CF9A {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_provesParameterFromTypesInsideDictionary() async throws {
		// R4: the proof descends into a dictionary, finding the internal `Theme` there, so the parameter is taken only by
		// an `internal` tier.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.badgeFixture(badgeInitializerAccess: "", receive: "@Received(onlyIfAvailable: true) let palette: [String: Theme]?", extraFiles: ["struct Theme {}"]),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Service+SafeDI.swift": generatedFileHeader + """
			extension Service {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public init() {
			        self.init(__safeDI_palette: nil)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    internal init(__safeDI_palette: @autoclosure @escaping () -> [String: Theme]?) {
			        let palette = LazilyInstantiated<[String: Theme]?>(__safeDI_palette)
			        let badge = Badge(palette: palette.instance)
			        self.init(badge: badge)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_F1BFEE4E8C26FD16 {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_provesUnreadableParameterTypeByItsMentions_whenParserCannotDescribeIt() async throws {
		// B2.25: SafeDI's parser does not describe an inline array type, so the proof matches it by its spelling, which
		// `Badge`'s `internal` initializer mentions. Not compiled: an inline array needs a newer platform than the
		// suite's.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.badgeFixture(badgeInitializerAccess: "", receive: "@Received(onlyIfAvailable: true) let values: [3 of Int]?", extraFiles: []),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
		)
		#expect(output.dependencyTreeFiles == [
			"Service+SafeDI.swift": generatedFileHeader + """
			extension Service {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public init() {
			        self.init(__safeDI_values: nil)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    internal init(__safeDI_values: @autoclosure @escaping () -> [3 of Int]?) {
			        let values = LazilyInstantiated<[3 of Int]?>(__safeDI_values)
			        let badge = Badge(values: values.instance)
			        self.init(badge: badge)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_41452DBABE69D826 {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorListingInstantiateAndMockProvers_whenEachMentionsTypeAtSameLevel() async {
		// R6(4) cause (ii): `Badge`'s initializer, `Shelf`'s `instantiate(token:)` and `FakeTokenReader`'s mock each prove
		// `Token` at `internal`, and are listed by member.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `token: [3 of Int]`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in this module or on a type that receives it is `internal` (`Badge.init(token:)`, `FakeTokenReader.mock(token:)`, `Shelf.instantiate(token:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `internal`; build `token` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Service`.
			\(fixtures["Badge.swift"]):7:5: note: `Badge` receives `token: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.badgeFixture(badgeInitializerAccess: "", receive: "@Received let token: [3 of Int]", extraFiles: [
					"public struct Shelf {}\n\n@Instantiable\nextension Shelf: Instantiable {\n    static func instantiate(token: [3 of Int]) -> Shelf {\n        Shelf()\n    }\n}",
					"@Instantiable(mockOnly: true)\nstruct FakeTokenReader {\n    @Received let token: [3 of Int]\n\n    static func mock(token: [3 of Int]) -> FakeTokenReader {\n        FakeTokenReader(token: token)\n    }\n}",
				]),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingMockAsLoneProver_whenItsExtensionIsRaisedOnlyToPackage() async {
		// R6(4) cause (vi) through a mock: `Rack.Shelf`'s public mock is the widest mention of `[3 of Int]`, capped at
		// `package`, to which `Cupboard`'s initializer raises the extension-based `Rack.Shelf`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):4:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `theme: [3 of Int]`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `package` as far as SafeDI can tell: `Rack.Shelf`'s `mock(…)`, which mentions it, is declared on an extension that spells no access level, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions `Rack.Shelf` is `package` (`Cupboard.init(shelf:)`). If `Rack.Shelf` can be `public`, declare `Rack` `public` and spell the extension's access level as `@Instantiable(conformsElsewhere: true) public extension Rack.Shelf`, declaring the `Instantiable` conformance on `Rack.Shelf`'s own declaration or in a separate `extension Rack.Shelf: Instantiable {}`, since Swift allows no access level on an extension that declares a conformance, or, if this module declares `Rack.Shelf`, apply `@Instantiable` to its declaration instead; mention `Rack.Shelf` or `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `theme` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Badge.swift"]):10:5: note: `Badge` receives `theme: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.rackShelfModules(
					shelfExtensionBody: "    static func instantiate(theme: [3 of Int]) -> Rack.Shelf {\n        Rack.Shelf()\n    }\n\n    public static func mock(theme: [3 of Int]) -> Rack.Shelf {\n        Rack.Shelf()\n    }",
					featureFiles: [
						"@Instantiable\npublic struct Cupboard: Instantiable {\n    package init(shelf: Rack.Shelf) {\n        self.shelf = shelf\n    }\n\n    @Instantiated let shelf: Rack.Shelf\n}",
						"@Instantiable\npublic struct Badge: Instantiable {\n    init(theme: [3 of Int]) {\n        self.theme = theme\n    }\n\n    @Received let theme: [3 of Int]\n}",
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamIsDeclaredInSpelledExtensionOfNestedType() async {
		// B1.4k, cause (v): a spelled extension of a nested type bounds nothing SafeDI can count, so `Outer.Mid.Service`
		// proves its own initializer's parameter types only at `internal`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):8:5: error: SafeDI cannot generate the dependency tree of `Outer.Mid.Service`: its generated `public` initializer, which `Outer.Mid.Service`'s `public` access requires, cannot take `theme: [3 of Int]`, which `Outer.Mid.Service` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `package` as far as SafeDI can tell: `Outer.Mid.Service`'s initializer, which mentions it, is declared inside an extension of `Outer.Mid`, whose own declaration is `package`. Declare `Outer.Mid` `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Outer.Mid.Service` `package`; receive `theme` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Outer.Mid.Service`.
			\(fixtures["Feature"]!["Service.swift"]):15:9: note: `Outer.Mid.Service` receives `theme: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						"""
						#if canImport(Foundation)
						package enum Outer {
						    public enum Mid {}
						}
						#endif

						public extension Outer.Mid {
						    @Instantiable(generateDependencyTree: true)
						    struct Service: Instantiable {
						        public init(theme: [3 of Int], badge: Badge) {
						            self.theme = theme
						            self.badge = badge
						        }

						        @Received let theme: [3 of Int]
						        @Instantiated let badge: Badge
						    }
						}
						""",
						seamFixtureType(named: "Badge", declarations: []),
					]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenParameterTypeIsInExtensionOfNarrowerRecordedType() async {
		// R6(4) cause (i) for an exact type in an extension: `Settings.Helper` is `package`, capped by `Settings`'s own
		// declaration.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `helper: Settings.Helper`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Settings.Helper` is `package`: it is declared inside an extension of `Settings`, whose own `@Instantiable` declaration is `package`. Declare `Settings` `public`; declare `Service` `package`; build `helper` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Badge.swift"]):7:5: note: `Badge` receives `helper: Settings.Helper` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						"@Instantiable\npackage struct Settings: Instantiable {\n    package init() {}\n}\n\nextension Settings {\n    @Instantiable\n    public struct Helper: Instantiable {\n        public init() {}\n    }\n}",
						"@Instantiable\npublic struct Badge: Instantiable {\n    package init(helper: Settings.Helper) {\n        self.helper = helper\n    }\n\n    @Received let helper: Settings.Helper\n}",
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
					]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenParameterTypeIsDeclaredNarrowerInExtensionOfSeam() async {
		// R6(4) cause (i) for an exact type in an extension: `Service.Helper` spells `package`, and `Service` is public.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `helper: Service.Helper`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Service.Helper` is declared `package`. Declare `Helper` `public`; declare `Service` `package`; build `helper` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Badge.swift"]):7:5: note: `Badge` receives `helper: Service.Helper` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						"@Instantiable(generateDependencyTree: true)\npublic struct Service: Instantiable {\n    public init(badge: Badge) {\n        self.badge = badge\n    }\n\n    @Instantiated let badge: Badge\n}\n\nextension Service {\n    @Instantiable\n    package struct Helper: Instantiable {\n        package init() {}\n    }\n}",
						"@Instantiable\npublic struct Badge: Instantiable {\n    package init(helper: Service.Helper) {\n        self.helper = helper\n    }\n\n    @Received let helper: Service.Helper\n}",
					]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenParameterTypeIsExtensionBasedAndNothingRaisesIt() async {
		// R6(4) cause (iii) for the parameter's own type: the unspelled `@Instantiable extension Rack.Shelf` is `internal`,
		// which `Badge`'s `internal` initializer does not raise.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):4:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `shelf: Rack.Shelf`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Rack.Shelf` is `internal` as far as SafeDI can tell: it is declared `@Instantiable` on an extension that spells no access level, and no initializer, `instantiate(…)` or mock method SafeDI records mentions it more widely. If `Rack.Shelf` can be `public`, declare `Rack` `public` and spell the extension's access level as `@Instantiable(conformsElsewhere: true) public extension Rack.Shelf`, declaring the `Instantiable` conformance on `Rack.Shelf`'s own declaration or in a separate `extension Rack.Shelf: Instantiable {}`, since Swift allows no access level on an extension that declares a conformance, or, if this module declares `Rack.Shelf`, apply `@Instantiable` to its declaration instead; mention `Rack.Shelf` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `internal`; build `shelf` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Service`.
			\(fixtures["Feature"]!["Badge.swift"]):10:5: note: `Badge` receives `shelf: Rack.Shelf` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.rackShelfModules(featureFiles: Self.badgeFixture(badgeInitializerAccess: "", receive: "@Received let shelf: Rack.Shelf", extraFiles: [])),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenParameterTypeIsExtensionBasedAndRaisedOnlyToPackage() async {
		// R6(4) cause (iii) raised, for the parameter's own type: `Badge`'s `package` initializer raises the unspelled
		// `@Instantiable extension Shelf` to `package`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):4:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `shelf: Rack.Shelf`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Rack.Shelf` is `package` as far as SafeDI can tell: it is declared `@Instantiable` on an extension that spells no access level, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `package` (`Badge.init(shelf:)`). If `Rack.Shelf` can be `public`, declare `Rack` `public` and spell the extension's access level as `@Instantiable(conformsElsewhere: true) public extension Rack.Shelf`, declaring the `Instantiable` conformance on `Rack.Shelf`'s own declaration or in a separate `extension Rack.Shelf: Instantiable {}`, since Swift allows no access level on an extension that declares a conformance, or, if this module declares `Rack.Shelf`, apply `@Instantiable` to its declaration instead; mention `Rack.Shelf` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `shelf` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Badge.swift"]):10:5: note: `Badge` receives `shelf: Rack.Shelf` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.rackShelfModules(featureFiles: Self.badgeFixture(badgeInitializerAccess: "package ", receive: "@Received let shelf: Rack.Shelf", extraFiles: [])),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingRaisingMembersInSourceOrder_whenSixPackageMembersRaiseExtensionBasedParameterType() async {
		// R6(4) cause (iii) raised by six members, which the diagnostic names in source order, by file and then by line:
		// `Attic.swift` declares `Frame` above `Drawer`, and `Cabinet.swift` declares `Gauge` above `Easel` above `Crate`,
		// an order that is neither the order of their types' names, in which the proof records them, nor its reverse.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):4:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `shelf: Rack.Shelf`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Rack.Shelf` is `package` as far as SafeDI can tell: it is declared `@Instantiable` on an extension that spells no access level, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `package` (`Frame.init(shelf:)`, `Drawer.init(shelf:)`, `Badge.init(shelf:)`, `Gauge.init(shelf:)`, `Easel.init(shelf:)`, `Crate.init(shelf:)`). If `Rack.Shelf` can be `public`, declare `Rack` `public` and spell the extension's access level as `@Instantiable(conformsElsewhere: true) public extension Rack.Shelf`, declaring the `Instantiable` conformance on `Rack.Shelf`'s own declaration or in a separate `extension Rack.Shelf: Instantiable {}`, since Swift allows no access level on an extension that declares a conformance, or, if this module declares `Rack.Shelf`, apply `@Instantiable` to its declaration instead; mention `Rack.Shelf` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `shelf` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Badge.swift"]):10:5: note: `Badge` receives `shelf: Rack.Shelf` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.rackShelfModules(
					featureFiles: Self.badgeFixture(badgeInitializerAccess: "package ", receive: "@Received let shelf: Rack.Shelf", extraFiles: []),
					featureFilesByPath: [
						"Attic.swift": "@Instantiable\npublic struct Frame: Instantiable {\n    package init(shelf: Rack.Shelf) {\n        self.shelf = shelf\n    }\n\n    @Received let shelf: Rack.Shelf\n}\n\n@Instantiable\npublic struct Drawer: Instantiable {\n    package init(shelf: Rack.Shelf) {\n        self.shelf = shelf\n    }\n\n    @Received let shelf: Rack.Shelf\n}",
						"Cabinet.swift": "@Instantiable\npublic struct Gauge: Instantiable {\n    package init(shelf: Rack.Shelf) {\n        self.shelf = shelf\n    }\n\n    @Received let shelf: Rack.Shelf\n}\n\n@Instantiable\npublic struct Easel: Instantiable {\n    package init(shelf: Rack.Shelf) {\n        self.shelf = shelf\n    }\n\n    @Received let shelf: Rack.Shelf\n}\n\n@Instantiable\npublic struct Crate: Instantiable {\n    package init(shelf: Rack.Shelf) {\n        self.shelf = shelf\n    }\n\n    @Received let shelf: Rack.Shelf\n}",
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenParameterTypeIsInUnspelledExtensionOfAnotherModulesTypeAndRaisedOnlyToPackage() async {
		// R6(4) cause (vi) for the parameter's own type: `Hub.Theme` is declared in an unspelled extension of another
		// module's `Hub`, and `Badge`'s `package` initializer raises it to `package`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `theme: Hub.Theme`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Hub.Theme` is `package` as far as SafeDI can tell: it is declared inside an extension of `Hub`, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `package` (`Badge.init(theme:)`). If `Hub` can be `public`, spell the extension's access level (`public extension Hub { … }`, dropping the modifier on `Theme` that Swift then reports as redundant; the compiler rejects a level wider than `Hub`'s), or declare `Theme` in `Hub`'s body or at top level; mention `Hub.Theme` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `theme` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Badge.swift"]):9:5: note: `Badge` receives `theme: Hub.Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					hubsModule,
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.badgeFixture(badgeInitializerAccess: "package ", receive: "@Received let theme: Hub.Theme", extraFiles: [hubTheme()]).map { "import Hubs\n\n" + $0 }, dependencies: ["Hubs"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: R6: the omission's receivers

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingReceiverInsideNestedSeam_whenOuterSeamsTierOmitsParameterPassedThroughIt() async {
		// R6(3): `Screen`'s tree takes `session` through the nested seam `Internals.Panel`, whose signature carries the
		// receive inside it, so the error names `Helpers.Detail`, not the nested seam. `Session` is `internal`.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `session: Session`, which `Helpers.Detail` receives, and cannot pass `nil` for it, since it is required. `Session` is declared `internal`. Declare `Session` `public`; declare `Screen` `internal`; build `session` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Session.swift"]):1:1: note: `Session` is declared `internal` here.
			\(fixtures["Session.swift"]):1:1-1:1: fixit: public\(" ")
			\(fixtures["Detail.swift"]):8:9: note: `Helpers.Detail` receives `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(panel: AnyPanel) {
					        self.panel = panel
					    }

					    @Instantiated(fulfilledByType: "Internals.Panel", erasedToConcreteExistential: true) let panel: AnyPanel
					}

					public protocol PanelProtocol {}

					#if canImport(Foundation)
					public struct AnyPanel: PanelProtocol {
					    public init(_ panel: some PanelProtocol) {}
					}
					#endif
					""",
					"""
					internal enum Internals {
					    @Instantiable(generateDependencyTree: true)
					    public struct Panel: Instantiable, PanelProtocol {
					        public init(detail: Helpers.Detail) {
					            self.detail = detail
					        }

					        @Instantiated let detail: Helpers.Detail
					    }
					}
					""",
					"""
					internal enum Helpers {
					    @Instantiable
					    public struct Detail: Instantiable {
					        init(session: Session) {
					            self.session = session
					        }

					        @Received let session: Session
					    }
					}
					""",
					"struct Session {}",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_notesEachReceiverOnceInTreeOrder_whenReceiverIsReachedOnTwoPaths() async {
		// R6(3): `Detail`, reached through `Right` and `Left`, is noted once, after `Right`, in the order the tree
		// declares them.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `token: Token`, which `Right` and `Detail` receive, and cannot pass `nil` for it, since it is required. `Token`'s own `@Instantiable` declaration is `internal`. Declare `Token` `public`; declare `Screen` `internal`; build `token` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Right.swift"]):9:5: note: `Right` receives `token: Token` here.
			\(fixtures["Detail.swift"]):7:5: note: `Detail` receives `token: Token` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let right: Right", "@Instantiated let left: Left"]),
					seamFixtureType(named: "Right", declarations: ["@Instantiated let detail: Detail", "@Received let token: Token"]),
					seamFixtureType(named: "Left", declarations: ["@Instantiated let detail: Detail"]),
					seamFixtureType(named: "Detail", declarations: ["@Received let token: Token"]),
					"@Instantiable\nstruct Token: Instantiable {\n    init() {}\n}",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_notesSeamsOwnReceiveAndTreesReceiver_whenBothReceiveOmittedParameter() async {
		// R6(3): the seam's own required `token` and `Right`'s receive of it are one parameter, which both receive: the
		// error names and notes both, the seam's first.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `token: Token`, which `Service` and `Right` receive, and cannot pass `nil` for it, since it is required. `Token` is declared `internal`. Declare `Token` `public`; declare `Service` `internal`; receive `token` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Service`.
			\(fixtures["Token.swift"]):1:1: note: `Token` is declared `internal` here.
			\(fixtures["Token.swift"]):1:1-1:1: fixit: public\(" ")
			\(fixtures["Service.swift"]):8:5: note: `Service` receives `token: Token` here.
			\(fixtures["Right.swift"]):7:5: note: `Right` receives `token: Token` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"@Instantiable(generateDependencyTree: true)\npublic struct Service: Instantiable {\n    init(token: Token, right: Right) {\n        self.token = token\n        self.right = right\n    }\n\n    @Received let token: Token\n    @Instantiated let right: Right\n}",
					"@Instantiable\npublic struct Right: Instantiable {\n    init(token: Token) {\n        self.token = token\n    }\n\n    @Received let token: Token\n}",
					"struct Token {}",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: R5: a caller holding a value the tier it can call omits

	/// `Feature`'s public seam `Service`, whose `Badge` receives `theme` only if available at `badgeInitializerAccess`,
	/// and `App`'s `Shell`, in package `appPackage`, which forwards `theme` and instantiates `Service`. `theme` is the
	/// `package` `Theme` `Feature` declares, which only a module of its package can name, or, when
	/// `hasUnreadableSpelling`, `[3 of Int]`, which SafeDI proves only by the mentions, so a module in another package
	/// can name it while SafeDI proves it `package`.
	private static func providedValueModules(appPackage: String, badgeInitializerAccess: String = "package ", hasUnreadableSpelling: Bool = false, featureFiles: [String] = []) -> [ModuleFixture] {
		let themeType = hasUnreadableSpelling ? unreadableThemeType : "Theme"
		// A type that forwards the `package` `Theme` is no wider, nor is an initializer that takes an `Instantiator` of it.
		let appAccess = hasUnreadableSpelling ? "public" : "package"
		var featureSwiftFiles = hasUnreadableSpelling ? [] : ["package struct Theme {\n    package init() {}\n}"]
		featureSwiftFiles.append("""
		@Instantiable
		public struct Badge: Instantiable {
		    \(badgeInitializerAccess)init(theme: \(themeType)?) {
		        self.theme = theme
		    }

		    @Received(onlyIfAvailable: true) let theme: \(themeType)?
		}
		""")
		featureSwiftFiles.append(seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]))
		return [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: featureSwiftFiles + featureFiles,
			),
			ModuleFixture(
				name: "App",
				packageName: appPackage,
				swiftFileContent: [
					"""
					import Feature
					import SafeDI

					@Instantiable
					\(appAccess) struct Shell: Instantiable {
					    \(appAccess) init(theme: \(themeType), service: Service) {
					        self.theme = theme
					        self.service = service
					    }

					    @Forwarded let theme: \(themeType)
					    @Instantiated let service: Service
					}

					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    \(appAccess) init(shellBuilder: Instantiator<Shell>) {
					        self.shellBuilder = shellBuilder
					    }

					    @Instantiated let shellBuilder: Instantiator<Shell>
					}
					""",
				],
				dependencies: ["Feature"],
			),
		]
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtProvider_whenCallerInAnotherPackageHoldsValueThePublicTierOmits(integration: MultiModuleIntegration) async {
		// B4.6: `Theme` is `package` as far as SafeDI can tell, so `Service`'s `public` tier, the one `App` can call,
		// omits `theme`, which `App`'s `Shell` provides: built inline, `Badge` would be handed it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Shell.swift", in: "App", fixtures, integration)):11:5: error: `Shell` provides `theme: [3 of Int]`, but the `public` initializer SafeDI generated for `Service` in module `Feature`, the narrowest one module `App` can call, does not take it: `Service` takes `theme` only on its `package` initializer, so this call would pass `nil` to `Badge`, which the tree would hand `theme` were it built inline. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `package` (`Badge.init(theme:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `Badge.init(theme:)` to `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `theme` on this path.
			\(Self.path(of: "Badge.swift", in: "Feature", fixtures, integration)):7:5: note: `Badge` receives `theme: [3 of Int]?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.providedValueModules(appPackage: "Other", hasUnreadableSpelling: true), integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtProviderWithoutOfferingToPassPackage_whenCallerInSamePackageHoldsValueOnlyTheInternalTierTakes(integration: MultiModuleIntegration) async {
		// As above, with `App` in `Feature`'s package and `Badge`'s initializer `internal`: `[3 of Int]` is `internal` as
		// far as SafeDI can tell, so only `Service`'s `internal` tier takes `theme`, which no other module can call. Telling
		// SafeDI a package would not help, so the error does not offer it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Shell.swift", in: "App", fixtures, integration)):11:5: error: `Shell` provides `theme: [3 of Int]`, but the `public` initializer SafeDI generated for `Service` in module `Feature`, the narrowest one module `App` can call, does not take it: `Service` takes `theme` only on its `internal` initializer, so this call would pass `nil` to `Badge`, which the tree would hand `theme` were it built inline. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `internal` (`Badge.init(theme:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `Badge.init(theme:)` to `package`; mention `[3 of Int]` in a `package` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `theme` on this path.
			\(Self.path(of: "Badge.swift", in: "Feature", fixtures, integration)):7:5: note: `Badge` receives `theme: [3 of Int]?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.providedValueModules(appPackage: "Shop", badgeInitializerAccess: "", hasUnreadableSpelling: true), integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWhereModuleRefersToProvider_whenProvidersFileCannotBeRead() async {
		// B4.14: `Base`'s `Holder` provides `theme` to the call of `Service`'s `public` tier that `App` emits, and `Base`'s
		// files are gone, as a sandboxed Bazel action hands `App` `Base`'s `.safedi` alone: the error is reported where
		// `App` refers to what leads to the call, and names the provider's module.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):11:5: error: `Holder` in module `Base` provides `theme: [3 of Int]`, but the `public` initializer SafeDI generated for `Service` in module `Feature`, the narrowest one module `App` can call, does not take it: `Service` takes `theme` only on its `package` initializer, so this call would pass `nil` to `Badge`, which the tree would hand `theme` were it built inline. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `package` (`Badge.init(theme:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `Badge.init(theme:)` to `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `theme` on this path.
			\(fixtures["Feature"]!["Badge.swift"]):7:5: note: `Badge` receives `theme: [3 of Int]?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.providedValueModules(appPackage: "Other", hasUnreadableSpelling: true)[0],
					ModuleFixture(
						name: "Base",
						packageName: "Other",
						swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Holder", declarations: ["@Forwarded let theme: \(Self.unreadableThemeType)", "@Instantiated let service: Service"])],
						dependencies: ["Feature"],
						deletesSwiftFilesAfterRunning: true,
					),
					ModuleFixture(
						name: "App",
						packageName: "Other",
						swiftFileContent: ["import Base\nimport Feature\nimport SafeDI\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let holderBuilder: Instantiator<Holder>"])],
						dependencies: ["Feature", "Base"],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPackageTierPassingValue_whenCallerInSamePackageHoldsValue(integration: MultiModuleIntegration) async throws {
		// B4.7, B3.22: the same package reaches the `package` tier, which takes `theme`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.providedValueModules(appPackage: "Shop"), integration: integration, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == Self.generatedFiles(of: "Feature", sourceFile: "Service", Self.twoTierService, under: integration))
		#expect(output.modules["App"]?.generatedFiles == Self.generatedFiles(of: "App", sourceFile: "Shell", """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public init() {
		        func __safeDI_shellBuilder(theme: Theme) -> Shell {
		            func __safeDI_service() -> Service {
		                _ = Service.__safeDI_Service_5CF188DE6A83E906.self
		                return Service(__safeDI_theme: theme)
		            }
		            let service: Service = __safeDI_service()
		            return Shell(theme: theme, service: service)
		        }
		        let shellBuilder = Instantiator<Shell> {
		            __safeDI_shellBuilder(theme: $0)
		        }
		        self.init(shellBuilder: shellBuilder)
		    }
		}
		""", under: integration))
	}

	/// Where `App`'s tree holds `theme` for `Service`'s own only-if-available receive.
	#if canImport(Foundation)
		enum OwnReceiveProvider: CaseIterable, Sendable {
			/// `Shell` forwards it and instantiates `Service`.
			case forwardedByCaller
			/// `Root` instantiates it, then `Service`.
			case instantiatedBeforeSeam
			/// `Root` instantiates `Service`, then it.
			case instantiatedAfterSeam
			/// `Root` instantiates `Service`, then it, which requires `service`: `Service` is built first.
			case instantiatedRequiringSeam
			/// Nothing holds it.
			case none
		}
	#endif

	/// `Feature`'s public seam `Service`, which receives `theme: Hub.Theme?` itself, only if available, on its `package`
	/// initializer, the only declaration that mentions `Hub.Theme` (`hubTheme(declarations:)`), which `Feature` declares,
	/// beside `Badge`, declared `badgeAccess`; and `App`, in package `appPackage`, whose tree holds `theme` as `provider`
	/// says.
	private static func ownReceiveModules(appPackage: String, provider: OwnReceiveProvider, badgeAccess: String = "public") -> [ModuleFixture] {
		let appImports = "import Feature\nimport Hubs\nimport SafeDI\n\n"
		let appFiles: [String] = switch provider {
		case .forwardedByCaller:
			[
				appImports + seamFixtureType(named: "Shell", declarations: ["@Forwarded let theme: Hub.Theme", "@Instantiated let service: Service"]),
				appImports + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shellBuilder: Instantiator<Shell>"]),
			]
		case .instantiatedBeforeSeam:
			[appImports + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let theme: Hub.Theme", "@Instantiated let service: Service"])]
		case .instantiatedAfterSeam, .instantiatedRequiringSeam:
			[appImports + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service", "@Instantiated let theme: Hub.Theme"])]
		case .none:
			[appImports + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service"])]
		}
		return [
			hubsModule,
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				hubTheme(declarations: provider == .instantiatedRequiringSeam ? ["@Received let service: Service"] : []),
				"@Instantiable\n\(badgeAccess) struct Badge: Instantiable {\n    \(badgeAccess) init() {}\n}",
				"""
				import Hubs

				@Instantiable(generateDependencyTree: true)
				public struct Service: Instantiable {
				    package init(theme: Hub.Theme?, badge: Badge) {
				        self.theme = theme
				        self.badge = badge
				    }

				    @Received(onlyIfAvailable: true) let theme: Hub.Theme?
				    @Instantiated let badge: Badge
				}
				""",
			], dependencies: ["Hubs"]),
			ModuleFixture(name: "App", packageName: appPackage, swiftFileContent: appFiles, dependencies: ["Feature", "Hubs"]),
		]
	}

	/// A spelling of a type SafeDI cannot read, so that only the mentions prove it: a module in another package can name it
	/// while SafeDI proves it narrower. A fixture that compiles cannot spell it, which needs a newer Swift and platform than
	/// SafeDI supports, so only fixtures whose run is an error use it.
	private static let unreadableThemeType = "[3 of Int]"

	/// `Service`'s generated initializers for `ownReceiveModules`, without the file header.
	private static let ownReceiveService = """
	#if canImport(Hubs)
	import Hubs
	#endif

	extension Service {
	    /// Code you write and code SafeDI generates can both call this initializer.
	    public init() {
	        self.init(__safeDI_theme: nil)
	    }

	    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
	    package init(__safeDI_theme theme: Hub.Theme?) {
	        let badge = Badge()
	        self.init(theme: theme, badge: badge)
	    }
	}

	extension Service {
	    public enum __safeDI_Service_9D6698F9EB89E77B {}
	}
	"""

	/// The generated files of `module` under `integration`: its one combined file, or, under the SwiftPM plugin, the file
	/// generated beside `sourceFile`, the file that declares the root, whose calls of `Feature`'s seam carry the comment
	/// `integration` adds.
	private static func generatedFiles(of module: String, sourceFile: String, _ code: String, under integration: MultiModuleIntegration) -> [String: String] {
		let code = code.replacingOccurrences(of: #"(_ = Service\.__safeDI_Service_[0-9A-F]+\.self)"#, with: "$1" + integration.seamCallComment(type: "Service", declaringModule: "Feature"), options: .regularExpression)
		return switch integration {
		case .moduleInfo:
			["\(module).swift": generatedFileHeader + code]
		case .swiftPackagePlugin:
			["\(sourceFile)+SafeDI.swift": generatedFileHeader + code]
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases, [OwnReceiveProvider.forwardedByCaller, .instantiatedBeforeSeam, .instantiatedAfterSeam])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtProvider_whenCallerInAnotherPackageHoldsValueForSeamsOwnReceive(integration: MultiModuleIntegration, provider: OwnReceiveProvider) async {
		// B4.31: the `public` tier `App` can call omits `Service`'s own only-if-available `theme`, which `App`'s tree
		// provides, however it holds it: built inline, `Service` would be handed it.
		let (file, line, providerType) = switch provider {
		case .forwardedByCaller: ("Shell.swift", 12, "Shell")
		case .instantiatedBeforeSeam: ("Root.swift", 12, "Root")
		case .instantiatedAfterSeam, .instantiatedRequiringSeam, .none: ("Root.swift", 13, "Root")
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: file, in: "App", fixtures, integration)):\(line):5: error: `\(providerType)` provides `theme: Hub.Theme`, but the `public` initializer SafeDI generated for `Service` in module `Feature`, the narrowest one module `App` can call, does not take it: `Service` receives `theme` itself, only if available, on its `package` initializer, so this call would pass `nil` to `Service`, which would be handed `theme` were its tree built inline. `Hub.Theme` is `package` as far as SafeDI can tell: it is declared inside an extension of `Hub`, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `package` (`Service.init(theme:badge:)`). If `Hub` can be `public`, spell the extension's access level (`public extension Hub { … }`, dropping the modifier on `Theme` that Swift then reports as redundant; the compiler rejects a level wider than `Hub`'s), or declare `Theme` in `Hub`'s body or at top level; mention `Hub.Theme` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `theme` on this path.
			\(Self.path(of: "Service.swift", in: "Feature", fixtures, integration)):10:5: note: `Service` receives `theme: Hub.Theme?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.ownReceiveModules(appPackage: "Other", provider: provider), integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersNoWideningOfSeamsInitializer_whenItsOtherArgumentIsNarrowerThanCallerNeeds() async {
		// B4.31, R6(4)'s gate: `Service`'s own initializer also takes the `package` `Badge`, so widening it to `public`
		// would not compile: the remedy is left out.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Shell.swift"]):12:5: error: `Shell` provides `theme: Hub.Theme`, but the `public` initializer SafeDI generated for `Service` in module `Feature`, the narrowest one module `App` can call, does not take it: `Service` receives `theme` itself, only if available, on its `package` initializer, so this call would pass `nil` to `Service`, which would be handed `theme` were its tree built inline. `Hub.Theme` is `package` as far as SafeDI can tell: it is declared inside an extension of `Hub`, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `package` (`Service.init(theme:badge:)`). If `Hub` can be `public`, spell the extension's access level (`public extension Hub { … }`, dropping the modifier on `Theme` that Swift then reports as redundant; the compiler rejects a level wider than `Hub`'s), or declare `Theme` in `Hub`'s body or at top level; mention `Hub.Theme` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `theme` on this path.
			\(fixtures["Feature"]!["Service.swift"]):10:5: note: `Service` receives `theme: Hub.Theme?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.ownReceiveModules(appPackage: "Other", provider: .forwardedByCaller, badgeAccess: "package"), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilForSeamsOwnOnlyIfAvailableReceiveFromPublicTier_whenCallerInSamePackageHoldsValue(integration: MultiModuleIntegration) async throws {
		// B3.16, B4.31: `Service`'s own only-if-available `theme` is a parameter of its `package` tier, which the `public`
		// tier calls passing `nil`; `App`, in the same package, calls the `package` tier passing `theme`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.ownReceiveModules(appPackage: "Shop", provider: .forwardedByCaller), integration: integration, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == Self.generatedFiles(of: "Feature", sourceFile: "Service", Self.ownReceiveService, under: integration))
		#expect(output.modules["App"]?.generatedFiles == Self.generatedFiles(of: "App", sourceFile: "Root", """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Hubs)
		import Hubs
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public init() {
		        func __safeDI_shellBuilder(theme: Hub.Theme) -> Shell {
		            func __safeDI_service() -> Service {
		                _ = Service.__safeDI_Service_9D6698F9EB89E77B.self
		                return Service(__safeDI_theme: theme)
		            }
		            let service: Service = __safeDI_service()
		            return Shell(theme: theme, service: service)
		        }
		        let shellBuilder = Instantiator<Shell> {
		            __safeDI_shellBuilder(theme: $0)
		        }
		        self.init(shellBuilder: shellBuilder)
		    }
		}
		""", under: integration))
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicTierPassingNothing_whenCallerInAnotherPackageHoldsNothingForSeamsOwnReceive(integration: MultiModuleIntegration) async throws {
		// B4.31: `App` holds no `theme`, so the `public` tier's `nil` is what `Service` would get built inline.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.ownReceiveModules(appPackage: "Other", provider: .none), integration: integration, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == Self.generatedFiles(of: "App", sourceFile: "Root", """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Hubs)
		import Hubs
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_9D6698F9EB89E77B.self
		            return Service()
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		""", under: integration))
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicTierPassingNothing_whenProviderOfSeamsOwnReceiveRequiresSeam(integration: MultiModuleIntegration) async throws {
		// B4.31's dropped edge: `Hub.Theme` requires `service`, so `Service` is built first and passed `nil`, as built
		// inline: no value is dropped.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.ownReceiveModules(appPackage: "Other", provider: .instantiatedRequiringSeam), integration: integration, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == Self.generatedFiles(of: "App", sourceFile: "Root", """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Hubs)
		import Hubs
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_9D6698F9EB89E77B.self
		            return Service()
		        }
		        let service: Service = __safeDI_service()
		        let theme = Hub.Theme(service: service)
		        self.init(service: service, theme: theme)
		    }
		}
		""", under: integration))
	}

	/// `Feature`'s public seam `Service`, whose `Badge` receives `theme: Hub.Theme?` only if available on a `package`
	/// initializer, the only declaration that mentions `Hub.Theme` (`hubTheme(declarations:)`), which `Feature` declares
	/// with `themeReceive`, and `App`'s root, in another package, which instantiates `service` and then `theme`.
	private static func siblingProviderModules(themeReceive: String?) -> [ModuleFixture] {
		[
			hubsModule,
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				hubTheme(declarations: themeReceive.map { [$0] } ?? []),
				"import Hubs\n\n@Instantiable\npublic struct Badge: Instantiable {\n    package init(theme: Hub.Theme?) {\n        self.theme = theme\n    }\n\n    @Received(onlyIfAvailable: true) let theme: Hub.Theme?\n}",
				seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
			], dependencies: ["Hubs"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"import Feature\nimport Hubs\nimport SafeDI\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service", "@Instantiated let theme: Hub.Theme"]),
			], dependencies: ["Feature", "Hubs"]),
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtSiblingProvider_whenProviderIsDeclaredAfterSeam() async {
		// B4.16: `Root` declares `theme` after `service`, but nothing orders `theme` after the call, so the call's leaf,
		// which receives `theme` only if available, is generated after it, as `Badge` would be built inline.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):13:5: error: `Root` provides `theme: Hub.Theme`, but the `public` initializer SafeDI generated for `Service` in module `Feature`, the narrowest one module `App` can call, does not take it: `Service` takes `theme` only on its `package` initializer, so this call would pass `nil` to `Badge`, which the tree would hand `theme` were it built inline. `Hub.Theme` is `package` as far as SafeDI can tell: it is declared inside an extension of `Hub`, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `package` (`Badge.init(theme:)`). If `Hub` can be `public`, spell the extension's access level (`public extension Hub { … }`, dropping the modifier on `Theme` that Swift then reports as redundant; the compiler rejects a level wider than `Hub`'s), or declare `Theme` in `Hub`'s body or at top level; mention `Hub.Theme` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `theme` on this path.
			\(fixtures["Feature"]!["Badge.swift"]):9:5: note: `Badge` receives `theme: Hub.Theme?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.siblingProviderModules(themeReceive: nil), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicTierPassingNothing_whenProviderRequiresSeamItProvidesFor() async throws {
		// B4.13b: `Hub.Theme` requires `service`, so `service` is generated first and the call's leaf, which receives
		// `theme` only if available, is passed `nil`, as `Badge` would be built inline: no value is dropped.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.siblingProviderModules(themeReceive: "@Received let service: Service"), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			#if canImport(Hubs)
			import Hubs
			#endif

			extension Service {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public init() {
			        self.init(__safeDI_theme: nil)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    package init(__safeDI_theme: @autoclosure @escaping () -> Hub.Theme?) {
			        let theme = LazilyInstantiated<Hub.Theme?>(__safeDI_theme)
			        let badge = Badge(theme: theme.instance)
			        self.init(badge: badge)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_93E737BA887EDA11 {}
			}
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Hubs)
			import Hubs
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			extension Root {
			    public init() {
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_93E737BA887EDA11.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Service()
			        }
			        let service: Service = __safeDI_service()
			        let theme = Hub.Theme(service: service)
			        self.init(service: service, theme: theme)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtNestedSeamsTypeAlone_whenOuterSeamInAnotherPackageCallsPackageSeam() async {
		// B3.15 through a seam: `Mid`'s `Outer` cannot construct `Feature`'s `package` seam `Inner`, so the check of every
		// construction reports `Inner`'s type, and `Outer` reports no omission of the `token` that call stands for.
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Inner.swift"]):2:1: error: `Inner` is `package`, so module `Mid`, in another package, cannot construct it in the code SafeDI generates. Make `Inner` `public` to fix.
			\(fixtures["Feature"]!["Inner.swift"]):2:1-2:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						"""
						@Instantiable(generateDependencyTree: true)
						package struct Inner: Instantiable {
						    package init(badge: Badge) {
						        self.badge = badge
						    }

						    @Instantiated let badge: Badge
						}
						""",
						"@Instantiable\npublic struct Badge: Instantiable {\n    package init(token: Token) {\n        self.token = token\n    }\n\n    @Received let token: Token\n}",
						"@Instantiable\npackage struct Token: Instantiable {\n    package init() {}\n}",
					]),
					ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated let inner: Inner"])], dependencies: ["Feature"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtTypeAlone_whenCallerInAnotherPackageCallsPackageSeam() async {
		// B3.15: a `package` seam's widest tier is `package`, so `App`, in another package, reaches none: the check of
		// every construction reports the type with its fix-it, never the initializer SafeDI generates.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):2:1: error: `Service` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Service` `public` to fix.
			\(fixtures["Feature"]!["Service.swift"]):2:1-2:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						"""
						@Instantiable(generateDependencyTree: true)
						package struct Service: Instantiable {
						    package init(badge: Badge) {
						        self.badge = badge
						    }

						    @Instantiated let badge: Badge
						}
						""",
						seamFixtureType(named: "Badge", declarations: []),
					]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Feature\n\n@Instantiable(isRoot: true)\nfinal class Root: Instantiable {\n    init(service: Service) {\n        self.service = service\n    }\n\n    @Instantiated let service: Service\n}"], dependencies: ["Feature"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenTypeInExtensionOfPackageTypeMentionsTypePublicly() async {
		// B1.4v: `Settings.Helper` is bounded by `Settings`'s own `package` declaration, cause (vii) with `Settings`'s
		// term, and never the remedy to spell `public extension Settings`, which Swift rejects.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `theme: [3 of Int]`, which `Settings.Helper` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `package` as far as SafeDI can tell: `Settings.Helper`'s initializer, which mentions it, is declared inside an extension of `Settings`, whose own `@Instantiable` declaration is `package`. Declare `Settings` `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `theme` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Settings.swift"]):13:9: note: `Settings.Helper` receives `theme: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						"""
						@Instantiable
						package struct Settings: Instantiable {
						    package init() {}
						}

						extension Settings {
						    @Instantiable
						    public struct Helper: Instantiable {
						        public init(theme: [3 of Int]) {
						            self.theme = theme
						        }

						        @Received let theme: [3 of Int]
						    }
						}
						""",
						"""
						@Instantiable(generateDependencyTree: true)
						public struct Service: Instantiable {
						    package init(helper: Settings.Helper) {
						        self.helper = helper
						    }

						    @Instantiated let helper: Settings.Helper
						}
						""",
					]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenTypeInExtensionOfTypeAnotherModuleDeclaresIsRaisedOnlyToPackage() async {
		// B1.4r: `Base`'s `Service` is no declaration of `Feature`'s own that could bound `Service.Helper`: it is another
		// module's. `Helper` starts at `internal`, and `Screen`'s `package` initializer raises it to `package`. (B1.4s, two
		// modules whose `.safedi` named no module, went when every `.safedi` came to name its module.)
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `theme: [3 of Int]`, which `Service.Helper` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `package` as far as SafeDI can tell: `Service.Helper`'s initializer, which mentions it, is declared inside an extension of `Service` that spells no access level, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions `Service.Helper` is `package` (`Screen.init(helper:)`). If `Service` can be `public`, spell the extension's access level (`public extension Service { … }`, dropping the modifier on `Helper` that Swift then reports as redundant; the compiler rejects a level wider than `Service`'s), or declare `Helper` in `Service`'s body or at top level; mention `Service.Helper` or `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Screen` `package`; build `theme` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Helper.swift"]):10:9: note: `Service.Helper` receives `theme: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Base", packageName: "Shop", swiftFileContent: [seamFixtureType(named: "Service", declarations: [])]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						"""
						import Base

						extension Service {
						    @Instantiable
						    public struct Helper: Instantiable {
						        public init(theme: [3 of Int]) {
						            self.theme = theme
						        }

						        @Received let theme: [3 of Int]
						    }
						}
						""",
						"@Instantiable(generateDependencyTree: true)\npublic struct Screen: Instantiable {\n    package init(helper: Service.Helper) {\n        self.helper = helper\n    }\n\n    @Instantiated let helper: Service.Helper\n}",
					], dependencies: ["Base"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesNoTierParameter_whenOuterSeamReachesInnerSeamsTierThatOmitsIt() async throws {
		// B4.23, B4.24: `Mid`'s `Shell` reaches the `public` tier of `Base`'s `Service`, which omits `theme`: no tier of
		// `Shell` takes it, so `App`, holding nothing, calls `Shell()`; holding `theme`, it is told.
		let modules = [
			hubsModule,
			ModuleFixture(name: "Base", packageName: "Shop", swiftFileContent: [
				hubTheme(),
				"import Hubs\n\n@Instantiable\npublic struct Badge: Instantiable {\n    package init(theme: Hub.Theme?) {\n        self.theme = theme\n    }\n\n    @Received(onlyIfAvailable: true) let theme: Hub.Theme?\n}",
				seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
			], dependencies: ["Hubs"]),
			ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: ["import Base\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let service: Service"])], dependencies: ["Base", "Hubs"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules + [ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Base\nimport Mid\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shell: Shell"])], dependencies: ["Base", "Hubs", "Mid"])],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Base"]?.generatedFiles == ["Base.swift": generatedFileHeader + """
		#if canImport(Hubs)
		import Hubs
		#endif

		extension Service {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        self.init(__safeDI_theme: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_theme: @autoclosure @escaping () -> Hub.Theme?) {
		        let theme = LazilyInstantiated<Hub.Theme?>(__safeDI_theme)
		        let badge = Badge(theme: theme.instance)
		        self.init(badge: badge)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_93E737BA887EDA11 {}
		}
		"""])
		#expect(output.modules["Mid"]?.generatedFiles == [
			"Mid.swift": generatedFileHeader + """
			#if canImport(Base)
			import Base
			#endif
			#if canImport(Hubs)
			import Hubs
			#endif

			extension Shell {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public init() {
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_93E737BA887EDA11.self // If this line does not compile, compile the code SafeDI generates for module Base into Base: under Bazel, add Base's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Service()
			        }
			        let service: Service = __safeDI_service()
			        self.init(service: service)
			    }
			}

			extension Shell {
			    public enum __safeDI_Shell_CBF29CE484222325 {}
			}
			""",
		])
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Holder.swift"]):12:5: error: `Holder` provides `theme: Hub.Theme`, but no initializer SafeDI generated for `Shell` takes it: `Shell`'s dependency tree calls the `public` initializer SafeDI generated for `Service` in module `Base`, the narrowest one module `Mid` can call, which takes `theme` only on its `package` initializer, so calling it would pass `nil` to `Badge`, which the tree would hand `theme` were it built inline. `Hub.Theme` is `package` as far as SafeDI can tell: it is declared inside an extension of `Hub`, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `package` (`Badge.init(theme:)`). If `Hub` can be `public`, spell the extension's access level (`public extension Hub { … }`, dropping the modifier on `Theme` that Swift then reports as redundant; the compiler rejects a level wider than `Hub`'s), or declare `Theme` in `Hub`'s body or at top level; mention `Hub.Theme` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `theme` on this path.
			\(fixtures["Base"]!["Badge.swift"]):9:5: note: `Badge` receives `theme: Hub.Theme?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: modules + [ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
					"import Base\nimport Hubs\nimport Mid\n\n" + seamFixtureType(named: "Holder", declarations: ["@Forwarded let theme: Hub.Theme", "@Instantiated let shell: Shell"]),
					"import Base\nimport Mid\nimport SafeDI\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let holderBuilder: Instantiator<Holder>"]),
				], dependencies: ["Base", "Hubs", "Mid"])],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesInnerSeamsParametersOnOuterSeamsTiers_whenOuterSeamIsInInnerSeamsPackage() async throws {
		// B3.9, R4: `Mid`'s `Shell` reaches `Base`'s `Service`, in its own package, at the `package` tier, which takes
		// `theme` and `session`; `Shell` proves each over its own module's declarations, `package`, so its `package` tier
		// takes them and its `public` tier passes `nil`. `App`, in the package, passes what it holds; `AppOther`, in
		// another package, holds nothing and calls the `public` tier.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Base", packageName: "Shop", swiftFileContent: [
					"package struct Theme {\n    package init() {}\n}",
					"@Instantiable\npackage struct Session: Instantiable {\n    package init() {}\n}",
					"@Instantiable\npublic struct Badge: Instantiable {\n    package init(theme: Theme?, session: Session?) {\n        self.theme = theme\n        self.session = session\n    }\n\n    @Received(onlyIfAvailable: true) let theme: Theme?\n    @Received(onlyIfAvailable: true) let session: Session?\n}",
					seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
				]),
				ModuleFixture(name: "Mid", packageName: "Shop", swiftFileContent: ["import Base\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let service: Service"])], dependencies: ["Base"]),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [
					"""
					import Base
					import Mid
					import SafeDI

					@Instantiable
					package struct Holder: Instantiable {
					    package init(theme: Theme, session: Session, shell: Shell) {
					        self.theme = theme
					        self.session = session
					        self.shell = shell
					    }

					    @Forwarded let theme: Theme
					    @Instantiated let session: Session
					    @Instantiated let shell: Shell
					}
					""",
					"import Base\nimport Mid\nimport SafeDI\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let holderBuilder: Instantiator<Holder>"]).replacingOccurrences(of: "public init(", with: "package init("),
				], dependencies: ["Base", "Mid"]),
				ModuleFixture(name: "AppOther", packageName: "Other", swiftFileContent: ["import Base\nimport Mid\n\n" + seamFixtureType(named: "OtherRoot", isRoot: true, declarations: ["@Instantiated let shell: Shell"])], dependencies: ["Base", "Mid"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Mid"]?.generatedFiles == [
			"Mid.swift": generatedFileHeader + """
			#if canImport(Base)
			import Base
			#endif

			extension Shell {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public init() {
			        self.init(__safeDI_session: nil, __safeDI_theme: nil)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    package init(__safeDI_session: @autoclosure @escaping () -> Session?, __safeDI_theme: @autoclosure @escaping () -> Theme?) {
			        let session = LazilyInstantiated<Session?>(__safeDI_session)
			        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_4376E198933DD11D.self // If this line does not compile, compile the code SafeDI generates for module Base into Base: under Bazel, add Base's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Service(__safeDI_session: session.instance, __safeDI_theme: theme.instance)
			        }
			        let service: Service = __safeDI_service()
			        self.init(service: service)
			    }
			}

			extension Shell {
			    public enum __safeDI_Shell_4376E198933DD11D {}
			}
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Base)
			import Base
			#endif
			#if canImport(Mid)
			import Mid
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			extension Root {
			    public init() {
			        func __safeDI_holderBuilder(theme: Theme) -> Holder {
			            let session = Session()
			            func __safeDI_shell() -> Shell {
			                _ = Shell.__safeDI_Shell_4376E198933DD11D.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			                return Shell(__safeDI_session: session, __safeDI_theme: theme)
			            }
			            let shell: Shell = __safeDI_shell()
			            return Holder(theme: theme, session: session, shell: shell)
			        }
			        let holderBuilder = Instantiator<Holder> {
			            __safeDI_holderBuilder(theme: $0)
			        }
			        self.init(holderBuilder: holderBuilder)
			    }
			}
			""",
		])
		#expect(output.modules["AppOther"]?.generatedFiles == [
			"AppOther.swift": generatedFileHeader + """
			#if canImport(Base)
			import Base
			#endif
			#if canImport(Mid)
			import Mid
			#endif

			extension OtherRoot {
			    public init() {
			        func __safeDI_shell() -> Shell {
			            _ = Shell.__safeDI_Shell_4376E198933DD11D.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Shell()
			        }
			        let shell: Shell = __safeDI_shell()
			        self.init(shell: shell)
			    }
			}
			""",
		])
	}

	/// `Feature`'s public seam `Service`, whose `Badge` receives `theme: [3 of Int]` and `color: [4 of Int]`, spellings
	/// SafeDI cannot read, only if available on a `package` initializer, and `App`, in another package, with `appFiles`.
	private static func twoOmissionModules(appFiles: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"@Instantiable\npublic struct Badge: Instantiable {\n    package init(theme: [3 of Int]?, color: [4 of Int]?) {\n        self.theme = theme\n        self.color = color\n    }\n\n    @Received(onlyIfAvailable: true) let theme: [3 of Int]?\n    @Received(onlyIfAvailable: true) let color: [4 of Int]?\n}",
				seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: appFiles.map { "import Feature\nimport SafeDI\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// The error `twoOmissionModules`' call of `Service` reports for a value of `label` that `provider` declares at
	/// `location`, and its note.
	private static func omissionError(provider: String, label: String, type: String, at location: String, _ fixtures: [String: FixturePaths]) -> String {
		"""
		\(location): error: `\(provider)` provides `\(label): \(type)`, but the `public` initializer SafeDI generated for `Service` in module `Feature`, the narrowest one module `App` can call, does not take it: `Service` takes `\(label)` only on its `package` initializer, so this call would pass `nil` to `Badge`, which the tree would hand `\(label)` were it built inline. `\(type)` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `package` (`Badge.init(theme:color:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `Badge.init(theme:color:)` to `public`; mention `\(type)` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `\(label)` on this path.
		\(fixtures["Feature"]!["Badge.swift"]):\(label == "theme" ? 8 : 9):5: note: `Badge` receives `\(label): \(type)?` here.
		"""
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorForEachParameter_whenOneCallOmitsTwoParametersCallerHolds() async {
		// B4.30, within one call: `Shell` holds `theme` and `color`, both of which the `public` tier omits.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			Self.omissionError(provider: "Shell", label: "theme", type: "[3 of Int]", at: "\(fixtures["App"]!["Shell.swift"]):12:5", fixtures) + "\n"
				+ Self.omissionError(provider: "Shell", label: "color", type: "[4 of Int]", at: "\(fixtures["App"]!["Shell.swift"]):13:5", fixtures)
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.twoOmissionModules(appFiles: [
					seamFixtureType(named: "Shell", declarations: ["@Forwarded let theme: [3 of Int]", "@Forwarded let color: [4 of Int]", "@Instantiated let service: Service"]),
					seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shellBuilder: Instantiator<Shell>"]),
				]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOnce_whenTwoCallsInOneTreeDropTheSameValue() async {
		// B4.30, within one tree: `Shell`'s own call of `Service` and the one beneath `Holder` would both drop `theme`,
		// which read the same, so the error is reported once.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			Self.omissionError(provider: "Shell", label: "theme", type: "[3 of Int]", at: "\(fixtures["App"]!["Shell.swift"]):12:5", fixtures)
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.twoOmissionModules(appFiles: [
					seamFixtureType(named: "Shell", declarations: ["@Forwarded let theme: [3 of Int]", "@Instantiated let service: Service", "@Instantiated let holder: Holder"]),
					seamFixtureType(named: "Holder", declarations: ["@Instantiated let service: Service"]),
					seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shellBuilder: Instantiator<Shell>"]),
				]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfEachRootInSourceOrder_whenTwoRootsDropValues() async {
		// B4.30, across roots: `ZRoot`'s tree drops `theme` and `ARoot`'s drops `color`; both are reported, in source
		// order, whatever order the roots are generated in.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			Self.omissionError(provider: "Other", label: "color", type: "[4 of Int]", at: "\(fixtures["App"]!["Other.swift"]):11:5", fixtures) + "\n"
				+ Self.omissionError(provider: "Shell", label: "theme", type: "[3 of Int]", at: "\(fixtures["App"]!["Shell.swift"]):11:5", fixtures)
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.twoOmissionModules(appFiles: [
					seamFixtureType(named: "Shell", declarations: ["@Forwarded let theme: [3 of Int]", "@Instantiated let service: Service"]),
					seamFixtureType(named: "ZRoot", isRoot: true, declarations: ["@Instantiated let shellBuilder: Instantiator<Shell>"]),
					seamFixtureType(named: "Other", declarations: ["@Forwarded let color: [4 of Int]", "@Instantiated let service: Service"]),
					seamFixtureType(named: "ARoot", isRoot: true, declarations: ["@Instantiated let otherBuilder: Instantiator<Other>"]),
				]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtOuterSeam_whenItsTreeHoldsItsParameterForInnerSeamsTierThatOmitsIt() async {
		// B4.28: `Mid`'s `Outer` takes `theme` from its callers because `Panel` receives it, and its tree calls `Base`'s
		// `Service` at the `public` tier, which omits it: the error at `Outer` notes `Panel`'s receive, which makes
		// `theme` its parameter, and `Badge`'s, which the call would pass `nil`.
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			"""
			\(fixtures["Mid"]!["Outer.swift"]):3:1: error: `Outer` takes `theme: [3 of Int]?` from its callers, but the `public` initializer SafeDI generated for `Service` in module `Base`, the narrowest one module `Mid` can call, does not take it: `Service` takes `theme` only on its `package` initializer, so this call would pass `nil` to `Badge`, which the tree would hand `theme` were it built inline. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Base` or on a type that receives it is `package` (`Badge.init(theme:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `Badge.init(theme:)` to `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `theme` on this path.
			\(fixtures["Mid"]!["Panel.swift"]):9:5: note: `Panel` receives `theme: [3 of Int]?` here.
			\(fixtures["Base"]!["Badge.swift"]):7:5: note: `Badge` receives `theme: [3 of Int]?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Base", packageName: "Shop", swiftFileContent: [
						"@Instantiable\npublic struct Badge: Instantiable {\n    package init(theme: [3 of Int]?) {\n        self.theme = theme\n    }\n\n    @Received(onlyIfAvailable: true) let theme: [3 of Int]?\n}",
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
					]),
					ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
						"import Base\n\n" + seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated let panel: Panel", "@Instantiated let service: Service"]),
						"import Base\n\n" + seamFixtureType(named: "Panel", declarations: ["@Received(onlyIfAvailable: true) let theme: [3 of Int]?"]),
					], dependencies: ["Base"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingFirstNestedCallBySeamType_whenTwoNestedCallsDropTheSameValue() async {
		// R5(5): `Shell`'s tree calls `ServiceB` and then `ServiceA`, each at a `public` tier that omits `theme`: the
		// error names one call, the first by seam type, whichever the tree meets first.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Holder.swift"]):11:5: error: `Holder` provides `theme: [3 of Int]`, but no initializer SafeDI generated for `Shell` takes it: `Shell`'s dependency tree calls the `public` initializer SafeDI generated for `ServiceA` in module `Base`, the narrowest one module `Mid` can call, which takes `theme` only on its `package` initializer, so calling it would pass `nil` to `Badge`, which the tree would hand `theme` were it built inline. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Mid` or on a type that receives it is `package` (`Badge.init(theme:)`, `Tag.init(theme:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `Badge.init(theme:)` to `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `theme` on this path.
			\(fixtures["Base"]!["Tag.swift"]):7:5: note: `Tag` receives `theme: [3 of Int]?` here.
			\(fixtures["Base"]!["Badge.swift"]):7:5: note: `Badge` receives `theme: [3 of Int]?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Base", packageName: "Shop", swiftFileContent: [
						"@Instantiable\npublic struct Badge: Instantiable {\n    package init(theme: [3 of Int]?) {\n        self.theme = theme\n    }\n\n    @Received(onlyIfAvailable: true) let theme: [3 of Int]?\n}",
						"@Instantiable\npublic struct Tag: Instantiable {\n    package init(theme: [3 of Int]?) {\n        self.theme = theme\n    }\n\n    @Received(onlyIfAvailable: true) let theme: [3 of Int]?\n}",
						seamFixtureType(named: "ServiceA", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
						seamFixtureType(named: "ServiceB", isSeam: true, declarations: ["@Instantiated let tag: Tag"]),
					]),
					ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: ["import Base\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let serviceB: ServiceB", "@Instantiated let serviceA: ServiceA"])], dependencies: ["Base"]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
						"import Base\nimport Mid\n\n" + seamFixtureType(named: "Holder", declarations: ["@Forwarded let theme: [3 of Int]", "@Instantiated let shell: Shell"]),
						"import Base\nimport Mid\nimport SafeDI\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let holderBuilder: Instantiator<Holder>"]),
					], dependencies: ["Base", "Mid"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingNestedCall_whenValueIsDroppedThreeSeamsDeep() async {
		// B4.29, R5(5): `Top`'s `Outer` reaches `Mid`'s `Shell`, whose tree reaches `Base`'s `Service` at a tier that omits
		// `theme`, so neither `Shell` nor `Outer` takes it, and `App`'s `Holder`, which provides it, is told which call
		// drops it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Holder.swift"]):11:5: error: `Holder` provides `theme: [3 of Int]`, but no initializer SafeDI generated for `Outer` takes it: `Outer`'s dependency tree calls the `public` initializer SafeDI generated for `Shell` in module `Mid`, the narrowest one module `Top` can call, which takes `theme` on none of its initializers, so calling it would pass `nil` to `Badge`, which the tree would hand `theme` were it built inline. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Top` or on a type that receives it is `package` (`Badge.init(theme:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `Badge.init(theme:)` to `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `theme` on this path.
			\(fixtures["Base"]!["Badge.swift"]):7:5: note: `Badge` receives `theme: [3 of Int]?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Base", packageName: "Shop", swiftFileContent: [
						"@Instantiable\npublic struct Badge: Instantiable {\n    package init(theme: [3 of Int]?) {\n        self.theme = theme\n    }\n\n    @Received(onlyIfAvailable: true) let theme: [3 of Int]?\n}",
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
					]),
					ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: ["import Base\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let service: Service"])], dependencies: ["Base"]),
					ModuleFixture(name: "Top", packageName: "Other", swiftFileContent: ["import Base\nimport Mid\n\n" + seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated let shell: Shell"])], dependencies: ["Base", "Mid"]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
						"import Base\nimport Top\n\n" + seamFixtureType(named: "Holder", declarations: ["@Forwarded let theme: [3 of Int]", "@Instantiated let outer: Outer"]),
						"import Base\nimport SafeDI\nimport Top\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let holderBuilder: Instantiator<Holder>"]),
					], dependencies: ["Base", "Mid", "Top"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtExtendedType_whenAnotherPackageConstructsTypeInExtensionOfPackageType(integration: MultiModuleIntegration) async {
		// The public-mocks matrix's M1.26: `Settings.Helper` is public, but code naming it names `Settings`, which is
		// `package`: `App`, in another package, is told to widen `Settings` rather than generating code that does not
		// compile.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Settings.swift", in: "Core", fixtures, integration)):4:1: error: `Settings`, which encloses `Settings.Helper`, is `package`, so module `App`, in another package, cannot construct `Settings.Helper` in the code SafeDI generates. Make `Settings` `public` to fix.
			\(Self.path(of: "Settings.swift", in: "Core", fixtures, integration)):4:1-4:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: [
						"""
						public protocol HelperProtocol {}

						@Instantiable
						package struct Settings: Instantiable {
						    package init() {}
						}

						extension Settings {
						    @Instantiable(fulfillingAdditionalTypes: [HelperProtocol.self])
						    public struct Helper: Instantiable, HelperProtocol {
						        public init() {}
						    }
						}
						""",
					]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Core\n\n@Instantiable(isRoot: true)\npublic struct Root: Instantiable {\n    public init(helper: any HelperProtocol) {\n        self.helper = helper\n    }\n\n    @Instantiated let helper: any HelperProtocol\n}"], dependencies: ["Core"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtInitializer_whenCallerInAnotherPackageCallsSeamWithoutSignature() async {
		// B3.21, R6(6): a seam with nothing to build and nothing to pass has no signature, so callers call its own
		// initializer, whose `package` level the check of every construction still reports.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):3:5: error: `Service`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(fixtures["Feature"]!["Service.swift"]):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: ["@Instantiable(generateDependencyTree: true)\npublic struct Service: Instantiable {\n    package init() {}\n}"]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service"])], dependencies: ["Feature"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	/// `Feature`'s public seam `Service`, whose `Badge` receives `theme: Hub.Theme?` only if available on a `package`
	/// initializer, and `Hub.Theme` (`hubTheme(declarations:)`), which receives `service` only if available; and `App`, in
	/// another package, whose root instantiates `service` and `theme`, in the order `themeFirst` says.
	private static func mutualProviderModules(themeFirst: Bool) -> [ModuleFixture] {
		let declarations = ["@Instantiated let service: Service", "@Instantiated let theme: Hub.Theme"]
		return [
			hubsModule,
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				hubTheme(declarations: ["@Received(onlyIfAvailable: true) let service: Service?"]),
				"import Hubs\n\n@Instantiable\npublic struct Badge: Instantiable {\n    package init(theme: Hub.Theme?) {\n        self.theme = theme\n    }\n\n    @Received(onlyIfAvailable: true) let theme: Hub.Theme?\n}",
				seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
			], dependencies: ["Hubs"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"import Feature\nimport Hubs\nimport SafeDI\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: themeFirst ? declarations.reversed() : declarations),
			], dependencies: ["Feature", "Hubs"]),
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtProvider_whenProviderAndSeamReceiveEachOtherOnlyIfAvailableAndSeamIsDeclaredFirst() async {
		// B4.13d, `service` declared first: the call's leaf keeps its soft edge, so `theme` is built first, passed `nil`
		// for `service`, and the leaf would read it, as `Badge` would built inline.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):13:5: error: `Root` provides `theme: Hub.Theme`, but the `public` initializer SafeDI generated for `Service` in module `Feature`, the narrowest one module `App` can call, does not take it: `Service` takes `theme` only on its `package` initializer, so this call would pass `nil` to `Badge`, which the tree would hand `theme` were it built inline. `Hub.Theme` is `package` as far as SafeDI can tell: it is declared inside an extension of `Hub`, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `package` (`Badge.init(theme:)`). If `Hub` can be `public`, spell the extension's access level (`public extension Hub { … }`, dropping the modifier on `Theme` that Swift then reports as redundant; the compiler rejects a level wider than `Hub`'s), or declare `Theme` in `Hub`'s body or at top level; mention `Hub.Theme` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `theme` on this path.
			\(fixtures["Feature"]!["Badge.swift"]):9:5: note: `Badge` receives `theme: Hub.Theme?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.mutualProviderModules(themeFirst: false), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicTierPassingNothing_whenProviderAndSeamReceiveEachOtherOnlyIfAvailableAndProviderIsDeclaredFirst() async throws {
		// B4.13d, `theme` declared first: the call's leaf's soft edge is dropped to keep the cycle open, so `Service` is
		// built first and passed `nil`, as `Badge` would be built inline.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.mutualProviderModules(themeFirst: true), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Hubs)
			import Hubs
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			extension Root {
			    public init() {
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_93E737BA887EDA11.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Service()
			        }
			        let service: Service = __safeDI_service()
			        let theme = Hub.Theme(service: service)
			        self.init(theme: theme, service: service)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_provesTypealiasAndAnotherModulesTypes_whenSeamCarriesThem() async throws {
		// B7.9, B7.10: `Base`'s public `@Instantiable` `Analytics` is proven by its own declaration; its plain `Theme`
		// and its closure typealias `Handler`, a name the proof never descends, by their `package` declarations inside a
		// platform-conditioned block, every clause of which SafeDI reads.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Base", packageName: "Shop", swiftFileContent: [
					seamFixtureType(named: "Analytics", declarations: []),
					platformConditionedDeclaration("package struct Theme {\n    package init() {}\n}\n\npackage typealias Handler = (String) -> Bool"),
				]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"import Base\n\n@Instantiable\npublic struct Badge: Instantiable {\n    package init(analytics: Analytics, theme: Theme?, handler: Handler?) {\n        self.analytics = analytics\n        self.theme = theme\n        self.handler = handler\n    }\n\n    @Received let analytics: Analytics\n    @Received(onlyIfAvailable: true) let theme: Theme?\n    @Received(onlyIfAvailable: true) let handler: Handler?\n}",
					"import Base\n\n" + seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
				], dependencies: ["Base"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Base\nimport Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let service: Service"])], dependencies: ["Base", "Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			#if canImport(Base)
			import Base
			#endif

			extension Service {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_analytics: @autoclosure @escaping () -> Analytics) {
			        self.init(__safeDI_analytics: __safeDI_analytics(), __safeDI_handler: nil, __safeDI_theme: nil)
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    package init(__safeDI_analytics: @autoclosure @escaping () -> Analytics, __safeDI_handler: @autoclosure @escaping () -> Handler?, __safeDI_theme: @autoclosure @escaping () -> Theme?) {
			        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
			        let handler = LazilyInstantiated<Handler?>(__safeDI_handler)
			        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
			        let badge = Badge(analytics: analytics.instance, theme: theme.instance, handler: handler.instance)
			        self.init(badge: badge)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_53DD043875695A26 {}
			}
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Base)
			import Base
			#endif
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let analytics = Analytics()
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_53DD043875695A26.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Service(__safeDI_analytics: analytics)
			        }
			        let service: Service = __safeDI_service()
			        self.init(analytics: analytics, service: service)
			    }
			}
			""",
		])
	}

	// MARK: R8: the mock condition

	/// `Feature`'s public seam `Service`, whose `Badge` requires the plain `Token` on a `package` initializer, and
	/// `FakeTokenReader`, a `mockOnly` fake whose public mock takes `token`, under `#if <fakeCondition>`: the fake's mock is
	/// the only `public` mention of `Token`. `featureMockCondition`, when set, is the condition `Feature`'s
	/// `SafeDIConfiguration.swift` names.
	private static func mockConditionFeature(fakeCondition: String, featureMockCondition: String?) -> ModuleFixture {
		ModuleFixture(
			name: "Feature",
			packageName: "Shop",
			swiftFileContent: [
				platformConditionedDeclaration("public struct Token {\n    public init() {}\n}"),
				"""
				#if \(fakeCondition)
				@Instantiable(mockOnly: true)
				public struct FakeTokenReader {
				    @Received let token: Token

				    public static func mock(token: Token) -> FakeTokenReader {
				        FakeTokenReader(token: token)
				    }
				}
				#endif
				""",
				"@Instantiable\npublic struct Badge: Instantiable {\n    package init(token: Token) {\n        self.token = token\n    }\n\n    @Received let token: Token\n}",
				seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
			],
			swiftFileContentByFilePath: featureMockCondition.map { ["SafeDIConfiguration.swift": "#SafeDIConfiguration(mockConditionalCompilation: \"\($0)\")"] } ?? [:],
			mockConditionalCompilation: featureMockCondition,
		)
	}

	/// `App`, in another package, whose `Shell` forwards `token` and instantiates `Service`. `appMockCondition`, when set,
	/// is the condition `App`'s `SafeDIConfiguration.swift` names.
	private static func mockConditionApp(appMockCondition: MockCondition?) -> ModuleFixture {
		let configuration = appMockCondition.map { mockCondition in
			"#SafeDIConfiguration(mockConditionalCompilation: \(mockCondition.conditionalCompilation.map { "\"\($0)\"" } ?? "nil"))"
		}
		return ModuleFixture(
			name: "App",
			packageName: "Other",
			swiftFileContent: [
				"import Feature\nimport SafeDI\n\n" + seamFixtureType(named: "Shell", declarations: ["@Forwarded let token: Token", "@Instantiated let service: Service"]),
				"import Feature\nimport SafeDI\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shellBuilder: Instantiator<Shell>"]),
			],
			swiftFileContentByFilePath: configuration.map { ["SafeDIConfiguration.swift": $0] } ?? [:],
			dependencies: ["Feature"],
			mockConditionalCompilation: appMockCondition?.conditionalCompilation,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtCallingDependency_whenCallersMockConditionDiffersFromSeamModules() async {
		// B5.6: under the SwiftPM plugin `App` computes `Service`'s signature from `Feature`'s files as it parsed them,
		// under its own mock condition, `TESTING`, while `Feature` reads them under `DEBUG`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Shell.swift", in: "App", fixtures, .swiftPackagePlugin)):12:5: error: `App` calls the initializer SafeDI generated for `Service` in module `Feature`, whose signature SafeDI computes from `Feature`'s declarations as `Feature` reads them, mock-only declarations under `Feature`'s mock condition included. `Feature` guards its mocks with `DEBUG` and `App` with `TESTING`, so `App` cannot read them as `Feature` does. Use the same `mockConditionalCompilation` in both modules.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [Self.mockConditionFeature(fakeCondition: "DEBUG", featureMockCondition: nil), Self.mockConditionApp(appMockCondition: MockCondition("TESTING"))],
				integration: .swiftPackagePlugin,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamsPublicTier_whenCallerSharesSeamModulesConfiguredMockCondition() async throws {
		// B5.6a: both modules name `TESTING` in their own `SafeDIConfiguration.swift`, so `App` reads `Feature`'s fake as
		// `Feature` does, and its public mock proves `Token` `public` in both.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [Self.mockConditionFeature(fakeCondition: "TESTING", featureMockCondition: "TESTING"), Self.mockConditionApp(appMockCondition: MockCondition("TESTING"))],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Service+SafeDI.swift": generatedFileHeader + """
			extension Service {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_token: @autoclosure @escaping () -> Token) {
			        let token = LazilyInstantiated<Token>(__safeDI_token)
			        let badge = Badge(token: token.instance)
			        self.init(badge: badge)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_F2F345803C710CE2 {}
			}
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			extension Root {
			    public init() {
			        func __safeDI_shellBuilder(token: Token) -> Shell {
			            func __safeDI_service() -> Service {
			                _ = Service.__safeDI_Service_F2F345803C710CE2.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
			                return Service(__safeDI_token: token)
			            }
			            let service: Service = __safeDI_service()
			            return Shell(token: token, service: service)
			        }
			        let shellBuilder = Instantiator<Shell> {
			            __safeDI_shellBuilder(token: $0)
			        }
			        self.init(shellBuilder: shellBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtCallingDependency_whenSeamModulesConfiguredMockConditionDiffersFromCallersDefault() async {
		// B5.6b: `Feature` names `TESTING`; `App` declares no configuration, so it guards its mocks with `DEBUG`, and
		// would not see `Feature`'s fake, which proves `Token` `public` for `Feature`: computed from `App`'s reading,
		// `Service` would have no tier `App` could call.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Shell.swift", in: "App", fixtures, .swiftPackagePlugin)):12:5: error: `App` calls the initializer SafeDI generated for `Service` in module `Feature`, whose signature SafeDI computes from `Feature`'s declarations as `Feature` reads them, mock-only declarations under `Feature`'s mock condition included. `Feature` guards its mocks with `TESTING` and `App` with `DEBUG`, so `App` cannot read them as `Feature` does. Use the same `mockConditionalCompilation` in both modules.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [Self.mockConditionFeature(fakeCondition: "TESTING", featureMockCondition: "TESTING"), Self.mockConditionApp(appMockCondition: nil)],
				integration: .swiftPackagePlugin,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtCallingDependency_whenCallerGuardsItsMocksWithNoCondition() async {
		// R8: a configuration that guards mocks with no condition is a spelling of its own, which `DEBUG` is not.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Shell.swift", in: "App", fixtures, .swiftPackagePlugin)):12:5: error: `App` calls the initializer SafeDI generated for `Service` in module `Feature`, whose signature SafeDI computes from `Feature`'s declarations as `Feature` reads them, mock-only declarations under `Feature`'s mock condition included. `Feature` guards its mocks with `DEBUG` and `App` with no condition, so `App` cannot read them as `Feature` does. Use the same `mockConditionalCompilation` in both modules.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [Self.mockConditionFeature(fakeCondition: "DEBUG", featureMockCondition: nil), Self.mockConditionApp(appMockCondition: MockCondition(nil))],
				integration: .swiftPackagePlugin,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamsPublicTier_whenCallerReadsSeamModulesModuleInfoUnderAnotherMockCondition() async throws {
		// R8: `App` reads `Feature`'s `.safedi`, which holds `Feature`'s declarations as `Feature` read them, under
		// `TESTING`, so `App`'s own `DEBUG` decides nothing.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [Self.mockConditionFeature(fakeCondition: "TESTING", featureMockCondition: "TESTING"), Self.mockConditionApp(appMockCondition: nil)],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			extension Service {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_token: @autoclosure @escaping () -> Token) {
			        let token = LazilyInstantiated<Token>(__safeDI_token)
			        let badge = Badge(token: token.instance)
			        self.init(badge: badge)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_F2F345803C710CE2 {}
			}
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			extension Root {
			    public init() {
			        func __safeDI_shellBuilder(token: Token) -> Shell {
			            func __safeDI_service() -> Service {
			                _ = Service.__safeDI_Service_F2F345803C710CE2.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			                return Service(__safeDI_token: token)
			            }
			            let service: Service = __safeDI_service()
			            return Shell(token: token, service: service)
			        }
			        let shellBuilder = Instantiator<Shell> {
			            __safeDI_shellBuilder(token: $0)
			        }
			        self.init(shellBuilder: shellBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoMockConditionDifference_whenOnlyDependencysRootCallsSeamOfModuleWithAnotherMockCondition() async throws {
		// R8: `Feature`'s `FeatureRoot` calls `Service`, but `App` generates only its own roots, so no tree `App` generates
		// calls the seam.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						seamFixtureType(named: "Theme", declarations: []),
						seamFixtureType(named: "Badge", declarations: ["@Received let theme: Theme"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
						seamFixtureType(named: "FeatureRoot", isRoot: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let service: Service"]),
					],
					swiftFileContentByFilePath: ["SafeDIConfiguration.swift": "#SafeDIConfiguration(mockConditionalCompilation: \"TESTING\")"],
					mockConditionalCompilation: "TESTING",
				),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [])], dependencies: ["Feature"]),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"FeatureRoot+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			// SafeDI generates FeatureRoot's init() only in Feature, the module that declares FeatureRoot. If FeatureRoot() does not compile, add the SafeDI plugin to the target that declares FeatureRoot.
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif


			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtFirstCallingDependencyInSourceOrder_whenTwentyTypesCallSeamOfModuleWithAnotherMockCondition() async {
		// R8: one error per seam, at the first dependency in source order that calls it, whichever the walk meets first.
		let callerNames = (0..<20).map { "Caller" + ($0 < 10 ? "0" : "") + String($0) }
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Caller00.swift", in: "App", fixtures, .swiftPackagePlugin)):12:5: error: `App` calls the initializer SafeDI generated for `Service` in module `Feature`, whose signature SafeDI computes from `Feature`'s declarations as `Feature` reads them, mock-only declarations under `Feature`'s mock condition included. `Feature` guards its mocks with `DEBUG` and `App` with `TESTING`, so `App` cannot read them as `Feature` does. Use the same `mockConditionalCompilation` in both modules.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.mockConditionFeature(fakeCondition: "DEBUG", featureMockCondition: nil),
					ModuleFixture(
						name: "App",
						packageName: "Other",
						swiftFileContent: callerNames.map { "import Feature\nimport SafeDI\n\n" + seamFixtureType(named: $0, declarations: ["@Forwarded let token: Token", "@Instantiated let service: Service"]) }
							+ ["import Feature\nimport SafeDI\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: callerNames.map { "@Instantiated let \($0.lowercased())Builder: Instantiator<\($0)>" })],
						swiftFileContentByFilePath: ["SafeDIConfiguration.swift": "#SafeDIConfiguration(mockConditionalCompilation: \"TESTING\")"],
						dependencies: ["Feature"],
						mockConditionalCompilation: "TESTING",
					),
				],
				integration: .swiftPackagePlugin,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Generic declarations

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generateMock_takesForwardedGenericParameter_whenMockedTypeIsGeneric() async throws {
		// B1.33c: a generic mocked type generates and compiles as it did before seams, its forwarded `key: Key` a
		// parameter of `mock()` typed by its own generic parameter.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Cache<Key: Hashable>: Instantiable {
				    public init(key: Key, clock: Clock) {
				        self.key = key
				        self.clock = clock
				    }

				    @Forwarded let key: Key
				    @Received let clock: Clock
				}
				""",
				seamFixtureType(named: "Clock", declarations: []),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Cache+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Cache {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            clock: (() -> Clock)? = nil
			        ) {
			            self.clock = clock
			        }

			        let clock: (() -> Clock)?
			    }

			    static func mock(
			        key: Key,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Cache {
			        let clock = if let safeDIBuilder = safeDIOverrides.clock { safeDIBuilder() } else { Clock() }
			        return Cache(key: key, clock: clock)
			    }
			}
			#endif
			""",
		])
	}

	// MARK: R8: the callers' view

	/// `Service`, whose `Badge` receives `receive` on a `package` initializer, and `Token`, a plain public type with an
	/// unspelled `@Instantiable` extension, under a target graph that names the module, with `Vault`, whose public
	/// initializer mentions `Token`, in a directory the module's configuration adds.
	/// `public enum Rack`, and `Rack`'s nested types `names`, declared in the clause of `#if FLAG` the tool, given no
	/// conditions, skips, with an `@Instantiable` extension of each: SafeDI reads `Rack`'s declaration and none of the nested
	/// types', so nothing bounds those extensions exactly, and only the mentions prove the types.
	private static func extensionBasedTypesNestedInRack(_ names: [String]) -> [String] {
		["public enum Rack {}\n\n#if FLAG\nextension Rack {\n" + names.map { "    public struct \($0) {}\n" }.joined() + "}\n#endif"]
			+ names.map { "@Instantiable\nextension Rack.\($0): Instantiable {\n    public static func instantiate() -> Rack.\($0) {\n        Rack.\($0)()\n    }\n}" }
	}

	private static func extensionBasedTokenMentionedInAdditionalDirectory(receive: String) -> (swiftFileContent: [String], additionalDirectorySwiftFileContent: [String]) {
		(
			swiftFileContent: [
				"#SafeDIConfiguration(\n    additionalDirectoriesToInclude: [\"$ADDITIONAL_DIRECTORY\"]\n)",
				seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
				"@Instantiable\npublic struct Badge: Instantiable {\n    package init(token: \(receive.components(separatedBy: ": ").last!)) {\n        self.token = token\n    }\n\n    \(receive)\n}",
			] + extensionBasedTypesNestedInRack(["Token"]),
			additionalDirectorySwiftFileContent: [
				"@Instantiable\npublic struct Vault: Instantiable {\n    public init(token: Rack.Token) {\n        self.token = token\n    }\n\n    @Received let token: Rack.Token\n}",
			],
		)
	}

	@Test(arguments: ["@Received(onlyIfAvailable: true) let token: Rack.Token?", "@Received let token: Rack.Token"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingUnseenProver_whenAdditionalDirectoryDeclarationRaisesExtensionBasedType(receive: String) async {
		// B6.5b: `Vault`'s public initializer raises the extension-based `Rack.Token` to `public` in this module's view,
		// which sees the added directory, and not in the callers', which do not: the seam names `Vault`, the first
		// declaration the callers cannot see among those that prove `Rack.Token`, whether the receive is optional or
		// required.
		let fixture = Self.extensionBasedTokenMentionedInAdditionalDirectory(receive: receive)
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: the initializer SafeDI generates for it depends on `Vault`, which is declared in a directory this module's `#SafeDIConfiguration` adds, and the modules that call that initializer cannot see that declaration, so their calls would not match the initializer. Declare `Vault` in a file of this module, or of a module it depends on.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: fixture.swiftFileContent,
				additionalDirectorySwiftFileContent: fixture.additionalDirectorySwiftFileContent,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				pluginTargetGraph: { inputSwiftFilePaths in
					PluginTargetGraph(
						target: PluginTargetGraph.Target(moduleName: "Feature", packageID: "shop", sourceFilePaths: inputSwiftFilePaths, dependencyModuleNames: []),
						dependencyTargets: [],
					)
				},
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingProverOfParametersCallersFailOn_whenCallersFailOnTwoParameters() async {
		// R8: the callers, who cannot see the added directory, prove `Rack.Token` and `Rack.Key` only `package`, so their
		// computation of `Service` fails on both required parameters at once. The seam names `Vault`, which proves those
		// two, and not `Atlas`, which comes first but proves only `map`, whose optional parameter the callers take.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: the initializer SafeDI generates for it depends on `Vault`, which is declared in a directory this module's `#SafeDIConfiguration` adds, and the modules that call that initializer cannot see that declaration, so their calls would not match the initializer. Declare `Vault` in a file of this module, or of a module it depends on.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"#SafeDIConfiguration(\n    additionalDirectoriesToInclude: [\"$ADDITIONAL_DIRECTORY\"]\n)",
					seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
					"@Instantiable\npublic struct Badge: Instantiable {\n    package init(token: Rack.Token, key: Rack.Key, map: Rack.Map?) {\n        self.token = token\n        self.key = key\n        self.map = map\n    }\n\n    @Received let token: Rack.Token\n    @Received let key: Rack.Key\n    @Received(onlyIfAvailable: true) let map: Rack.Map?\n}",
				] + Self.extensionBasedTypesNestedInRack(["Token", "Key", "Map"]),
				additionalDirectorySwiftFileContent: [
					"@Instantiable\npublic struct Atlas: Instantiable {\n    public init(map: Rack.Map) {\n        self.map = map\n    }\n\n    @Received let map: Rack.Map\n}",
					"@Instantiable\npublic struct Vault: Instantiable {\n    public init(token: Rack.Token, key: Rack.Key) {\n        self.token = token\n        self.key = key\n    }\n\n    @Received let token: Rack.Token\n    @Received let key: Rack.Key\n}",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				pluginTargetGraph: { inputSwiftFilePaths in
					PluginTargetGraph(
						target: PluginTargetGraph.Target(moduleName: "Feature", packageID: "shop", sourceFilePaths: inputSwiftFilePaths, dependencyModuleNames: []),
						dependencyTargets: [],
					)
				},
			)
		}
	}

	// MARK: R9: a type's plain declaration proves it

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesHoleOfPackageProtocolOnPackageTier_whenSeamsOwnInitializerAndTheTypesItBuildsAreInternal(integration: MultiModuleIntegration) async throws {
		// F4, F5: `FeedService`'s own `package` declaration proves it, in a file without a SafeDI marker, so the seam's
		// `package` tier takes the hole's builder while the seam's own initializer and `FeedStore` stay `internal`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.feedModules(), integration: integration, filesToDelete: &filesToDelete)
		let feedFile = generatedFileHeader + Self.importLines("SharedModule") + """
		extension FeedScreen {
		    @frozen public enum SafeDIScope_FeedService {
		        case service(service_Values)

		        public struct service_Values {
		            package let shared: SharedThing
		            internal let store: FeedStore
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package convenience init(__safeDI_shared shared: SharedThing, __safeDI_feedServiceBuilder: @escaping (SafeDIScope_FeedService) -> FeedService) {
		        func __safeDI_store() -> FeedStore {
		            let formatter = FeedFormatter()
		            return FeedStore(shared: shared, formatter: formatter)
		        }
		        let store: FeedStore = __safeDI_store()
		        let service: FeedService = __safeDI_feedServiceBuilder(.service(SafeDIScope_FeedService.service_Values(shared: shared, store: store)))
		        self.init(shared: shared, store: store, service: service)
		    }
		}

		extension FeedScreen {
		    public enum __safeDI_FeedScreen_3DBB8F75AF60AC87 {}
		}
		"""
		let pluginComment = integration.seamCallComment(type: "FeedScreen", declaringModule: "FeedModule")
		let appFile = generatedFileHeader + Self.importLines("FeedModule").dropLast() + Self.importLines("SharedModule") + """
		extension Root {
		    public convenience init() {
		        let shared = SharedThing()
		        func __safeDI_feed() -> FeedScreen {
		            _ = FeedScreen.__safeDI_FeedScreen_3DBB8F75AF60AC87.self\(pluginComment)
		            func __safeDI_feedServiceBuilder_FeedScreen(_ scope: FeedScreen.SafeDIScope_FeedService) -> FeedService {
		                switch scope {
		                case let .service(scope):
		                    let shared = scope.shared
		                    let service: FeedService = AppFeedService(shared: shared)
		                    return service
		                }
		            }
		            return FeedScreen(__safeDI_shared: shared, __safeDI_feedServiceBuilder: __safeDI_feedServiceBuilder_FeedScreen)
		        }
		        let feed: FeedScreen = __safeDI_feed()
		        self.init(shared: shared, feed: feed)
		    }
		}
		"""
		#expect(output.modules["FeedModule"]?.generatedFiles == [integration == .moduleInfo ? "FeedModule.swift" : "FeedScreen+SafeDI.swift": feedFile])
		#expect(output.modules["App"]?.generatedFiles == [integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": appFile])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtSeamWithNoteAtDeclaration_whenPackageSeamsHoleIsInternalProtocolPackageInitializerMentions(integration: MultiModuleIntegration) async {
		// F4, F7: `FeedService`'s own `internal` declaration proves it, whatever the seam's `package` initializer, which the
		// compiler rejects, spells: SafeDI reports the seam before the compiler runs, with a fix-it at the declaration.
		await assertThrowsMultiModuleError(inModule: "FeedModule", diagnostics: { fixtures in
			let feedServicePath = Self.path(of: "FeedService.swift", in: "FeedModule", fixtures, integration)
			return """
			\(Self.path(of: "FeedScreen.swift", in: "FeedModule", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `FeedScreen`: its generated `package` initializer, which `FeedScreen`'s `package` access requires, cannot take `feedServiceBuilder: @escaping (SafeDIScope_FeedService) -> FeedService`, the builder for `FeedScreen`'s `service: FeedService`, which no @Instantiable declaration that module `FeedModule` can see fulfills. `FeedService` is declared `internal`. Declare `FeedService` `package`; declare `FeedScreen` `internal`; declare an @Instantiable type that fulfills `FeedService` in module `FeedModule` or a module it lists among its SafeDI dependencies, so `FeedScreen`’s tree builds it; or declare the dependency tree on an `internal` type that instantiates `FeedScreen`.
			\(feedServicePath):1:1: note: `FeedService` is declared `internal` here.
			\(feedServicePath):1:1-1:1: fixit: package 
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.feedModules(feedServiceDeclaration: "protocol FeedService {\n    func headlines() -> [String]\n}", seamInitializerAccess: "package "),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesReceivedTypeOnPublicTier_whenAnotherModuleDeclaresItsProtocolPublicInFileWithoutSafeDIMarker(integration: MultiModuleIntegration) async throws {
		// F4: `Core` declares `Theme` alone, which none of its own declarations mentions: under the plugin the run reads
		// `Core`'s file because `Badge` mentions `Theme`, while a `.safedi` records only the declarations of `Core`'s that
		// only its package can name, so under `.moduleInfo` SafeDI reads no declaration of the `public` `Theme`, counts it
		// as `public` all the same, and names it in the comment.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Kit", swiftFileContentByFilePath: ["Theme.swift": "public protocol Theme {}"]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"import Core\n\n@Instantiable\npublic struct Badge: Instantiable {\n    init(theme: any Theme) {\n        self.theme = theme\n    }\n\n    @Received let theme: any Theme\n}",
					seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
				], dependencies: ["Core"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == [integration == .moduleInfo ? "Feature.swift" : "Service+SafeDI.swift": generatedFileHeader + Self.importLines("Core") + """
		extension Service {
		\(Self.unreadTypeComment(["Theme"], integration))    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_theme: @autoclosure @escaping () -> any Theme) {
		        let theme = LazilyInstantiated<any Theme>(__safeDI_theme)
		        let badge = Badge(theme: theme.instance)
		        self.init(badge: badge)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_BC9F4F791E8F6B4E {}
		}
		"""])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingBothModules_whenTwoModulesTheSeamSeesDeclareTypeAtDifferentLevels(integration: MultiModuleIntegration) async {
		// F4: `Core` declares `Theme` `package` and `Other` `public`; SafeDI cannot tell which one a mention names, and takes
		// the narrower. Under the plugin it reads both; a `.safedi` records only the declarations only the module's package
		// can name, so under `.moduleInfo` it reads `Core`'s alone, and has no `Other.Theme` to suggest.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let corePath = Self.path(of: "Theme.swift", in: "Core", fixtures, integration)
			let declarationsAndRemedies = switch integration {
			case .moduleInfo:
				"`Theme` is declared `package` in module `Core`. Declare `Theme` `public` in module `Core`;"
			case .swiftPackagePlugin:
				"`Theme` is declared `package` in module `Core` and `public` in module `Other`, and SafeDI takes the narrower. Declare `Theme` `public` in module `Core`; spell the type with its module where it is mentioned (`Other.Theme`), so that it names that module's declaration;"
			}
			return """
			\(Self.path(of: "Service.swift", in: "Feature", fixtures, integration)):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `theme: any Theme`, which `Badge` receives, and cannot pass `nil` for it, since it is required. \(declarationsAndRemedies) declare `Service` `package`; build `theme` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(corePath):1:1: note: `Theme` is declared `package` here.
			\(corePath):1:1-1:8: fixit: public
			\(Self.path(of: "Badge.swift", in: "Feature", fixtures, integration)):10:5: note: `Badge` receives `theme: any Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.themeInTwoModules(mention: "Theme"), integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypeOnPublicTier_whenMentionSpellsModuleWhosePublicDeclarationItNames(integration: MultiModuleIntegration) async throws {
		// F4: spelled `Other.Theme`, the mention names `Other`'s `public` declaration alone.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.themeInTwoModules(mention: "Other.Theme"), integration: integration, filesToDelete: &filesToDelete)
		// Split for Swift 6.2 on Linux, which times out type-checking chains like this one.
		let expectedFeatureFileName = integration == .moduleInfo ? "Feature.swift" : "Service+SafeDI.swift"
		let expectedFeatureFile: String = [generatedFileHeader, String(Self.importLines("Core").dropLast()), Self.importLines("Other"), """
		extension Service {
		\(Self.unreadTypeComment(["Other.Theme"], integration))    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_theme: @autoclosure @escaping () -> any Other.Theme) {
		        let theme = LazilyInstantiated<any Other.Theme>(__safeDI_theme)
		        let badge = Badge(theme: theme.instance)
		        self.init(badge: badge)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_C026E16A44F7FB2E {}
		}
		"""].joined()
		#expect(output.modules["Feature"]?.generatedFiles == [expectedFeatureFileName: expectedFeatureFile])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypeOnPublicTier_whenAnotherFileOfSeamsModuleDeclaresPrivateTypeOfItsName(integration: MultiModuleIntegration) async throws {
		// F4: `Helper.swift`'s `private struct Theme` names nothing another file mentions, so `Badge`'s `Theme` is `Core`'s.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Kit", swiftFileContentByFilePath: ["Theme.swift": "public protocol Theme {}"]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Badge.swift": "import Core\n\n@Instantiable\npublic struct Badge: Instantiable {\n    init(theme: any Theme) {\n        self.theme = theme\n    }\n\n    @Received let theme: any Theme\n}",
					"Service.swift": seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
					"Helper.swift": "private struct Theme {}\n\nfunc themeCount() -> Int {\n    _ = Theme()\n    return 1\n}",
				], dependencies: ["Core"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == [integration == .moduleInfo ? "Feature.swift" : "Service+SafeDI.swift": generatedFileHeader + Self.importLines("Core") + """
		extension Service {
		\(Self.unreadTypeComment(["Theme"], integration))    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_theme: @autoclosure @escaping () -> any Theme) {
		        let theme = LazilyInstantiated<any Theme>(__safeDI_theme)
		        let badge = Badge(theme: theme.instance)
		        self.init(badge: badge)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_BC9F4F791E8F6B4E {}
		}
		"""])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesForwardedTypeOnPublicTier_whenUnspelledMockOnlyExtensionMocksPublicClass(integration: MultiModuleIntegration) async throws {
		// EOU-4: the README's unspelled `@Instantiable(mockOnly: true) extension User` is bounded by `User`'s own `public`
		// declaration, so the seam's `public` tier takes the `user` it forwards.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.profileModules(seamAttribute: "@Instantiable(generateDependencyTree: true)", userDeclaration: Self.publicUser), integration: integration, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == [integration == .moduleInfo ? "Feature.swift" : "ProfileView+SafeDI.swift": generatedFileHeader + """
		extension ProfileView {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public convenience init(__safeDI_user user: User) {
		        let store = ProfileStore()
		        self.init(user: user, store: store)
		    }
		}

		extension ProfileView {
		    public enum __safeDI_ProfileView_38882A8C29DA6D12 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesForwardedType_whenUnspelledMockOnlyExtensionMocksTypeDeclaredInPlatformBlock() async throws {
		// IF15 (EOU-4): `User` is declared inside a platform block, every clause of which SafeDI reads, so its own `public`
		// declaration bounds the unspelled `mockOnly` extension, which needs no spelled level.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.profileModules(seamAttribute: "@Instantiable(generateDependencyTree: true)", userDeclaration: platformConditionedDeclaration(Self.publicUser)), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension ProfileView {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public convenience init(__safeDI_user user: User) {
		        let store = ProfileStore()
		        self.init(user: user, store: store)
		    }
		}

		extension ProfileView {
		    public enum __safeDI_ProfileView_38882A8C29DA6D12 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesReceivedProtocolOnPackageTier_whenDependencyDeclaresItPublicBesideInstantiableAndNothingThereMentionsIt() async throws {
		// BZ-2: `Core`'s `public protocol Theme` shares a file with `ThemeService`, and no declaration of `Core` mentions it.
		// A run that writes a `.safedi` without a target graph cannot tell what its dependents will mention, so it keeps
		// every declaration another module can name, and `Feature`'s `package` seam proves `Theme` from it.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.themeBesideInstantiableModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		// Split for Swift 6.2 on Linux, which times out type-checking chains like this one.
		let expectedFeatureFile: String = [generatedFileHeader, String(Self.importLines("Core").dropLast()), Self.importLines("SafeDI"), """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_theme theme: Theme) {
		        let store = Store()
		        self.init(theme: theme, store: store)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_FE0EC2F5EC57A9C9 {}
		}
		"""].joined()
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": expectedFeatureFile])
		// Split for Swift 6.2 on Linux, which times out type-checking the single expression.
		let expectedAppFile: String = [generatedFileHeader, String(Self.importLines("Core").dropLast()), String(Self.importLines("Feature").dropLast()), Self.importLines("SafeDI"), """
		extension Root {
		    public init() {
		        let theme: Theme = ThemeProvider()
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_FE0EC2F5EC57A9C9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen(__safeDI_theme: theme)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(theme: theme, screen: screen)
		    }
		}
		"""].joined()
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": expectedAppFile])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorCountingOnlyMentionsTiedToParameter_whenDependencysPublicInitializerMentionsTypeSafeDICannotRead() async {
		// BZ-2: SafeDI cannot read `[3 of Int]`'s spelling, so only mentions prove it. `Painter`'s `public` initializer in
		// `Core` mentions it, but nothing ties that mention to `Screen`'s parameter, so only `Screen`'s own
		// `internal` initializer proves it, and the sentence says which mentions count.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):4:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `package` initializer, which `Screen`'s `package` access requires, cannot take `theme: [3 of Int]`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `internal` (`Screen.init(theme:store:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `[3 of Int]` in a `package` initializer, `instantiate(…)` or mock method SafeDI records; declare `Screen` `internal`; receive `theme` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Screen.swift"]):11:5: note: `Screen` receives `theme: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Pkg", swiftFileContentByFilePath: [
						"Painter.swift": "import SafeDI\n\n@Instantiable\npublic final class Painter: Instantiable {\n    public init(theme: [3 of Int]) {\n        self.theme = theme\n    }\n\n    @Received let theme: [3 of Int]\n}",
					]),
					ModuleFixture(name: "Feature", packageName: "Pkg", swiftFileContentByFilePath: ["Screen.swift": Self.themeScreen.replacingOccurrences(of: ": Theme", with: ": [3 of Int]")], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsOnlyConstructionOfInternalType_whenNarrowingTypeWhosePublicInitializerMentionedTypeOfUnspelledMockOnlyExtension() async throws {
		// X-5, the Xcode example's shape: `NoteStorage`'s `public` initializer was the only mention of `User`, which only an
		// unspelled `mockOnly` extension declares `@Instantiable`. Making `NoteStorage` `internal` leaves `User` proven by
		// its own `public struct` declaration, so the seam still takes `user`, and the app's construction of `NoteStorage`
		// is the one error.
		let subproject = ModuleFixture(name: "Subproject", packageName: "Notes", swiftFileContentByFilePath: [
			"User.swift": """
			import Foundation
			import SafeDI

			public struct User: Codable, Equatable, Hashable, Sendable {
			    public init(name: String) {
			        self.name = name
			    }

			    public let name: String
			}

			@Instantiable(mockOnly: true)
			extension User {
			    public static func mock() -> User {
			        User(name: "Mock User")
			    }
			}
			""",
			"NoteStorage.swift": """
			import SafeDI

			@Instantiable
			final class NoteStorage: Instantiable {
			    public init(user: User) {
			        self.user = user
			    }

			    @Received private let user: User
			}
			""",
			"ProfileScreen.swift": """
			import SafeDI

			@Instantiable(generateDependencyTree: true)
			package struct ProfileScreen: Instantiable {
			    init(user: User, store: ProfileStore) {
			        self.user = user
			        self.store = store
			    }

			    @Received private let user: User
			    @Instantiated private let store: ProfileStore
			}

			@Instantiable
			final class ProfileStore: Instantiable {
			    init(user: User) {
			        self.user = user
			    }

			    @Received private let user: User
			}
			""",
		])
		let subprojectOutput = try await executeSafeDIToolMultiModuleTest(modules: [subproject], integration: .moduleInfo, filesToDelete: &filesToDelete)
		// Split for Swift 6.2 on Linux, which times out type-checking chains like this one.
		let expectedSubprojectFile: String = [generatedFileHeader, String(Self.importLines("Foundation").dropLast()), Self.importLines("SafeDI"), """
		extension ProfileScreen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_user user: User) {
		        let store = ProfileStore(user: user)
		        self.init(user: user, store: store)
		    }
		}

		extension ProfileScreen {
		    public enum __safeDI_ProfileScreen_EFFD1BCD9A5EF54D {}
		}
		"""].joined()
		#expect(subprojectOutput.modules["Subproject"]?.generatedFiles == ["Subproject.swift": expectedSubprojectFile])
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let noteStoragePath = fixtures["Subproject"]!["NoteStorage.swift"]
			return """
			\(noteStoragePath):4:1: error: `NoteStorage` is `internal`, so this module, which SafeDI cannot tell is in the same package, cannot construct it in the code SafeDI generates. Make `NoteStorage` `package` to fix, which needs both modules compiled with one package name (`SWIFT_PACKAGE_NAME` in an Xcode project), or `public` if the two modules are in different packages.
			\(noteStoragePath):4:1-4:1: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					subproject,
					ModuleFixture(name: "App", packageName: "Notes", swiftFileContent: [
						"import SafeDI\nimport Subproject\n\n" + seamFixtureType(named: "NotesApp", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let loggedInViewBuilder: Instantiator<LoggedInView>"]),
						"import SafeDI\nimport Subproject\n\n@Instantiable\nfinal class LoggedInView: Instantiable {\n    init(user: User, noteStorage: NoteStorage) {\n        self.user = user\n        self.noteStorage = noteStorage\n    }\n\n    @Forwarded let user: User\n    @Instantiated let noteStorage: NoteStorage\n}",
					], dependencies: ["Subproject"], omitsModuleName: true, omitsPackageName: true),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingDeclaringModule_whenPublicSeamReceivesProtocolAnotherModuleDeclaresPackage(integration: MultiModuleIntegration) async {
		// F4: `Core`'s `package` declaration of `Theme` proves it, and the text names the module that declares it.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let corePath = Self.path(of: "Theme.swift", in: "Core", fixtures, integration)
			return """
			\(Self.path(of: "Service.swift", in: "Feature", fixtures, integration)):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `theme: any Theme`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Theme` is declared `package` in module `Core`. Declare `Theme` `public` in module `Core`; declare `Service` `package`; build `theme` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(corePath):1:1: note: `Theme` is declared `package` here.
			\(corePath):1:1-1:8: fixit: public
			\(Self.path(of: "Badge.swift", in: "Feature", fixtures, integration)):9:5: note: `Badge` receives `theme: any Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": "package protocol Theme {}"]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						"import Core\n\n@Instantiable\npublic struct Badge: Instantiable {\n    init(theme: any Theme) {\n        self.theme = theme\n    }\n\n    @Received let theme: any Theme\n}",
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
					], dependencies: ["Core"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingExtendedTypesPlainDeclaration_whenTypeInExtensionOfExtensionBasedTypeIsNarrowerThanSeam() async {
		// R9 part 6: `Outer`'s `@Instantiable` extension is bounded by its own `package` declaration, which bounds the type an
		// extension of `Outer` declares too.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `inner: Outer.Inner`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Outer.Inner` is `package`: it is declared inside an extension of `Outer`, whose own declaration is `package`. Declare `Outer` `public`; declare `Service` `package`; build `inner` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Badge.swift"]):7:5: note: `Badge` receives `inner: Outer.Inner` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"package final class Outer {\n    init() {}\n}\n\n@Instantiable\nextension Outer: Instantiable {\n    public static func instantiate() -> Outer {\n        Outer()\n    }\n}\n\nextension Outer {\n    @Instantiable\n    public final class Inner: Instantiable {\n        public init() {}\n    }\n}",
					"@Instantiable\npublic struct Badge: Instantiable {\n    init(inner: Outer.Inner) {\n        self.inner = inner\n    }\n\n    @Received let inner: Outer.Inner\n}",
					seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorListingProverCappedByPlainDeclaration_whenOnlyInstantiateOfPackageTypeMentionsTypeSafeDICannotRead() async {
		// R9 part 6: `Outer.instantiate(token:)`, spelled `public`, is capped by `Outer`'s own `package` declaration, so it proves
		// `[3 of Int]`, whose spelling SafeDI cannot read, only `package`.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `token: [3 of Int]`, which `Outer`'s `instantiate(…)` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in this module or on a type that receives it is `package` (`Outer.instantiate(token:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `token` inside the tree; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Outer.swift"]):7:36: note: `Outer` receives `token: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"package final class Outer {\n    init() {}\n}\n\n@Instantiable\nextension Outer: Instantiable {\n    public static func instantiate(token: [3 of Int]) -> Outer {\n        Outer()\n    }\n}",
					"@Instantiable(generateDependencyTree: true)\npublic struct Service: Instantiable {\n    init(outer: Outer) {\n        self.outer = outer\n    }\n\n    @Instantiated let outer: Outer\n}",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: R4: a member an entry SafeDI proves only by mentions caps

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingCarriersUnspelledExtension_whenOnlyInitializerOfTypeInExtensionOfAnotherModulesTypeMentionsTypeSafeDICannotRead() async {
		// `[3 of Int]` is mentioned only by the `public` initializer of `Hub.Theme`, which an unspelled extension of another
		// module's `Hub` bounds at `internal`, and which only `Badge`'s `internal` initializer mentions: the lone prover is
		// capped by that extension, and nothing raises it.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `count: [3 of Int]`, which `Hub.Theme` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `internal` as far as SafeDI can tell: `Hub.Theme` is declared inside an extension of `Hub` that spells no access level, which SafeDI counts as `internal`, since it reads `Hub`'s access only from a declaration of `Hub` in the same module that is outside every extension, or inside an extension of a type it reads the same way, so `Hub.Theme`'s initializer proves its parameter types only at `internal`. If `Hub` can be `public`, spell the extension's access level (`public extension Hub { … }`, dropping the modifier on `Theme` that Swift then reports as redundant; the compiler rejects a level wider than `Hub`'s), or declare `Theme` in `Hub`'s body or at top level; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `internal`; build `count` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Service`.
			\(fixtures["Feature"]!["Theme.swift"]):10:9: note: `Hub.Theme` receives `count: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					hubsModule,
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
						"import Hubs\n\n@Instantiable\npublic struct Badge: Instantiable {\n    init(theme: Hub.Theme) {\n        self.theme = theme\n    }\n\n    @Instantiated let theme: Hub.Theme\n}",
						hubTheme(declarations: ["@Received let count: \(Self.unreadableThemeType)"]),
					], dependencies: ["Hubs"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingCarriersSpelledExtensionOfNestedType_whenOnlyInitializerOfRaisedTypeInThatExtensionMentionsTypeSafeDICannotRead() async {
		// `[3 of Int]` is mentioned only by the `public` initializer of `Hub.Mid.Carrier`, declared in a `public` extension of
		// `Hub.Mid`, which `Gear` declares in an extension of another module's `Hub` and SafeDI reads no declaration of: the
		// extension of a nested type bounds nothing SafeDI can count, so `Carrier` starts at `internal`, and `Badge`'s
		// `package` initializer raises it to `package`, which caps the lone prover. The extension spells its level, which the
		// explanation says.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `count: [3 of Int]`, which `Hub.Mid.Carrier` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `package` as far as SafeDI can tell: `Hub.Mid.Carrier`'s initializer, which mentions it, is declared inside an extension of `Hub.Mid`, a nested type, whose spelled access level bounds nothing SafeDI can count, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions `Hub.Mid.Carrier` is `package` (`Badge.init(carrier:)`). Declare `Carrier` in `Hub.Mid`'s body or at top level; mention `Hub.Mid.Carrier` or `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `count` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Carrier.swift"]):11:9: note: `Hub.Mid.Carrier` receives `count: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					hubsModule,
					ModuleFixture(name: "Gear", packageName: "Shop", swiftFileContent: ["import Hubs\n\nextension Hub {\n    public enum Mid {}\n}"], dependencies: ["Hubs"], runsSafeDI: false),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
						"import Gear\nimport Hubs\n\n@Instantiable\npublic struct Badge: Instantiable {\n    package init(carrier: Hub.Mid.Carrier) {\n        self.carrier = carrier\n    }\n\n    @Instantiated let carrier: Hub.Mid.Carrier\n}",
						"import Gear\nimport Hubs\n\npublic extension Hub.Mid {\n    @Instantiable\n    final class Carrier: Instantiable {\n        public init(count: \(Self.unreadableThemeType)) {\n            self.count = count\n        }\n\n        @Received let count: \(Self.unreadableThemeType)\n    }\n}",
					], dependencies: ["Hubs", "Gear"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingCarriersSpelledExtensionOfTopLevelType_whenOnlyInitializerOfRaisedTypeInThatExtensionMentionsTypeSafeDICannotRead() async {
		// `[3 of Int]` is mentioned only by the `public` initializer of `Hub.Carrier`, declared `package` in an `internal`
		// extension of another module's `Hub`: SafeDI counts the extension's level with `Carrier`'s own, so `Carrier` starts
		// at `internal`, and `Badge`'s `package` initializer raises it to `package`, which caps the lone prover. The
		// extension spells its level, which the explanation says. (Swift warns that `package` conflicts with the
		// extension's default access, and makes `Carrier` `package`.)
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `count: [3 of Int]`, which `Hub.Carrier` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `package` as far as SafeDI can tell: `Hub.Carrier`'s initializer, which mentions it, is declared inside an extension of `Hub` that spells its access level, which SafeDI counts with `Carrier`'s own, since it reads `Hub`'s access only from a declaration of `Hub` in the same module, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions `Hub.Carrier` is `package` (`Badge.init(carrier:)`). If `Hub` can be `public`, spell the extension's access level (`public extension Hub { … }`, dropping the modifier on `Carrier` that Swift then reports as redundant; the compiler rejects a level wider than `Hub`'s), or declare `Carrier` in `Hub`'s body or at top level; mention `Hub.Carrier` or `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `count` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Carrier.swift"]):10:9: note: `Hub.Carrier` receives `count: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					hubsModule,
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
						"import Hubs\n\n@Instantiable\npublic struct Badge: Instantiable {\n    package init(carrier: Hub.Carrier) {\n        self.carrier = carrier\n    }\n\n    @Instantiated let carrier: Hub.Carrier\n}",
						"import Hubs\n\ninternal extension Hub {\n    @Instantiable\n    package final class Carrier: Instantiable {\n        public init(count: \(Self.unreadableThemeType)) {\n            self.count = count\n        }\n\n        @Received let count: \(Self.unreadableThemeType)\n    }\n}",
					], dependencies: ["Hubs"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingExtensionBasedCarrier_whenOnlyItsInstantiateMentionsTypeSafeDICannotReadAndNothingRaisesIt() async {
		// `[3 of Int]` is mentioned only by the `instantiate(…)` of the extension-based `Rack.Token`, whose declaration sits in
		// a clause the conditions skip, so its unspelled extension bounds it at `internal`, and only `Badge`'s `internal`
		// initializer mentions it.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `count: [3 of Int]`, which `Rack.Token`'s `instantiate(…)` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `internal` as far as SafeDI can tell: `Rack.Token` is declared `@Instantiable` on an extension that spells no access level, so its `instantiate(…)` proves its parameter types only at `internal` whatever access the method spells, and no initializer, `instantiate(…)` or mock method SafeDI records mentions `Rack.Token` or `[3 of Int]` more widely. If `Rack.Token` can be `public`, spell the extension's access level as `@Instantiable(conformsElsewhere: true) public extension Rack.Token`, declaring the `Instantiable` conformance on `Rack.Token`'s own declaration or in a separate `extension Rack.Token: Instantiable {}`, since Swift allows no access level on an extension that declares a conformance, or, if this module declares `Rack.Token`, apply `@Instantiable` to its declaration instead; mention `Rack.Token` or `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `internal`; build `count` inside the tree; or declare the dependency tree on an `internal` type that instantiates `Service`.
			\(fixtures["Feature"]!["Rack.swift"]):11:36: note: `Rack.Token` receives `count: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
						"@Instantiable\npublic struct Badge: Instantiable {\n    init(token: Rack.Token) {\n        self.token = token\n    }\n\n    @Instantiated let token: Rack.Token\n}",
						"public enum Rack {}\n\n#if FLAG\nextension Rack {\n    public struct Token {}\n}\n#endif\n\n@Instantiable\nextension Rack.Token: Instantiable {\n    public static func instantiate(count: \(Self.unreadableThemeType)) -> Rack.Token {\n        Rack.Token()\n    }\n}",
					]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingCarriersRaisingProver_whenOnlyInstantiateOfRaisedExtensionBasedTypeMentionsTypeSafeDICannotRead() async {
		// As above, but `Badge`'s `package` initializer raises `Rack.Token` to `package`, which caps the mention of its
		// `instantiate(…)`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `count: [3 of Int]`, which `Rack.Token`'s `instantiate(…)` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `package` as far as SafeDI can tell: `Rack.Token`'s `instantiate(…)`, which mentions it, is declared on an extension that spells no access level, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions `Rack.Token` is `package` (`Badge.init(token:)`). If `Rack.Token` can be `public`, spell the extension's access level as `@Instantiable(conformsElsewhere: true) public extension Rack.Token`, declaring the `Instantiable` conformance on `Rack.Token`'s own declaration or in a separate `extension Rack.Token: Instantiable {}`, since Swift allows no access level on an extension that declares a conformance, or, if this module declares `Rack.Token`, apply `@Instantiable` to its declaration instead; mention `Rack.Token` or `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `count` inside the tree; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Rack.swift"]):11:36: note: `Rack.Token` receives `count: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
						"@Instantiable\npublic struct Badge: Instantiable {\n    package init(token: Rack.Token) {\n        self.token = token\n    }\n\n    @Instantiated let token: Rack.Token\n}",
						"public enum Rack {}\n\n#if FLAG\nextension Rack {\n    public struct Token {}\n}\n#endif\n\n@Instantiable\nextension Rack.Token: Instantiable {\n    public static func instantiate(count: \(Self.unreadableThemeType)) -> Rack.Token {\n        Rack.Token()\n    }\n}",
					]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSpellingMockOnlyExtension_whenSeamForwardsTypeOnlyUnspelledMockOnlyExtensionDeclares() async {
		// EOU-4: `Rack.User`'s declaration sits in a clause the conditions skip, so only its unspelled `mockOnly` extension
		// bounds it, and the remedy spells that extension's level, with no conformance to move.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["ProfileView.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `ProfileView`: its generated `public` initializer, which `ProfileView`'s `public` access requires, cannot take `user: Rack.User`, which `ProfileView`'s own initializer takes, and cannot pass `nil` for it, since it is required. `Rack.User` is `internal` as far as SafeDI can tell: it is declared `@Instantiable` on an extension that spells no access level, and no initializer, `instantiate(…)` or mock method SafeDI records mentions it more widely. If `Rack.User` can be `public`, spell the extension's access level as `@Instantiable(mockOnly: true) public extension Rack.User`; mention `Rack.User` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `ProfileView` `internal`; or declare the dependency tree on an `internal` type that instantiates `ProfileView`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Rack.swift": "public enum Rack {}\n\n#if FLAG\nextension Rack {\n    public final class User {}\n}\n#endif",
						"UserMock.swift": "@Instantiable(mockOnly: true)\nextension Rack.User {\n    public static func mock() -> Rack.User {\n        Rack.User()\n    }\n}",
						"ProfileView.swift": "@Instantiable(generateDependencyTree: true)\npublic final class ProfileView: Instantiable {\n    init(user: Rack.User, store: ProfileStore) {\n        self.user = user\n        self.store = store\n    }\n\n    @Forwarded let user: Rack.User\n    @Instantiated let store: ProfileStore\n}\n\n@Instantiable\nfinal class ProfileStore: Instantiable {\n    init() {}\n}",
					]),
					ModuleFixture(name: "App", packageName: "Notes", swiftFileContent: [
						"import Feature\nimport SafeDI\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let profileViewBuilder: Instantiator<ProfileView>"]),
					], dependencies: ["Feature"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingToWidenSeamsInitializer_whenCallerInAnotherPackageHoldsValueTheSeamReceivesItself() async {
		// B4.6 for the seam's own receive: only `Service`'s `package` initializer mentions `[3 of Int]`, so its `public`
		// tier omits `theme`, which `App`'s `Shell` provides, and widening that initializer is a remedy, since its other
		// argument, `Badge`, is `public`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Shell.swift"]):11:5: error: `Shell` provides `theme: [3 of Int]`, but the `public` initializer SafeDI generated for `Service` in module `Feature`, the narrowest one module `App` can call, does not take it: `Service` receives `theme` itself, only if available, on its `package` initializer, so this call would pass `nil` to `Service`, which would be handed `theme` were its tree built inline. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `package` (`Service.init(theme:badge:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `Service.init(theme:badge:)` to `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `theme` on this path.
			\(fixtures["Feature"]!["Service.swift"]):8:5: note: `Service` receives `theme: [3 of Int]?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						"@Instantiable\npublic struct Badge: Instantiable {\n    public init() {}\n}",
						"@Instantiable(generateDependencyTree: true)\npublic struct Service: Instantiable {\n    package init(theme: \(Self.unreadableThemeType)?, badge: Badge) {\n        self.theme = theme\n        self.badge = badge\n    }\n\n    @Received(onlyIfAvailable: true) let theme: \(Self.unreadableThemeType)?\n    @Instantiated let badge: Badge\n}",
					]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
						"import Feature\nimport SafeDI\n\n" + seamFixtureType(named: "Shell", declarations: ["@Forwarded let theme: \(Self.unreadableThemeType)", "@Instantiated let service: Service"]),
						"import Feature\nimport SafeDI\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shellBuilder: Instantiator<Shell>"]),
					], dependencies: ["Feature"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenParameterTypeIsInSpelledExtensionOfTypeNestedInAnotherModulesType() async {
		// B1.4k for a type SafeDI proves only by mentions: `Hub.Mid`, which `Gear` declares in an extension of another module's
		// `Hub` and SafeDI reads no declaration of, is nested, so the `public` extension of it bounds nothing SafeDI can count,
		// and only `Badge`'s `internal` initializer mentions `Hub.Mid.Bin`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `bin: Hub.Mid.Bin`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Hub.Mid.Bin` is `internal` as far as SafeDI can tell: it is declared inside an extension of `Hub.Mid`, a nested type, whose spelled access level bounds nothing SafeDI can count. Declare `Bin` in `Hub.Mid`'s body or at top level; mention `Hub.Mid.Bin` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `internal`; build `bin` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Service`.
			\(fixtures["Feature"]!["Badge.swift"]):10:5: note: `Badge` receives `bin: Hub.Mid.Bin` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					hubsModule,
					ModuleFixture(name: "Gear", packageName: "Shop", swiftFileContent: ["import Hubs\n\nextension Hub {\n    public enum Mid {}\n}"], dependencies: ["Hubs"], runsSafeDI: false),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
						"import Gear\nimport Hubs\n\n@Instantiable\npublic struct Badge: Instantiable {\n    init(bin: Hub.Mid.Bin) {\n        self.bin = bin\n    }\n\n    @Received let bin: Hub.Mid.Bin\n}",
						"import Gear\nimport Hubs\n\npublic extension Hub.Mid {\n    @Instantiable\n    final class Bin: Instantiable {\n        init() {}\n    }\n}",
					], dependencies: ["Hubs", "Gear"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenParameterTypeIsInPackageExtensionOfAnotherModulesType() async {
		// `Hub.Theme` is declared in a `package` extension of another module's `Hub`, which bounds it at `package`, and
		// only `Badge`'s `internal` initializer mentions it.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `theme: Hub.Theme`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Hub.Theme` is `package` as far as SafeDI can tell: it is declared inside an extension of `Hub` that spells its access level, which SafeDI counts with `Theme`'s own, since it reads `Hub`'s access only from a declaration of `Hub` in the same module. If `Hub` can be `public`, spell the extension's access level (`public extension Hub { … }`, dropping the modifier on `Theme` that Swift then reports as redundant; the compiler rejects a level wider than `Hub`'s), or declare `Theme` in `Hub`'s body or at top level; mention `Hub.Theme` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `theme` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Badge.swift"]):9:5: note: `Badge` receives `theme: Hub.Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					hubsModule,
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
						"import Hubs\n\n@Instantiable\npublic struct Badge: Instantiable {\n    init(theme: Hub.Theme) {\n        self.theme = theme\n    }\n\n    @Received let theme: Hub.Theme\n}",
						"import Hubs\n\npackage extension Hub {\n    @Instantiable\n    final class Theme: Instantiable {\n        init() {}\n    }\n}",
					], dependencies: ["Hubs"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingEnclosingEntry_whenPlainTypeIsDeclaredInExtensionOfExtensionBasedTypeNothingRaises() async {
		// `Rack.Token.Chip` is declared `public` in an extension of the extension-based `Rack.Token`, whose declaration sits
		// in a clause the conditions skip and which nothing raises, so `Rack.Token` caps it.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `chip: Rack.Token.Chip`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Rack.Token.Chip` is nested in `Rack.Token`, which is `internal` as far as SafeDI can tell: it is declared `@Instantiable` on an extension that spells no access level, and no initializer, `instantiate(…)` or mock method SafeDI records mentions it more widely. If `Rack.Token` can be `public`, spell the extension's access level as `@Instantiable(conformsElsewhere: true) public extension Rack.Token`, declaring the `Instantiable` conformance on `Rack.Token`'s own declaration or in a separate `extension Rack.Token: Instantiable {}`, since Swift allows no access level on an extension that declares a conformance, or, if this module declares `Rack.Token`, apply `@Instantiable` to its declaration instead; mention `Rack.Token` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `internal`; build `chip` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Service`.
			\(fixtures["Feature"]!["Badge.swift"]):7:5: note: `Badge` receives `chip: Rack.Token.Chip` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
						"@Instantiable\npublic struct Badge: Instantiable {\n    init(chip: Rack.Token.Chip) {\n        self.chip = chip\n    }\n\n    @Received let chip: Rack.Token.Chip\n}",
						"public enum Rack {}\n\n#if FLAG\nextension Rack {\n    public struct Token {}\n}\n#endif\n\n@Instantiable\nextension Rack.Token: Instantiable {\n    public static func instantiate() -> Rack.Token {\n        Rack.Token()\n    }\n}\n\nextension Rack.Token {\n    public struct Chip {}\n}",
					]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingUnseenProverOfRaisedEntry_whenRaisedEntryMentionsParameterTypeTwice() async {
		// R8: `Atlas`, in the added directory, raises the extension-based `Rack.Vault`, which its unspelled extension bounds
		// at `internal`, to `public`, and `Rack.Vault`'s `instantiate(…)`, which mentions `Rack.Token` twice, raises
		// `Rack.Token` to `public` in turn – in this module's view, and not in the callers', which see `Rack.Vault` but not
		// `Atlas`. The seam names `Atlas`, which proves `Rack.Token` only through `Rack.Vault`: the walk follows `Rack.Vault`,
		// which both of its mentions of `Rack.Token` reach, and visits it once.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: the initializer SafeDI generates for it depends on `Atlas`, which is declared in a directory this module's `#SafeDIConfiguration` adds, and the modules that call that initializer cannot see that declaration, so their calls would not match the initializer. Declare `Atlas` in a file of this module, or of a module it depends on.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"#SafeDIConfiguration(\n    additionalDirectoriesToInclude: [\"$ADDITIONAL_DIRECTORY\"]\n)",
					seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
					"@Instantiable\npublic struct Badge: Instantiable {\n    package init(token: Rack.Token) {\n        self.token = token\n    }\n\n    @Received let token: Rack.Token\n}",
					"public enum Rack {}\n\n#if FLAG\nextension Rack {\n    public struct Token {}\n    public struct Vault {}\n}\n#endif\n\n@Instantiable\nextension Rack.Token: Instantiable {\n    public static func instantiate() -> Rack.Token {\n        Rack.Token()\n    }\n}\n\n@Instantiable\nextension Rack.Vault: Instantiable {\n    public static func instantiate(token: Rack.Token, spareToken: Rack.Token) -> Rack.Vault {\n        Rack.Vault()\n    }\n}",
				],
				additionalDirectorySwiftFileContent: [
					"@Instantiable\npublic struct Atlas: Instantiable {\n    public init(vault: Rack.Vault) {\n        self.vault = vault\n    }\n\n    @Received let vault: Rack.Vault\n}",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				pluginTargetGraph: { inputSwiftFilePaths in
					PluginTargetGraph(
						target: PluginTargetGraph.Target(moduleName: "Feature", packageID: "shop", sourceFilePaths: inputSwiftFilePaths, dependencyModuleNames: []),
						dependencyTargets: [],
					)
				},
			)
		}
	}

	// MARK: The level an extension of a nested type spells

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesExtensionBasedTypeOnPackageTier_whenPublicExtensionExtendsTypeNestedInPackageTypeSafeDIReads() async throws {
		// The remedy an unspelled extension is offered, taken: SafeDI reads `Rack`'s `package` declaration and none of
		// `Rack.Token`'s, which `Gear` declares, and Swift requires `Rack.Token` to be as visible as its extension spells, so
		// the `public` extension, capped by `Rack`, proves it `package`, and the `package` seam `Service` takes `token`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.nestedTypeModules(
				coreDeclaration: "package enum Rack {}",
				gearDeclaration: "extension Rack {\n    public struct Token {\n        public init() {}\n    }\n}",
				badgeProperty: "@Received let token: Rack.Token",
				extensionDeclaration: "@Instantiable(conformsElsewhere: true)\npublic extension Rack.Token {\n    package static func instantiate() -> Rack.Token {\n        Rack.Token()\n    }\n}\n\nextension Rack.Token: Instantiable {}",
				serviceAccess: "package",
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Gear)
		import Gear
		#endif

		extension Service {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package init(__safeDI_token: @autoclosure @escaping () -> Rack.Token) {
		        let token = LazilyInstantiated<Rack.Token>(__safeDI_token)
		        let badge = Badge(token: token.instance)
		        self.init(badge: badge)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_F2C72F9BD3F5798E {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesMockOnlyExtensionBasedTypeOnPackageTier_whenSeamForwardsTypeOnlyPublicMockOnlyExtensionOfTypeNestedInPackageTypeDeclares() async throws {
		// EOU-4's remedy, taken: SafeDI reads `Rack`'s `package` declaration and none of `Rack.User`'s, which `Gear` declares,
		// so the `public` `mockOnly` extension, capped by `Rack`, proves `Rack.User` `package`, and the `package` seam
		// `ProfileView` takes `user`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Rack.swift": "package enum Rack {}"]),
				ModuleFixture(name: "Gear", packageName: "Shop", swiftFileContent: ["import Core\n\nextension Rack {\n    public final class User {\n        public init() {}\n    }\n}"], dependencies: ["Core"], runsSafeDI: false),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"UserMock.swift": "import Core\nimport Gear\n\n@Instantiable(mockOnly: true)\npublic extension Rack.User {\n    package static func mock() -> Rack.User {\n        Rack.User()\n    }\n}",
					"ProfileView.swift": "import Core\nimport Gear\n\n@Instantiable(generateDependencyTree: true)\npackage final class ProfileView: Instantiable {\n    init(user: Rack.User, store: ProfileStore) {\n        self.user = user\n        self.store = store\n    }\n\n    @Forwarded let user: Rack.User\n    @Instantiated let store: ProfileStore\n}\n\n@Instantiable\nfinal class ProfileStore: Instantiable {\n    init() {}\n}",
				], dependencies: ["Core", "Gear"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Gear)
		import Gear
		#endif

		extension ProfileView {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package convenience init(__safeDI_user user: Rack.User) {
		        let store = ProfileStore()
		        self.init(user: user, store: store)
		    }
		}

		extension ProfileView {
		    public enum __safeDI_ProfileView_C933DB709369908C {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesExtensionBasedTypeOnPublicTier_whenPublicExtensionExtendsTypeNestedInPublicTypeSafeDIReads() async throws {
		// The reproduced shape: SafeDI reads `Rack`'s `public` declaration and none of `Rack.Token`'s, so the `public`
		// extension proves `Rack.Token` `public`, and the `public` seam takes `token`, naming no type SafeDI counts
		// `public` unread. The fixture cannot compile: the conditions skip `Rack.Token`'s declaration.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.rackFileModules(
				rackFile: "public enum Rack {}\n\n#if FLAG\nextension Rack {\n    public struct Token {}\n}\n#endif\n\n@Instantiable(conformsElsewhere: true)\npublic extension Rack.Token {\n    static func instantiate() -> Rack.Token {\n        Rack.Token()\n    }\n}\n\nextension Rack.Token: Instantiable {}",
				badgeProperty: "@Received let token: Rack.Token",
			),
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if FLAG
		#error("SafeDI scanned this module assuming `#if FLAG` was inactive, but it is active in this compilation. Report the conditions this target compiles with to SafeDITool, as the \\"Reporting active conditions\\" section of the SafeDI manual describes for your build system.")
		#endif

		extension Service {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_token: @autoclosure @escaping () -> Rack.Token) {
		        let token = LazilyInstantiated<Rack.Token>(__safeDI_token)
		        let badge = Badge(token: token.instance)
		        self.init(badge: badge)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_8E429FFB2D7F8CA5 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesExtensionBasedTypeOnPublicTierCommentingEnclosingType_whenPublicExtensionExtendsTypeNestedInUnreadTypeWithInstantiableExtension() async throws {
		// `Gear`, which does not run SafeDI, declares `Rack`, so `Rack`'s own `@Instantiable` extension counts it `public`,
		// as an unread type, and caps `Rack.Token`, whose extension spells `public`, exactly as SafeDI reading no
		// declaration of `Rack` does without that entry. The generated `public` initializer names `Rack.Token`, so it
		// carries the comment naming `Rack`, the type SafeDI counts `public` unread.
		let imports = "import Gear\n\n"
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Gear", packageName: "Shop", swiftFileContent: ["public final class Rack {\n    public init() {}\n\n    public struct Token {\n        public init() {}\n    }\n}"], runsSafeDI: false),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
					"Service.swift": imports + "@Instantiable(generateDependencyTree: true)\npublic struct Service: Instantiable {\n    public init(badge: Badge) {\n        self.badge = badge\n    }\n\n    @Instantiated let badge: Badge\n}",
					"Badge.swift": imports + Self.badgeDeclaration(property: "@Received let token: Rack.Token", initializerAccess: ""),
					"Extension.swift": imports + "@Instantiable(conformsElsewhere: true)\nextension Rack {\n    public static func instantiate() -> Rack {\n        Rack()\n    }\n}\n\nextension Rack: Instantiable {}\n\n@Instantiable(conformsElsewhere: true)\npublic extension Rack.Token {\n    static func instantiate() -> Rack.Token {\n        Rack.Token()\n    }\n}\n\nextension Rack.Token: Instantiable {}",
				], dependencies: ["Gear"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Gear)
		import Gear
		#endif

		extension Service {
		    // SafeDI counts `Rack` as `public`: no module it reads declares it narrower. If `Rack` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_token: @autoclosure @escaping () -> Rack.Token) {
		        let token = LazilyInstantiated<Rack.Token>(__safeDI_token)
		        let badge = Badge(token: token.instance)
		        self.init(badge: badge)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_8E429FFB2D7F8CA5 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingEnclosingType_whenPublicExtensionExtendsTypeNestedInPackageTypeSafeDIReads() async {
		// `Rack`'s `package` declaration caps `Rack.Token`, which its `public` extension proves at least as visible, so
		// `Rack.Token` is exactly as visible as `Rack`, and widening `Rack` is the remedy.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):4:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `token: Rack.Token`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Rack.Token` is nested in `Rack`, which is declared `package` in module `Core`. Declare `Rack` `public` in module `Core`; declare `Service` `package`; build `token` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Core"]!["Rack.swift"]):1:1: note: `Rack` is declared `package` here.
			\(fixtures["Core"]!["Rack.swift"]):1:1-1:8: fixit: public
			\(fixtures["Feature"]!["Badge.swift"]):10:5: note: `Badge` receives `token: Rack.Token` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.nestedTypeModules(
					coreDeclaration: "package enum Rack {}",
					gearDeclaration: "extension Rack {\n    public struct Token {\n        public init() {}\n    }\n}",
					badgeProperty: "@Received let token: Rack.Token",
					extensionDeclaration: "@Instantiable(conformsElsewhere: true)\npublic extension Rack.Token {\n    package static func instantiate() -> Rack.Token {\n        Rack.Token()\n    }\n}\n\nextension Rack.Token: Instantiable {}",
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingEnclosingType_whenPublicExtensionExtendsTypeNestedTwoLevelsInPackageTypeSafeDIReads() async {
		// Swift checks `public extension Rack.Bay.Bin` against `Bin`'s own level alone, and SafeDI reads `Rack.Bay`'s
		// `package` declaration, which caps `Bin`: `Rack.Bay.Bin` is exactly as visible as `Rack.Bay`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):4:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `bin: Rack.Bay.Bin`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Rack.Bay.Bin` is nested in `Rack.Bay`, which is declared `package` in module `Core`. Declare `Rack.Bay` `public` in module `Core`; declare `Service` `package`; build `bin` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Core"]!["Rack.swift"]):2:5: note: `Rack.Bay` is declared `package` here.
			\(fixtures["Core"]!["Rack.swift"]):2:5-2:12: fixit: public
			\(fixtures["Feature"]!["Badge.swift"]):10:5: note: `Badge` receives `bin: Rack.Bay.Bin` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.nestedTypeModules(
					coreDeclaration: "public enum Rack {\n    package enum Bay {}\n}",
					gearDeclaration: "extension Rack.Bay {\n    public struct Bin {\n        public init() {}\n    }\n}",
					badgeProperty: "@Received let bin: Rack.Bay.Bin",
					extensionDeclaration: "@Instantiable(conformsElsewhere: true)\npublic extension Rack.Bay.Bin {\n    package static func instantiate() -> Rack.Bay.Bin {\n        Rack.Bay.Bin()\n    }\n}\n\nextension Rack.Bay.Bin: Instantiable {}",
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingEnclosingEntry_whenPublicExtensionExtendsTypeNestedInPackageInstantiableType() async {
		// The type enclosing `Rack.Token`, whose declaration sits in a clause the conditions skip, is the `package`
		// `@Instantiable` `Rack`, whose own declaration caps it.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `token: Rack.Token`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Rack.Token` is nested in `Rack`, whose own `@Instantiable` declaration is `package`. Declare `Rack` `public`; declare `Service` `package`; build `token` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Badge.swift"]):7:5: note: `Badge` receives `token: Rack.Token` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.rackFileModules(
					rackFile: "@Instantiable\npackage struct Rack: Instantiable {\n    package init() {}\n}\n\n#if FLAG\nextension Rack {\n    public struct Token {}\n}\n#endif\n\n@Instantiable(conformsElsewhere: true)\npublic extension Rack.Token {\n    package static func instantiate() -> Rack.Token {\n        Rack.Token()\n    }\n}\n\nextension Rack.Token: Instantiable {}",
					badgeProperty: "@Received let token: Rack.Token",
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingLevelExtensionSpells_whenPackageExtensionExtendsTypeNestedInPublicTypeSafeDIReads() async {
		// `Rack` is `public`, and the `package` extension proves `Rack.Token` `package`, which nothing raises.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `token: Rack.Token`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Rack.Token` is `package` as far as SafeDI can tell: it is declared `@Instantiable` on an extension that spells `package`, and no initializer, `instantiate(…)` or mock method SafeDI records mentions it more widely. If `Rack.Token` can be `public`, spell the extension's access level as `@Instantiable(conformsElsewhere: true) public extension Rack.Token`, declaring the `Instantiable` conformance on `Rack.Token`'s own declaration or in a separate `extension Rack.Token: Instantiable {}`, since Swift allows no access level on an extension that declares a conformance, or, if this module declares `Rack.Token`, apply `@Instantiable` to its declaration instead; mention `Rack.Token` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `token` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Badge.swift"]):7:5: note: `Badge` receives `token: Rack.Token` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.rackFileModules(
					rackFile: "public enum Rack {}\n\n#if FLAG\nextension Rack {\n    public struct Token {}\n}\n#endif\n\n@Instantiable(conformsElsewhere: true)\npackage extension Rack.Token {\n    static func instantiate() -> Rack.Token {\n        Rack.Token()\n    }\n}\n\nextension Rack.Token: Instantiable {}",
					badgeProperty: "@Received let token: Rack.Token",
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingLevelExtensionSpells_whenInternalExtensionOfTypeNestedInPublicTypeIsRaisedOnlyToPackage() async {
		// The `internal` extension proves `Rack.Token` `internal`, and `Badge`'s `package` initializer raises it to
		// `package`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `token: Rack.Token`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Rack.Token` is `package` as far as SafeDI can tell: it is declared `@Instantiable` on an extension that spells `internal`, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `package` (`Badge.init(token:)`). If `Rack.Token` can be `public`, spell the extension's access level as `@Instantiable(conformsElsewhere: true) public extension Rack.Token`, declaring the `Instantiable` conformance on `Rack.Token`'s own declaration or in a separate `extension Rack.Token: Instantiable {}`, since Swift allows no access level on an extension that declares a conformance, or, if this module declares `Rack.Token`, apply `@Instantiable` to its declaration instead; mention `Rack.Token` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `token` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Badge.swift"]):7:5: note: `Badge` receives `token: Rack.Token` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.rackFileModules(
					rackFile: "public enum Rack {}\n\n#if FLAG\nextension Rack {\n    public struct Token {}\n}\n#endif\n\n@Instantiable(conformsElsewhere: true)\ninternal extension Rack.Token {\n    static func instantiate() -> Rack.Token {\n        Rack.Token()\n    }\n}\n\nextension Rack.Token: Instantiable {}",
					badgeProperty: "@Received let token: Rack.Token",
					badgeInitializerAccess: "package ",
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingSpelledLevelDoesNotCount_whenPublicExtensionExtendsTypeNestedInTypeSafeDIReadsNoDeclarationOf() async {
		// SafeDI reads `Rack` but not `Rack.Bay`, whose declaration sits in a clause the conditions skip, and Swift checks
		// the extension against `Bin`'s own level alone, so `Bay` could be narrower: the extension's `public` does not
		// count, and spelling it is no remedy.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `bin: Rack.Bay.Bin`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Rack.Bay.Bin` is `internal` as far as SafeDI can tell: it is declared `@Instantiable` on an extension that spells `public`, which SafeDI cannot count, since it cannot prove the access of `Rack.Bay`, the type enclosing `Rack.Bay.Bin`, and no initializer, `instantiate(…)` or mock method SafeDI records mentions it more widely. Mention `Rack.Bay.Bin` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `internal`; build `bin` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Service`.
			\(fixtures["Feature"]!["Badge.swift"]):7:5: note: `Badge` receives `bin: Rack.Bay.Bin` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.rackFileModules(
					rackFile: Self.unreadBayRackFile(binExtension: "@Instantiable(conformsElsewhere: true)\npublic extension Rack.Bay.Bin {\n    static func instantiate() -> Rack.Bay.Bin {\n        Rack.Bay.Bin()\n    }\n}\n\nextension Rack.Bay.Bin: Instantiable {}"),
					badgeProperty: "@Received let bin: Rack.Bay.Bin",
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingSpelledLevelDoesNotCount_whenPublicExtensionOfTypeNestedInTypeSafeDIReadsNoDeclarationOfIsRaisedOnlyToPackage() async {
		// As above, with `Badge`'s `package` initializer raising `Rack.Bay.Bin` to `package`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `bin: Rack.Bay.Bin`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Rack.Bay.Bin` is `package` as far as SafeDI can tell: it is declared `@Instantiable` on an extension that spells `public`, which SafeDI cannot count, since it cannot prove the access of `Rack.Bay`, the type enclosing `Rack.Bay.Bin`, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions it is `package` (`Badge.init(bin:)`). Mention `Rack.Bay.Bin` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `bin` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Badge.swift"]):7:5: note: `Badge` receives `bin: Rack.Bay.Bin` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.rackFileModules(
					rackFile: Self.unreadBayRackFile(binExtension: "@Instantiable(conformsElsewhere: true)\npublic extension Rack.Bay.Bin {\n    static func instantiate() -> Rack.Bay.Bin {\n        Rack.Bay.Bin()\n    }\n}\n\nextension Rack.Bay.Bin: Instantiable {}"),
					badgeProperty: "@Received let bin: Rack.Bay.Bin",
					badgeInitializerAccess: "package ",
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingSpelledLevelDoesNotCount_whenPublicExtensionExtendsTypeNestedInAnotherModulesInstantiableType() async {
		// `Hub.Token`, which `Gear` declares in an extension of another module's `@Instantiable` `Hub`, is nested in a type
		// SafeDI reads the access of only from a declaration of the same module, so the extension's `public` does not
		// count.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):4:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `token: Hub.Token`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Hub.Token` is `internal` as far as SafeDI can tell: it is declared `@Instantiable` on an extension that spells `public`, which SafeDI cannot count, since it cannot prove the access of `Hub`, the type enclosing `Hub.Token`, and no initializer, `instantiate(…)` or mock method SafeDI records mentions it more widely. Mention `Hub.Token` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `internal`; build `token` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Service`.
			\(fixtures["Feature"]!["Badge.swift"]):10:5: note: `Badge` receives `token: Hub.Token` here.
			"""
		}) {
			let imports = "import Gear\nimport Hubs\n\n"
			return try await executeSafeDIToolMultiModuleTest(
				modules: [
					hubsModule,
					ModuleFixture(name: "Gear", packageName: "Shop", swiftFileContent: ["import Hubs\n\nextension Hub {\n    public struct Token {\n        public init() {}\n    }\n}"], dependencies: ["Hubs"], runsSafeDI: false),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Service.swift": imports + seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
						"Badge.swift": imports + Self.badgeDeclaration(property: "@Received let token: Hub.Token", initializerAccess: ""),
						"Extension.swift": imports + "@Instantiable(conformsElsewhere: true)\npublic extension Hub.Token {\n    static func instantiate() -> Hub.Token {\n        Hub.Token()\n    }\n}\n\nextension Hub.Token: Instantiable {}",
					], dependencies: ["Hubs", "Gear"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingNoSpelledExtension_whenUnspelledExtensionExtendsTypeNestedInTypeSafeDIReadsNoDeclarationOf() async {
		// As two above, unspelled: spelling the extension would not count either, so it is not offered.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `bin: Rack.Bay.Bin`, which `Badge` receives, and cannot pass `nil` for it, since it is required. `Rack.Bay.Bin` is `internal` as far as SafeDI can tell: it is declared `@Instantiable` on an extension that spells no access level, and no initializer, `instantiate(…)` or mock method SafeDI records mentions it more widely. Mention `Rack.Bay.Bin` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `internal`; build `bin` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Service`.
			\(fixtures["Feature"]!["Badge.swift"]):7:5: note: `Badge` receives `bin: Rack.Bay.Bin` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.rackFileModules(
					rackFile: Self.unreadBayRackFile(binExtension: "@Instantiable\nextension Rack.Bay.Bin: Instantiable {\n    public static func instantiate() -> Rack.Bay.Bin {\n        Rack.Bay.Bin()\n    }\n}"),
					badgeProperty: "@Received let bin: Rack.Bay.Bin",
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingCarriersExtensionSpellsItsLevel_whenOnlyInstantiateOfPackageExtensionBasedTypeMentionsTypeSafeDICannotRead() async {
		// `[3 of Int]` is mentioned only by the `public` `instantiate(…)` of `Rack.Token`, whose `package` extension, which
		// `Rack`'s `public` declaration does not cap, proves it `package`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `count: [3 of Int]`, which `Rack.Token`'s `instantiate(…)` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `package` as far as SafeDI can tell: `Rack.Token` is declared `@Instantiable` on an extension that spells `package`, so its `instantiate(…)` proves its parameter types only at `package` whatever access the method spells, and no initializer, `instantiate(…)` or mock method SafeDI records mentions `Rack.Token` or `[3 of Int]` more widely. If `Rack.Token` can be `public`, spell the extension's access level as `@Instantiable(conformsElsewhere: true) public extension Rack.Token`, declaring the `Instantiable` conformance on `Rack.Token`'s own declaration or in a separate `extension Rack.Token: Instantiable {}`, since Swift allows no access level on an extension that declares a conformance, or, if this module declares `Rack.Token`, apply `@Instantiable` to its declaration instead; mention `Rack.Token` or `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `count` inside the tree; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Rack.swift"]):11:36: note: `Rack.Token` receives `count: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.rackFileModules(
					rackFile: "public enum Rack {}\n\n#if FLAG\nextension Rack {\n    public struct Token {}\n}\n#endif\n\n@Instantiable(conformsElsewhere: true)\npackage extension Rack.Token {\n    public static func instantiate(count: \(Self.unreadableThemeType)) -> Rack.Token {\n        Rack.Token()\n    }\n}\n\nextension Rack.Token: Instantiable {}",
					badgeProperty: "@Instantiated let token: Rack.Token",
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingCarriersExtensionSpellsItsLevel_whenOnlyInstantiateOfRaisedInternalExtensionBasedTypeMentionsTypeSafeDICannotRead() async {
		// As above, with an `internal` extension, which `Badge`'s `package` initializer raises to `package`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `count: [3 of Int]`, which `Rack.Token`'s `instantiate(…)` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `package` as far as SafeDI can tell: `Rack.Token`'s `instantiate(…)`, which mentions it, is declared on an extension that spells `internal`, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions `Rack.Token` is `package` (`Badge.init(token:)`). If `Rack.Token` can be `public`, spell the extension's access level as `@Instantiable(conformsElsewhere: true) public extension Rack.Token`, declaring the `Instantiable` conformance on `Rack.Token`'s own declaration or in a separate `extension Rack.Token: Instantiable {}`, since Swift allows no access level on an extension that declares a conformance, or, if this module declares `Rack.Token`, apply `@Instantiable` to its declaration instead; mention `Rack.Token` or `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `count` inside the tree; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Rack.swift"]):11:36: note: `Rack.Token` receives `count: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.rackFileModules(
					rackFile: "public enum Rack {}\n\n#if FLAG\nextension Rack {\n    public struct Token {}\n}\n#endif\n\n@Instantiable(conformsElsewhere: true)\ninternal extension Rack.Token {\n    public static func instantiate(count: \(Self.unreadableThemeType)) -> Rack.Token {\n        Rack.Token()\n    }\n}\n\nextension Rack.Token: Instantiable {}",
					badgeProperty: "@Instantiated let token: Rack.Token",
					badgeInitializerAccess: "package ",
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingCarriersSpelledLevelDoesNotCount_whenOnlyInstantiateOfTypeNestedInTypeSafeDIReadsNoDeclarationOfMentionsTypeSafeDICannotRead() async {
		// `[3 of Int]` is mentioned only by the `public` `instantiate(…)` of `Rack.Bay.Bin`, whose `public` extension does
		// not count, since SafeDI reads no declaration of `Rack.Bay`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `count: [3 of Int]`, which `Rack.Bay.Bin`'s `instantiate(…)` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `internal` as far as SafeDI can tell: `Rack.Bay.Bin` is declared `@Instantiable` on an extension that spells `public`, which SafeDI cannot count, since it cannot prove the access of `Rack.Bay`, the type enclosing `Rack.Bay.Bin`, so its `instantiate(…)` proves its parameter types only at `internal` whatever access the method spells, and no initializer, `instantiate(…)` or mock method SafeDI records mentions `Rack.Bay.Bin` or `[3 of Int]` more widely. Mention `Rack.Bay.Bin` or `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `internal`; build `count` inside the tree; or declare the dependency tree on an `internal` type that instantiates `Service`.
			\(fixtures["Feature"]!["Rack.swift"]):13:36: note: `Rack.Bay.Bin` receives `count: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.rackFileModules(
					rackFile: Self.unreadBayRackFile(binExtension: "@Instantiable(conformsElsewhere: true)\npublic extension Rack.Bay.Bin {\n    public static func instantiate(count: \(Self.unreadableThemeType)) -> Rack.Bay.Bin {\n        Rack.Bay.Bin()\n    }\n}\n\nextension Rack.Bay.Bin: Instantiable {}"),
					badgeProperty: "@Instantiated let bin: Rack.Bay.Bin",
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingCarriersSpelledLevelDoesNotCount_whenOnlyInstantiateOfRaisedTypeNestedInTypeSafeDIReadsNoDeclarationOfMentionsTypeSafeDICannotRead() async {
		// As above, with `Badge`'s `package` initializer raising `Rack.Bay.Bin` to `package`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `count: [3 of Int]`, which `Rack.Bay.Bin`'s `instantiate(…)` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `package` as far as SafeDI can tell: `Rack.Bay.Bin`'s `instantiate(…)`, which mentions it, is declared on an extension that spells `public`, which SafeDI cannot count, since it cannot prove the access of `Rack.Bay`, the type enclosing `Rack.Bay.Bin`, and every initializer, `instantiate(…)` and mock method SafeDI records that mentions `Rack.Bay.Bin` is `package` (`Badge.init(bin:)`). Mention `Rack.Bay.Bin` or `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `count` inside the tree; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Rack.swift"]):13:36: note: `Rack.Bay.Bin` receives `count: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.rackFileModules(
					rackFile: Self.unreadBayRackFile(binExtension: "@Instantiable(conformsElsewhere: true)\npublic extension Rack.Bay.Bin {\n    public static func instantiate(count: \(Self.unreadableThemeType)) -> Rack.Bay.Bin {\n        Rack.Bay.Bin()\n    }\n}\n\nextension Rack.Bay.Bin: Instantiable {}"),
					badgeProperty: "@Instantiated let bin: Rack.Bay.Bin",
					badgeInitializerAccess: "package ",
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorListingProverAtEnclosingTypesLevel_whenOnlyInstantiateOfPublicExtensionOfTypeNestedInPackageTypeMentionsTypeSafeDICannotRead() async {
		// `Rack`'s `package` declaration caps `Rack.Token`, whose extension spells `public`, so the `public`
		// `instantiate(…)` of `Rack.Token` proves `[3 of Int]` at `package`, as a member of any type proven exactly does.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `count: [3 of Int]`, which `Rack.Token`'s `instantiate(…)` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `package` (`Rack.Token.instantiate(count:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `count` inside the tree; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Rack.swift"]):11:36: note: `Rack.Token` receives `count: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.rackFileModules(
					rackFile: "package enum Rack {}\n\n#if FLAG\nextension Rack {\n    public struct Token {}\n}\n#endif\n\n@Instantiable(conformsElsewhere: true)\npublic extension Rack.Token {\n    public static func instantiate(count: \(Self.unreadableThemeType)) -> Rack.Token {\n        Rack.Token()\n    }\n}\n\nextension Rack.Token: Instantiable {}",
					badgeProperty: "@Instantiated let token: Rack.Token",
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorListingProverAtEnclosingTypesLevel_whenOnlyInstantiateOfPublicExtensionOfTypeNestedInPackageInstantiableTypeMentionsTypeSafeDICannotRead() async {
		// As above, with the `package` `@Instantiable` `Rack` capping `Rack.Token`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`'s `public` access requires, cannot take `count: [3 of Int]`, which `Rack.Token`'s `instantiate(…)` receives, and cannot pass `nil` for it, since it is required. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `package` (`Rack.Token.instantiate(count:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; declare `Service` `package`; build `count` inside the tree; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["Rack.swift"]):14:36: note: `Rack.Token` receives `count: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.rackFileModules(
					rackFile: "@Instantiable\npackage struct Rack: Instantiable {\n    package init() {}\n}\n\n#if FLAG\nextension Rack {\n    public struct Token {}\n}\n#endif\n\n@Instantiable(conformsElsewhere: true)\npublic extension Rack.Token {\n    public static func instantiate(count: \(Self.unreadableThemeType)) -> Rack.Token {\n        Rack.Token()\n    }\n}\n\nextension Rack.Token: Instantiable {}",
					badgeProperty: "@Instantiated let token: Rack.Token",
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Core`, in package `Shop`, which declares `coreDeclaration` in `Rack.swift`, and `Gear`, which does not run SafeDI
	/// and declares `gearDeclaration`, before `Feature`, whose seam `Service`, at `serviceAccess`, instantiates `Badge`,
	/// which declares `badgeProperty` and takes it in an `internal` initializer, and whose `Extension.swift` holds
	/// `extensionDeclaration`: SafeDI reads `Core`'s `package` declarations, which another module can name, and none of
	/// `Gear`'s.
	private static func nestedTypeModules(coreDeclaration: String, gearDeclaration: String, badgeProperty: String, extensionDeclaration: String, serviceAccess: String = "public") -> [ModuleFixture] {
		let imports = "import Core\nimport Gear\n\n"
		return [
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Rack.swift": coreDeclaration]),
			ModuleFixture(name: "Gear", packageName: "Shop", swiftFileContent: ["import Core\n\n" + gearDeclaration], dependencies: ["Core"], runsSafeDI: false),
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContentByFilePath: [
					"Service.swift": imports + "@Instantiable(generateDependencyTree: true)\n\(serviceAccess) struct Service: Instantiable {\n    \(serviceAccess) init(badge: Badge) {\n        self.badge = badge\n    }\n\n    @Instantiated let badge: Badge\n}",
					"Badge.swift": imports + badgeDeclaration(property: badgeProperty, initializerAccess: ""),
					"Extension.swift": imports + extensionDeclaration,
				],
				dependencies: ["Core", "Gear"],
			),
		]
	}

	/// `Feature`, in package `Shop`, whose seam `Service` instantiates `Badge`, which declares `badgeProperty` and takes it
	/// in an initializer at `badgeInitializerAccess`, and whose `Rack.swift` holds `rackFile`.
	private static func rackFileModules(rackFile: String, badgeProperty: String, badgeInitializerAccess: String = "") -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
				"Service.swift": seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
				"Badge.swift": badgeDeclaration(property: badgeProperty, initializerAccess: badgeInitializerAccess),
				"Rack.swift": rackFile,
			]),
		]
	}

	/// The `public` `@Instantiable` `Badge`, which declares `property` and takes it in an initializer at
	/// `initializerAccess`.
	private static func badgeDeclaration(property: String, initializerAccess: String) -> String {
		let declaredProperty = property[property.range(of: " let ")!.upperBound...]
		let label = String(declaredProperty.prefix { $0 != ":" })
		let type = declaredProperty.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
		return "@Instantiable\npublic struct Badge: Instantiable {\n    \(initializerAccess)init(\(label): \(type)) {\n        self.\(label) = \(label)\n    }\n\n    \(property)\n}"
	}

	/// A file that declares the `public` `Rack` and, in a clause the conditions skip, `Rack.Bay.Bin`, then `binExtension`:
	/// SafeDI reads `Rack` and no declaration of `Rack.Bay`.
	private static func unreadBayRackFile(binExtension: String) -> String {
		"public enum Rack {}\n\n#if FLAG\nextension Rack {\n    public enum Bay {\n        public struct Bin {}\n    }\n}\n#endif\n\n" + binExtension
	}

	/// The lines a generated file repeats for a fixture's `import <moduleName>`, and the blank line after them.
	private static func importLines(_ moduleName: String) -> String {
		"#if canImport(\(moduleName))\nimport \(moduleName)\n#endif\n\n"
	}

	/// The adopter's per-module tree, its modules all in package `App`: `FeedModule`'s `package` seam `FeedScreen`,
	/// whose own initializer spells `seamInitializerAccess`, receives `SharedModule`'s `SharedThing` and instantiates the
	/// `internal` `FeedStore`, which builds the `internal` `FeedFormatter`, and `service: FeedService`, a hole declared by
	/// `feedServiceDeclaration` in a file of its own without a SafeDI marker; `App`'s root builds the seam, and
	/// `AppFeedService`, which receives `shared`, fills the hole.
	private static func feedModules(feedServiceDeclaration: String = "package protocol FeedService {\n    func headlines() -> [String]\n}", seamInitializerAccess: String = "") -> [ModuleFixture] {
		[
			ModuleFixture(name: "SharedModule", packageName: "App", swiftFileContent: ["@Instantiable\npackage final class SharedThing: Instantiable {\n    package init() {}\n}"]),
			ModuleFixture(
				name: "FeedModule",
				packageName: "App",
				swiftFileContentByFilePath: [
					"FeedService.swift": feedServiceDeclaration,
					"FeedScreen.swift": """
					import SharedModule

					@Instantiable(generateDependencyTree: true)
					package final class FeedScreen: Instantiable {
					    \(seamInitializerAccess)init(shared: SharedThing, store: FeedStore, service: FeedService) {
					        self.shared = shared
					        self.store = store
					        self.service = service
					    }

					    @Received let shared: SharedThing
					    @Instantiated let store: FeedStore
					    @Instantiated let service: FeedService
					}

					@Instantiable
					final class FeedStore: Instantiable {
					    init(shared: SharedThing, formatter: FeedFormatter) {
					        self.shared = shared
					        self.formatter = formatter
					    }

					    @Received let shared: SharedThing
					    @Instantiated let formatter: FeedFormatter
					}

					@Instantiable
					struct FeedFormatter: Instantiable {
					    init() {}
					}
					""",
				],
				dependencies: ["SharedModule"],
			),
			ModuleFixture(
				name: "App",
				packageName: "App",
				swiftFileContent: [
					"""
					import FeedModule
					import SharedModule

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    init(shared: SharedThing, feed: FeedScreen) {
					        self.shared = shared
					        self.feed = feed
					    }

					    @Instantiated let shared: SharedThing
					    @Instantiated let feed: FeedScreen
					}

					@Instantiable(fulfillingAdditionalTypes: [FeedService.self])
					final class AppFeedService: FeedService, Instantiable {
					    init(shared: SharedThing) {
					        self.shared = shared
					    }

					    @Received let shared: SharedThing

					    func headlines() -> [String] { ["app"] }
					}
					""",
				],
				dependencies: ["SharedModule", "FeedModule"],
			),
		]
	}

	/// `Core`, which declares `Theme` `package`, and `Other`, which declares it `public`, each in a file without a
	/// SafeDI marker, and `Feature`, of the same package, which sees both: its public seam `Service` builds `Badge`, which
	/// receives `theme` of the protocol `mention` spells.
	private static func themeInTwoModules(mention: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": "package protocol Theme {}"]),
			ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": "public protocol Theme {}"]),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"import Core\nimport Other\n\n@Instantiable\npublic struct Badge: Instantiable {\n    init(theme: any \(mention)) {\n        self.theme = theme\n    }\n\n    @Received let theme: any \(mention)\n}",
				seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
			], dependencies: ["Core", "Other"]),
		]
	}

	/// `Feature`'s `package` seam `Screen`, whose own `internal` initializer takes the `theme: Theme` it receives and the
	/// `internal` `Store` it builds.
	private static let themeScreen = """
	import Core
	import SafeDI

	@Instantiable(generateDependencyTree: true)
	package struct Screen: Instantiable {
	    init(theme: Theme, store: Store) {
	        self.theme = theme
	        self.store = store
	    }

	    @Received private let theme: Theme
	    @Instantiated private let store: Store
	}

	@Instantiable
	final class Store: Instantiable {
	    init() {}
	}
	"""

	/// The Bazel adopter's shape: `Core` declares `public protocol Theme` in the file of its `ThemeService`, and none of its
	/// declarations mentions `Theme`; `Feature`'s seam `Screen` receives it; `App`'s root builds `ThemeProvider` as the
	/// `Theme` and the seam. All three modules are in package `Pkg`.
	private static let themeBesideInstantiableModules = [
		ModuleFixture(name: "Core", packageName: "Pkg", swiftFileContentByFilePath: [
			"ThemeService.swift": "import SafeDI\n\npublic protocol Theme {\n    var name: String { get }\n}\n\n@Instantiable\npublic final class ThemeService: Instantiable {\n    public init() {}\n}",
		]),
		ModuleFixture(name: "Feature", packageName: "Pkg", swiftFileContentByFilePath: ["Screen.swift": themeScreen], dependencies: ["Core"]),
		ModuleFixture(name: "App", packageName: "Pkg", swiftFileContent: [
			"""
			import Core
			import Feature
			import SafeDI

			@Instantiable(fulfillingAdditionalTypes: [Theme.self])
			final class ThemeProvider: Theme, Instantiable {
			    init() {}

			    let name = "app"
			}

			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    init(theme: Theme, screen: Screen) {
			        self.theme = theme
			        self.screen = screen
			    }

			    @Instantiated private let theme: Theme
			    @Instantiated private let screen: Screen
			}
			""",
		], dependencies: ["Core", "Feature"]),
	]

	/// The `public final class User` the README's `mockOnly` extension mocks.
	private static let publicUser = "public final class User: Sendable {\n    public init(name: String) {\n        self.name = name\n    }\n\n    public let name: String\n}"

	/// The README's profile: `Feature`'s public `ProfileView`, declared with `seamAttribute`, forwards `user: User`, which
	/// `userDeclaration` declares and an unspelled `@Instantiable(mockOnly: true) extension User` mocks, and builds the
	/// `internal` `ProfileStore`; `App`, in another package, builds the view through its root's instantiator.
	private static func profileModules(seamAttribute: String, userDeclaration: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
				"User.swift": userDeclaration,
				"UserMock.swift": "@Instantiable(mockOnly: true)\nextension User {\n    public static func mock() -> User {\n        User(name: \"Mock\")\n    }\n}",
				"ProfileView.swift": """
				\(seamAttribute)
				public final class ProfileView: Instantiable {
				    init(user: User, store: ProfileStore) {
				        self.user = user
				        self.store = store
				    }

				    @Forwarded let user: User
				    @Instantiated let store: ProfileStore
				}

				@Instantiable
				final class ProfileStore: Instantiable {
				    init() {}
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "Notes", swiftFileContent: [
				"import Feature\nimport SafeDI\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let profileViewBuilder: Instantiator<ProfileView>"]),
			], dependencies: ["Feature"]),
		]
	}

	/// `Service`'s generated initializers, without the file header, where `Badge`'s `package` initializer receives the
	/// plain `Theme` only if available: a `public` tier that passes `nil`, and a `package` one that takes it.
	private static let twoTierService = """
	extension Service {
	    /// Code you write and code SafeDI generates can both call this initializer.
	    public init() {
	        self.init(__safeDI_theme: nil)
	    }

	    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
	    package init(__safeDI_theme: @autoclosure @escaping () -> Theme?) {
	        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
	        let badge = Badge(theme: theme.instance)
	        self.init(badge: badge)
	    }
	}

	extension Service {
	    public enum __safeDI_Service_5CF188DE6A83E906 {}
	}
	"""

	/// The comment line a `.moduleInfo` run's generated file carries above the first `public` declaration that names one
	/// of `names`, types SafeDI reads no declaration of; none under the plugin, which reads every first-party module.
	private static func unreadTypeComment(_ names: [String], _ integration: MultiModuleIntegration) -> String {
		guard integration == .moduleInfo else { return "" }
		let list = names.map { "`\($0)`" }.joined(separator: " and ")
		return names.count == 1
			? "    // SafeDI counts \(list) as `public`: no module it reads declares it narrower. If \(list) is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.\n"
			: "    // SafeDI counts \(list) as `public`: no module it reads declares them narrower. If one is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.\n"
	}

	/// The path a diagnostic names `file` of `module` by under `integration`.
	private static func path(of file: String, in module: String, _ fixtures: [String: FixturePaths], _ integration: MultiModuleIntegration) -> String {
		guard let moduleFixtures = fixtures[module] else { return "<\(module) did not run>/\(file)" }
		return switch integration {
		case .moduleInfo:
			moduleFixtures[file]
		case .swiftPackagePlugin:
			NormalizedFilePath(moduleFixtures.compilerPath(of: file)).path
		}
	}
}
