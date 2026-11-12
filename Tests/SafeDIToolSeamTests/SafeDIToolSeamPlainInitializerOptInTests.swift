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

/// Every tier of a seam has the initializer only generated code calls, under `__safeDI_` labels, and every generated call
/// calls it. The initializer a person calls, under readable labels, is generated only when the seam's own module sets
/// `generatePlainDependencyTreeInitializers: true` in its `#SafeDIConfiguration`, so no caller reads another module's
/// setting, and no guard, call or `.safedi` depends on it.
struct SafeDIToolSeamPlainInitializerOptInTests: ~Copyable {
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

	/// The configuration that opts a module in.
	private static let optingIn = ["SafeDIConfiguration.swift": "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n"]

	/// `Screen`, a seam whose tree receives `user` in `Detail`, which `Screen` builds behind an instantiator, and `User`.
	/// `userType` is how `Detail` receives `user`: a `User` is deferred by the initializer generated code calls, an
	/// `Instantiator<User>` taken by value.
	private static func featureFiles(userType: String = "User") -> [String] {
		[
			seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let detailBuilder: Instantiator<Detail>"]),
			seamFixtureType(named: "Detail", declarations: ["@Received let user: \(userType)"]),
			"""
			@Instantiable
			public final class User: Instantiable, Sendable {
			    public init() {}
			}
			""",
		]
	}

	/// `featureFiles(userType:)` with `Root`, which holds `user` as `rootUser` and builds `Screen`.
	private static func singleModuleFiles(rootUser: String, userType: String = "User") -> [String] {
		[seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: \(rootUser)", "@Instantiated let screen: Screen"])]
			+ featureFiles(userType: userType)
	}

	/// `Feature`, which declares `featureFiles()`, and `App`, whose root builds `Screen`; each module's configuration is
	/// its `SafeDIConfiguration.swift`, when given.
	private static func modules(featureConfiguration: [String: String] = [:], appConfiguration: [String: String] = [:]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: featureFiles(), swiftFileContentByFilePath: featureConfiguration),
			ModuleFixture(
				name: "App",
				packageName: "Shop",
				swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let screen: Screen"])],
				swiftFileContentByFilePath: appConfiguration,
				dependencies: ["Feature"],
			),
		]
	}

	/// The extension `Feature` generates for `Screen` when its module does not opt in: the initializer generated code
	/// calls, alone.
	private static let screenWithoutPlainInitializer = """
	extension Screen {
	    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
	    public init(__safeDI_user: @autoclosure @escaping () -> User) {
	        let user = LazilyInstantiated<User>(__safeDI_user)
	        func __safeDI_detailBuilder() -> Detail {
	            Detail(user: user.instance)
	        }
	        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
	        self.init(detailBuilder: detailBuilder)
	    }
	}

	extension Screen {
	    public enum __safeDI_Screen_08AA1A656B91D4BA {}
	}
	"""

	/// The extension `Feature` generates for `Screen` when its module opts in: the initializer for people, then the one
	/// generated code calls.
	private static let screenWithPlainInitializer = """
	extension Screen {
	    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained.
	    public init(user: User) {
	        self.init(__safeDI_user: user)
	    }

	    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	    /// From code you write, call the initializer above instead.
	    public init(__safeDI_user: @autoclosure @escaping () -> User) {
	        let user = LazilyInstantiated<User>(__safeDI_user)
	        func __safeDI_detailBuilder() -> Detail {
	            Detail(user: user.instance)
	        }
	        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
	        self.init(detailBuilder: detailBuilder)
	    }
	}

	extension Screen {
	    public enum __safeDI_Screen_08AA1A656B91D4BA {}
	}
	"""

	/// The file `App` generates for its root, which calls `Screen`'s initializer generated code calls, whatever either
	/// module's configuration says.
	private static func appFiles(_ integration: MultiModuleIntegration) -> [String: String] {
		[
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let user = User()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_08AA1A656B91D4BA.self\(integration.seamCallComment(type: "Screen", declaringModule: "Feature"))
			            return Screen(__safeDI_user: user)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(user: user, screen: screen)
			    }
			}
			""",
		]
	}

	/// The files `Feature` generates under `integration` when its extension for `Screen` is `screen`.
	private static func featureFiles(_ integration: MultiModuleIntegration, screen: String) -> [String: String] {
		[integration == .moduleInfo ? "Feature.swift" : "Screen+SafeDI.swift": generatedFileHeader + screen]
	}

	// MARK: Off by default

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesOnlyInitializerGeneratedCodeCalls_whenNoModuleConfiguresPlainInitializers(integration: MultiModuleIntegration) async throws {
		// Off by default: `Feature` generates the `__safeDI_` initializer alone, and `App`'s generated call of it compiles.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(), integration: integration, filesToDelete: &filesToDelete)
		#expect(try #require(output.modules["Feature"]).generatedFiles == Self.featureFiles(integration, screen: Self.screenWithoutPlainInitializer))
		#expect(try #require(output.modules["App"]).generatedFiles == Self.appFiles(integration))
		try expectEveryModuleCompiled(output)
	}

	// MARK: On

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesBothInitializersWithDocumentation_whenModuleConfiguresPlainInitializers() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.singleModuleFiles(rootUser: "LazilyInstantiated<User>"),
			swiftFileContentByFilePath: Self.optingIn,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + Self.screenWithPlainInitializer)
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_user() -> User {
		            User()
		        }
		        let user = LazilyInstantiated<User>(__safeDI_user)
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_08AA1A656B91D4BA.self
		            return Screen(__safeDI_user: user.instance)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(user: user, screen: screen)
		    }
		}
		""")
	}

	// MARK: Hand-written calls

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func handWrittenCall_failsToCompile_whenSeamsModuleDoesNotConfigurePlainInitializers() async throws {
		// Without the setting, the only initializer is the one under `__safeDI_` labels, whose documentation names the
		// setting, so a call written with readable labels does not compile.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.handWrittenCallModules(featureConfiguration: [:]),
			integration: .moduleInfo,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)
		#expect(try #require(output.modules["Feature"]).generatedFiles == Self.featureFiles(.moduleInfo, screen: Self.screenWithoutPlainInitializer))
		guard compileVerificationIsEnabled else { return }
		let failure = try #require(output.compilation?.failure)
		#expect(failure.moduleName == "Caller")
		#expect(failure.standardError.contains("incorrect argument label in call (have 'user:', expected '__safeDI_user:')"), "Unexpected compiler output \(failure.standardError)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func handWrittenCall_compiles_whenSeamsModuleConfiguresPlainInitializers() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.handWrittenCallModules(featureConfiguration: Self.optingIn),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(try #require(output.modules["Feature"]).generatedFiles == Self.featureFiles(.moduleInfo, screen: Self.screenWithPlainInitializer))
		try expectEveryModuleCompiled(output)
	}

	/// `Feature`, with `featureConfiguration`, and `Caller`, which does not use SafeDI yet and calls `Screen` by hand.
	private static func handWrittenCallModules(featureConfiguration: [String: String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: featureFiles(), swiftFileContentByFilePath: featureConfiguration),
			ModuleFixture(
				name: "Caller",
				packageName: "Shop",
				swiftFileContentByFilePath: ["Caller.swift": "import Feature\n\nfunc makeScreen() -> Screen {\n    Screen(user: User())\n}\n"],
				dependencies: ["Feature"],
			),
		]
	}

	// MARK: A hand-written initializer with the readable labels

	@Test(arguments: MultiModuleIntegration.allCases, [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesOnlyInitializerGeneratedCodeCalls_whenSeamDeclaresInitializerWithReadableLabelsAndSeamsModuleDoesNotConfigurePlainInitializers(
		integration: MultiModuleIntegration,
		callersModuleConfiguresPlainInitializers: Bool,
	) async throws {
		// `Screen` keeps the `init(user:)` its callers called before it was a seam. `Feature` does not opt in, so SafeDI
		// generates no `init(user:)` beside it: `App`'s root calls the `__safeDI_` initializer, and `App`'s own call runs
		// the hand-written one. `App`'s setting decides nothing about `Feature`'s seam.
		let screenKeepingHandWrittenInitializer = """
		@Instantiable(generateDependencyTree: true)
		public struct Screen: Instantiable {
		    public init(detailBuilder: Instantiator<Detail>) {
		        self.detailBuilder = detailBuilder
		    }

		    public init(user: User) {
		        self.init(detailBuilder: Instantiator<Detail> { Detail(user: user) })
		    }

		    @Instantiated let detailBuilder: Instantiator<Detail>
		}
		"""
		var appFiles = callersModuleConfiguresPlainInitializers ? Self.optingIn : [:]
		appFiles["Caller.swift"] = "import Feature\n\nfunc makeScreen() -> Screen {\n    Screen(user: User())\n}\n"
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [screenKeepingHandWrittenInitializer] + Self.featureFiles().dropFirst()),
			ModuleFixture(
				name: "App",
				packageName: "Shop",
				swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let screen: Screen"])],
				swiftFileContentByFilePath: appFiles,
				dependencies: ["Feature"],
			),
		], integration: integration, filesToDelete: &filesToDelete)
		#expect(try #require(output.modules["Feature"]).generatedFiles == Self.featureFiles(integration, screen: Self.screenWithoutPlainInitializer))
		#expect(try #require(output.modules["App"]).generatedFiles == Self.appFiles(integration))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenSeamDeclaresInitializerTakingNoArgumentBesideTierTakingNoArgumentAndModuleDoesNotConfigurePlainInitializers() async {
		// A tier that takes no argument has one `init()` whatever the module sets, which a hand-written `init()` would
		// redeclare.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: it declares `init()` at line 7, which can be called with the argument labels of its generated initializer, `init()`. Because the labels match, a call meant for one initializer can run the other instead, or the code can fail to compile. Rename the hand-written initializer's argument labels, or remove it.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let screen: Screen"]),
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(header: Header) {
					        self.header = header
					    }

					    public init() {
					        self.init(header: Header())
					    }

					    @Instantiated let header: Header
					}
					""",
					seamFixtureType(named: "Header", declarations: []),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: A tier that defers no parameter

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesOnlyInitializerGeneratedCodeCalls_whenTierDefersNoParameterAndModuleDoesNotConfigurePlainInitializers() async throws {
		// An instantiator is taken by value, so the tier defers nothing; it still has the `__safeDI_` initializer, which
		// generated code calls.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.singleModuleFiles(rootUser: "Instantiator<User>", userType: "Instantiator<User>"),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_user user: Instantiator<User>) {
		        func __safeDI_detailBuilder() -> Detail {
		            Detail(user: user)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_0C022EBEABB7BCBE {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == Self.rootCallingScreenByInstantiator)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesBothInitializers_whenTierDefersNoParameterAndModuleConfiguresPlainInitializers() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.singleModuleFiles(rootUser: "Instantiator<User>", userType: "Instantiator<User>"),
			swiftFileContentByFilePath: Self.optingIn,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained.
		    public init(user: Instantiator<User>) {
		        self.init(__safeDI_user: user)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_user user: Instantiator<User>) {
		        func __safeDI_detailBuilder() -> Detail {
		            Detail(user: user)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_0C022EBEABB7BCBE {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == Self.rootCallingScreenByInstantiator)
	}

	/// The root `singleModuleFiles(rootUser: "Instantiator<User>", …)` generates, in either setting.
	private static let rootCallingScreenByInstantiator = generatedFileHeader + """
	extension Root {
	    public init() {
	        func __safeDI_user() -> User {
	            User()
	        }
	        let user = Instantiator<User>(__safeDI_user)
	        func __safeDI_screen() -> Screen {
	            _ = Screen.__safeDI_Screen_0C022EBEABB7BCBE.self
	            return Screen(__safeDI_user: user)
	        }
	        let screen: Screen = __safeDI_screen()
	        self.init(user: user, screen: screen)
	    }
	}
	"""

	// MARK: A tier that takes no argument

	/// `Screen`, a seam that takes no argument, since nothing its tree receives comes from outside it.
	private static let argumentlessSeamFiles = [
		seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let cache: Cache"]),
		seamFixtureType(named: "Cache", declarations: []),
	]

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesOneArgumentlessInitializerDocumentedForEveryCaller_whetherOrNotModuleConfiguresPlainInitializers(configuresPlainInitializers: Bool) async throws {
		// A plain `init()` beside the one generated code calls would redeclare it, so the tier has one, which code a person
		// writes can call whatever the setting, as generated code does.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.argumentlessSeamFiles,
			swiftFileContentByFilePath: configuresPlainInitializers ? Self.optingIn : [:],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        let cache = Cache()
		        self.init(cache: cache)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_CBF29CE484222325 {}
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesOneArgumentlessWiderTier_whenModuleConfiguresPlainInitializers() async throws {
		// `theme` is `internal`, so the `public` tier takes no argument: its one `init()` calls the `internal` tier's
		// initializer generated code calls, which has a plain initializer beside it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public struct Badge: Instantiable {
				    init(theme: Theme?) {
				        self.theme = theme
				    }

				    @Received(onlyIfAvailable: true) let theme: Theme?
				}

				struct Theme: Sendable {
				    init() {}
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Service: Instantiable {
				    public init(badge: Badge) {
				        self.badge = badge
				    }

				    @Instantiated public let badge: Badge
				}
				""",
			],
			swiftFileContentByFilePath: Self.optingIn,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Service+SafeDI.swift"] == generatedFileHeader + """
		extension Service {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public convenience init() {
		        self.init(__safeDI_theme: nil)
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained.
		    internal convenience init(theme: Theme?) {
		        self.init(__safeDI_theme: theme)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    internal convenience init(__safeDI_theme: @autoclosure @escaping () -> Theme?) {
		        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
		        let badge = Badge(theme: theme.instance)
		        self.init(badge: badge)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_D6D2DB04D77F61B7 {}
		}
		""")
	}

	// MARK: A public seam called from another package

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicTiersInitializerGeneratedCodeCalls_whenAnotherPackageCallsSeamWhoseModuleConfiguresPlainInitializers(integration: MultiModuleIntegration) async throws {
		// `title` is `public` and `theme` `package`, so `Service` has a `public` and a `package` tier, each with both
		// initializers. `App`, in another package, generates a call of the `public` tier's `__safeDI_` initializer, and
		// `Previews`, in a third, calls the `public` tier's plain initializer by hand.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    package init(theme: Theme?) {
					        self.theme = theme
					    }

					    @Received(onlyIfAvailable: true) package let theme: Theme?
					}

					package struct Theme: Sendable {
					    package init() {}
					}
					""",
					"""
					@Instantiable
					public struct Header: Instantiable {
					    public init(title: String) {
					        self.title = title
					    }

					    @Received public let title: String
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Service: Instantiable {
					    public init(badge: Badge, header: Header) {
					        self.badge = badge
					        self.header = header
					    }

					    @Instantiated public let badge: Badge
					    @Instantiated public let header: Header
					}
					""",
				],
				swiftFileContentByFilePath: Self.optingIn,
			),
			ModuleFixture(
				name: "App",
				packageName: "Other",
				swiftFileContent: [
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class AppRoot: Instantiable {
					    public init(shellBuilder: Instantiator<AppShell>) {
					        self.shellBuilder = shellBuilder
					    }

					    @Instantiated public let shellBuilder: Instantiator<AppShell>
					}
					""",
					"""
					import Feature

					@Instantiable
					public final class AppShell: Instantiable {
					    public init(title: String, service: Service) {
					        self.title = title
					        self.service = service
					    }

					    @Forwarded public let title: String
					    @Instantiated public let service: Service
					}
					""",
				],
				dependencies: ["Feature"],
			),
			ModuleFixture(
				name: "Previews",
				packageName: "Gallery",
				swiftFileContentByFilePath: ["Previews.swift": "import Feature\n\nfunc makeService() -> Service {\n    Service(title: \"Hello\")\n}\n"],
				dependencies: ["Feature"],
			),
		], integration: integration, filesToDelete: &filesToDelete)
		#expect(try #require(output.modules["Feature"]).generatedFiles == [integration == .moduleInfo ? "Feature.swift" : "Service+SafeDI.swift": generatedFileHeader + """
		extension Service {
		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained.
		    public convenience init(title: String) {
		        self.init(__safeDI_title: title)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_title: @autoclosure @escaping () -> String) {
		        self.init(__safeDI_theme: nil, __safeDI_title: __safeDI_title())
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained.
		    package convenience init(theme: Theme?, title: String) {
		        self.init(__safeDI_theme: theme, __safeDI_title: title)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    package convenience init(__safeDI_theme: @autoclosure @escaping () -> Theme?, __safeDI_title: @autoclosure @escaping () -> String) {
		        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
		        let title = LazilyInstantiated<String>(__safeDI_title)
		        let badge = Badge(theme: theme.instance)
		        let header = Header(title: title.instance)
		        self.init(badge: badge, header: header)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_29874EE5B00C89A6 {}
		}
		"""])
		#expect(try #require(output.modules["App"]).generatedFiles == [integration == .moduleInfo ? "App.swift" : "AppRoot+SafeDI.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension AppRoot {
		    public convenience init() {
		        func __safeDI_shellBuilder(title: String) -> AppShell {
		            func __safeDI_service() -> Service {
		                _ = Service.__safeDI_Service_29874EE5B00C89A6.self\(integration.seamCallComment(type: "Service", declaringModule: "Feature"))
		                return Service(__safeDI_title: title)
		            }
		            let service: Service = __safeDI_service()
		            return AppShell(title: title, service: service)
		        }
		        let shellBuilder = Instantiator<AppShell> {
		            __safeDI_shellBuilder(title: $0)
		        }
		        self.init(shellBuilder: shellBuilder)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
	}

	// MARK: Which module's configuration decides

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesNoPlainInitializer_whenOnlyCallersModuleConfiguresPlainInitializers(integration: MultiModuleIntegration) async throws {
		// The setting of the module that declares the seam decides: `App`'s does not reach `Feature`'s generation, whose
		// own run reads only its own configuration, nor `App`'s call.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(appConfiguration: Self.optingIn), integration: integration, filesToDelete: &filesToDelete)
		#expect(try #require(output.modules["Feature"]).generatedFiles == Self.featureFiles(integration, screen: Self.screenWithoutPlainInitializer))
		#expect(try #require(output.modules["App"]).generatedFiles == Self.appFiles(integration))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsInitializerGeneratedCodeCalls_whenOnlySeamsModuleConfiguresPlainInitializers(integration: MultiModuleIntegration) async throws {
		// `Feature` opts in and generates both initializers; `App`, which reads nothing of `Feature`'s setting, generates
		// the same call as when nothing opts in.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(featureConfiguration: Self.optingIn), integration: integration, filesToDelete: &filesToDelete)
		#expect(try #require(output.modules["Feature"]).generatedFiles == Self.featureFiles(integration, screen: Self.screenWithPlainInitializer))
		#expect(try #require(output.modules["App"]).generatedFiles == Self.appFiles(integration))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesModuleInfoFileHoldingSettingAtItsDefault_whenModuleConfiguresPlainInitializers() async throws {
		// No module that reads `Feature`'s `.safedi` reads the setting, so the file holds it at its default, and turning
		// it on or off leaves the file, and the builds that read it, as they were.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(featureConfiguration: Self.optingIn),
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		let moduleInfoFile = try #require(output.modules["Feature"]?.moduleInfoFile)
		#expect(moduleInfoFile.configurations.map(\.generatePlainDependencyTreeInitializers) == [false])
		#expect(try #require(output.modules["Feature"]).generatedFiles == Self.featureFiles(.moduleInfo, screen: Self.screenWithPlainInitializer))
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Expects every module to have compiled, when compile verification runs.
	private func expectEveryModuleCompiled(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 }, sourceLocation: sourceLocation)
	}
}
