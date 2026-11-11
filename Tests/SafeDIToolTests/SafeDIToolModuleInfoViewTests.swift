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

import ArgumentParser
import Foundation
import SafeDICore
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// What a module lists under a build system that runs `generate` once per module: the modules it depends on, whose
/// `.safedi` files carry, in their views, what a seam or public mock of a module they depend on needs, so that none
/// is listed only for that.
struct SafeDIToolModuleInfoViewTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – A seam two modules down

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamOfImportedModule_whenModuleListsOnlyTheModulesItImports(listsClosure: Bool) async throws {
		// Cells 1 and 1b: `App` imports `Feed` and lists it alone, or lists `Feed`'s dependencies too, as 2.2.0 asked. Either
		// way `App` computes `FeedScreen`'s signature from the declarations `Feed` saw, which `Feed`'s `.safedi` carries.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.seamChain(appDependencies: listsClosure ? ["Core", "Feed", "Session"] : ["Feed"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.appCallingFeedScreen()])
		let feedView = try #require(output.modules["Feed"]?.moduleInfoFile?.view)
		#expect(feedView.moduleGraph.map(\.moduleName) == ["Core", "Session"])
		#expect(feedView.declarations.map(\.moduleName) == ["Core", "Session"])
		let appView = try #require(output.modules["App"]?.moduleInfoFile?.view)
		#expect(appView.moduleGraph.map(\.moduleName) == ["Core", "Feed", "Session"])
		#expect(appView.declarations.map(\.moduleName) == ["Core", "Feed", "Session"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamOfImportedModule_whenPluginReadsTargetGraph() async throws {
		// Cell 1 under the SwiftPM plugin, which reads every module's files and never a view: the same call, with the
		// comment a plugin's call carries.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.seamChain(appDependencies: ["Feed"]),
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["Root+SafeDI.swift": Self.appCallingFeedScreenFromPlugin])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_computesSeamFromWhatItsModuleRead_whenSeamsModuleReadNoModuleInfoOfADependency() async throws {
		// Cell 2: `Session` runs no SafeDI, so `Feed`'s run read none of its declarations and records no dependency on it;
		// `FeedScreen` receives `Session`'s `Token` only if available, a pass-through `App` computes from what `Feed` read,
		// and nothing is missing.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: [Self.clock]),
				ModuleFixture(name: "Session", packageName: "Base", swiftFileContent: ["public struct Token {\n    public init() {}\n}"], runsSafeDI: false),
				ModuleFixture(name: "Feed", packageName: "Base", swiftFileContent: [
					"import Core\nimport Session\n\n" + seamFixtureType(named: "FeedScreen", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let clock: Clock", "@Received(onlyIfAvailable: true) let token: Token?"]),
				], dependencies: ["Core", "Session"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Feed\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let feedScreen: FeedScreen"])], dependencies: ["Feed"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feed"]?.moduleInfoFile?.dependencyModuleNames == ["Core"])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.appCallingFeedScreen(guardHash: "029593DA1BB2FBD5", tokenLabel: "token")])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenTwoModuleInfosDescribeOneModuleDifferently(corePackageChanged: Bool) async throws {
		// Cell 2b: `Bar`'s `.safedi` was written against an earlier `Core`, `Feed`'s against the current one, whose
		// declarations or whose package differ.
		var earlierFilesToDelete = [URL]()
		let earlier = try await executeSafeDIToolMultiModuleTest(
			modules: Self.disagreementModules(coreTypeName: "Clock", corePackageName: "Base"),
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &earlierFilesToDelete,
		)
		defer { filesToDelete += earlierFilesToDelete }
		let earlierBarModuleInfo = try #require(earlier.modules["Bar"]?.moduleInfoOutputPath)
		let staleBarModuleInfo = earlierBarModuleInfo + ".stale"
		try FileManager.default.copyItem(atPath: earlierBarModuleInfo, toPath: staleBarModuleInfo)
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let moduleInfoDirectory = URL(fileURLWithPath: fixtures["Bar"]!["BarScreen.swift"]).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ModuleInfo").path
			return "SafeDI was given two module infos that describe module `Core` differently: `\(moduleInfoDirectory)/Bar.safedi` and `\(moduleInfoDirectory)/Feed.safedi` were written against two different builds of `Core`. Build `Core` and the modules that depend on it again, so that every module info is written against the current one."
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.disagreementModules(coreTypeName: corePackageChanged ? "Clock" : "Calendar", corePackageName: corePackageChanged ? "Moved" : "Base"),
				integration: .moduleInfo,
				compileVerification: .skipped,
				moduleInfoOverrides: ["Bar": staleBarModuleInfo],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsOneModuleInfoListedUnderTwoPaths_onlyWhenBothHoldTheSameBytes(filesDiffer: Bool) async throws {
		// Cell 2c: a stale `Core.safedi` beside the current `Core_safedi.safedi`, both recording `Core`.
		let core = try await executeSafeDIToolTest(
			swiftFileContent: [Self.clock],
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "Core"],
		)
		let corePath = try core.writtenModuleInfoOutputPath
		let secondPath: String
		if filesDiffer {
			let otherCore = try await executeSafeDIToolTest(
				swiftFileContent: [Self.clock],
				filesToDelete: &filesToDelete,
				moduleMembershipArguments: ["--module-name", "Core"],
			)
			secondPath = try otherCore.writtenModuleInfoOutputPath
		} else {
			secondPath = corePath + ".copy.safedi"
			try FileManager.default.copyItem(atPath: corePath, toPath: secondPath)
			filesToDelete.append(URL(fileURLWithPath: secondPath))
		}
		if filesDiffer {
			let paths = [corePath, secondPath].map { URL(fileURLWithPath: $0).path }.sorted()
			await assertThrowsError("SafeDI was given two module infos that describe module `Core` differently: `\(paths[0])` and `\(paths[1])` were written against two different builds of `Core`. Build `Core` and the modules that depend on it again, so that every module info is written against the current one.") {
				try await Self.runClockConsumer(dependentModuleInfoPaths: [corePath, secondPath], filesToDelete: &filesToDelete)
			}
		} else {
			let output = try await Self.runClockConsumer(dependentModuleInfoPaths: [corePath, secondPath], filesToDelete: &filesToDelete)
			#expect(output.combinedOutput?.contains("let clock = Clock()") == true)
		}
	}

	/// A root that builds `Core`'s `Clock`, given `dependentModuleInfoPaths`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func runClockConsumer(dependentModuleInfoPaths: [String], filesToDelete: inout [URL]) async throws -> TestOutput {
		try await executeSafeDIToolTest(
			swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let clock: Clock"])],
			dependentModuleInfoPaths: dependentModuleInfoPaths,
			buildCombinedOutput: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingModuleItIsDeclaredIn_whenOnlyAViewCarriesTheTypeItsTreeBuilds() async {
		// Cell 3: `App` builds `Clock`, which only `Feed`'s view carries: the view never fulfills a type of `App`'s trees.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):12:5: error: No @Instantiable declaration of a module this module lists fulfills `Clock`, which @Instantiated property `clock: Clock` instantiates. `Clock` is declared in `Core`, which this module depends on through `Feed` but does not list; list `Core` where this module lists `Feed`: list its `<name>_safedi` target in this target's `safedi_deps` under Bazel, list its module in the `dependencies:` of this target's `SafeDI.preCompileScript` under Tuist, or pass its `.safedi` with `--dependent-module-info-file-path` in another build.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.seamChain(appDependencies: ["Feed"], rootAlsoBuildsClock: true),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingModuleWhoseConfigurationAddsDirectory_whenOnlyAViewCarriesTypeFromThatDirectory() async {
		// Cell 27: `Clock` is declared in a directory `Core`'s `#SafeDIConfiguration` adds, which records no module, and
		// only `Feed`'s view carries it. `Core`'s `.safedi` carries the declarations that directory holds, so `App` is told
		// to list `Core`, which fulfills `Clock` as it would a type `Core`'s own files declare.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):11:5: error: No @Instantiable declaration of a module this module lists fulfills `Clock`, which @Instantiated property `clock: Clock` instantiates. `Clock` is declared in `Core`, which this module depends on through `Feed` but does not list; list `Core` where this module lists `Feed`: list its `<name>_safedi` target in this target's `safedi_deps` under Bazel, list its module in the `dependencies:` of this target's `SafeDI.preCompileScript` under Tuist, or pass its `.safedi` with `--dependent-module-info-file-path` in another build.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Extra", packageName: "Base", swiftFileContent: [Self.clock], runsSafeDI: false),
					ModuleFixture(name: "Core", packageName: "Base", swiftFileContentByFilePath: [
						"SafeDIConfiguration.swift": "#SafeDIConfiguration(additionalDirectoriesToInclude: [\"$FIXTURE_ROOT/Base/Sources/Extra\"])\n",
					]),
					ModuleFixture(name: "Feed", packageName: "Base", swiftFileContent: [
						"import Core\n\n" + seamFixtureType(named: "FeedScreen", isSeam: true, isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let token: Token?"]) + "\n\npublic struct Token {\n    public init() {}\n}",
					], dependencies: ["Core"]),
					ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
						"import Feed\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let feedScreen: FeedScreen", "@Instantiated let clock: Clock"]),
					], dependencies: ["Feed"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fulfillsTypeFromListedModuleWithoutDuplicateError_whenAViewCarriesItToo() async throws {
		// Cell 4: `App` lists `Core` too, so `Clock` is fulfilled, once, though `Feed`'s view carries `Core` as well.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.seamChain(appDependencies: ["Core", "Feed"], rootAlsoBuildsClock: true),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles.keys.sorted() == ["App.swift"])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsNestedSeams_whenOnlyTheOuterSeamsModuleIsListed(integration: MultiModuleIntegration) async throws {
		// Cell 6: `Feed`'s seam reaches `Session`'s seam; `App` lists `Feed` alone and computes both signatures.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.seamChain(appDependencies: ["Feed"], sessionIsSeam: true),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let appFiles = output.modules["App"]?.generatedFiles ?? [:]
		// `Session`'s seam takes `token: Token?`, which `FeedScreen` passes on: the same signature as when `Session` is built
		// inline.
		#expect(appFiles == (integration == .moduleInfo ? ["App.swift": Self.appCallingFeedScreen()] : ["Root+SafeDI.swift": Self.appCallingFeedScreenFromPlugin]))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: [(MultiModuleIntegration.moduleInfo, false), (.moduleInfo, true), (.swiftPackagePlugin, false)])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicMockAsItsModuleGeneratedIt_whenPublicMocksChainThreeModulesBeneathIt(integration: MultiModuleIntegration, listsClosure: Bool) async throws {
		// Cell 5b: `Feed`'s public mock calls `Session`'s, which calls `Core`'s, which builds `Base`'s `BaseThing`. `App`
		// computes each signature as its module did, from the declarations that module saw, so its call names the enum
		// `Feed` generated, whether it lists `Feed` alone or every module.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.publicMockChain(appDependencies: listsClosure ? ["Base", "Core", "Feed", "Session"] : ["Feed"]),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == (integration == .moduleInfo
				? ["App.swift": Self.appCallingFeedServiceMock(carriesPluginComment: false)]
				: ["AppFeature+SafeDIMock.swift": Self.appCallingFeedServiceMock(carriesPluginComment: true), "SafeDIMockConfiguration.swift": Self.publicMockChainImports + "\n\n"]))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: ["internal ", "", "private "])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_computesSeamFromViewAsSeamsModuleComputesIt_whenParameterTypeSpellsItsAccessInsideExtension(spelling: String) async throws {
		// Cells 22a and 22b: `Core`'s seam `CoreScreen` receives `Token` only if available, which spells `internal` or
		// nothing inside `public extension Namespace`, or `internal` inside a `private` extension, so `CoreScreen`'s `public`
		// initializer takes it or not. `App` computes `FeedScreen`'s signature, and so `CoreScreen`'s, from `Feed`'s view:
		// positions are stripped from a view, never whether a modifier is spelled, so `App` computes them exactly as from
		// `Core`'s own file.
		let extensionSpelling = spelling == "private " ? "private extension" : "public extension"
		let tokenSpelling = spelling == "private " ? "internal " : spelling
		let modules = { (appDependencies: [String]) in
			[
				ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: [
					"""
					public enum Namespace {}

					\(extensionSpelling) Namespace {
					    \(tokenSpelling)struct Token {}
					}

					@Instantiable
					public struct Clock: Instantiable {
					    public init() {}
					}

					@Instantiable(generateDependencyTree: true)
					public struct CoreScreen: Instantiable {
					    init(clock: Clock, token: Namespace.Token?) {
					        self.clock = clock
					        self.token = token
					    }

					    @Instantiated let clock: Clock
					    @Received(onlyIfAvailable: true) let token: Namespace.Token?
					}
					""",
				]),
				ModuleFixture(name: "Feed", packageName: "Other", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "FeedScreen", isSeam: true, declarations: ["@Instantiated let coreScreen: CoreScreen"])], dependencies: ["Core"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Feed\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let feedScreen: FeedScreen"])], dependencies: appDependencies),
			]
		}
		let viewOutput = try await executeSafeDIToolMultiModuleTest(modules: modules(["Feed"]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		let directOutput = try await executeSafeDIToolMultiModuleTest(modules: modules(["Core", "Feed"]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(viewOutput.modules["App"]?.generatedFiles == directOutput.modules["App"]?.generatedFiles)
		// `Token` spelled `internal` keeps `CoreScreen`'s `public` tier from taking it; unspelled, it is `public`.
		let callComment = MultiModuleIntegration.moduleInfo.seamCallComment(type: "FeedScreen", declaringModule: "Feed")
		let call = spelling == "" ? "FeedScreen.__safeDI_FeedScreen_DD887236DB7407AA.self\(callComment)\n            return FeedScreen(__safeDI_token: nil)" : "FeedScreen.__safeDI_FeedScreen_CBF29CE484222325.self\(callComment)\n            return FeedScreen()"
		#expect(viewOutput.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + Self.importBlock("Core") + "\n" + Self.importBlock("Feed") + "\n\n" + """
		extension Root {
		    public init() {
		        func __safeDI_feedScreen() -> FeedScreen {
		            _ = \(call)
		        }
		        let feedScreen: FeedScreen = __safeDI_feedScreen()
		        self.init(feedScreen: feedScreen)
		    }
		}
		"""])
		try expectEveryModuleCompiled(viewOutput)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_computesSeamOnce_whenOwnTreeAndAnotherModulesSeamBothReachIt() async throws {
		// Cell 6b: `Session`'s seam is reached by `App`'s own tree, through `App`'s own `Session.safedi`, and by `Feed`'s seam,
		// through `Feed`'s view: one signature, the same call in both places.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.seamChain(appDependencies: ["Feed", "Session"], sessionIsSeam: true, rootAlsoBuildsSession: true),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + Self.importBlock("Core") + "\n" + Self.importBlock("Feed") + "\n" + Self.importBlock("Session") + "\n\n" + """
		extension Root {
		    public init() {
		        func __safeDI_feedScreen() -> FeedScreen {
		            _ = FeedScreen.__safeDI_FeedScreen_F046DCFB1718557F.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "FeedScreen", declaringModule: "Feed"))
		            return FeedScreen(__safeDI_token: nil)
		        }
		        let feedScreen: FeedScreen = __safeDI_feedScreen()
		        func __safeDI_session() -> Session {
		            _ = Session.__safeDI_Session_029593DA1BB2FBD5.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Session", declaringModule: "Session"))
		            return Session(token: nil)
		        }
		        let session: Session = __safeDI_session()
		        self.init(feedScreen: feedScreen, session: session)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesNestedTypeAsSeamsModuleDoes_whenCallerDeclaresTopLevelTypeOfItsName(integration: MultiModuleIntegration) async throws {
		// Cell 30: `Core`'s seam `CoreScreen` builds `Settings`, its nested type, spelled unqualified; `App` declares a
		// top-level `Settings` too. A view holds `Core`'s declarations unnormalized, so `App`'s computation of
		// `CoreScreen`'s signature, through `Feed`, qualifies `Settings` among `Core`'s declarations, as `Core`'s own run did.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: [
					"""
					@Instantiable(generateDependencyTree: true)
					public struct CoreScreen: Instantiable {
					    public init(settings: Settings) {
					        self.settings = settings
					    }

					    @Instantiated let settings: Settings

					    @Instantiable
					    public struct Settings: Instantiable {
					        public init(theme: Theme?) {
					            self.theme = theme
					        }

					        @Received(onlyIfAvailable: true) let theme: Theme?
					    }
					}

					public struct Theme {
					    public init() {}
					}
					""",
				]),
				ModuleFixture(name: "Feed", packageName: "Base", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "FeedScreen", isSeam: true, declarations: ["@Instantiated let coreScreen: CoreScreen"])], dependencies: ["Core"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
					seamFixtureType(named: "Settings", declarations: []),
					"import Feed\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let feedScreen: FeedScreen", "@Instantiated let settings: Settings"]),
				], dependencies: ["Feed"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let fileName = integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift"
		let pluginComment = integration.seamCallComment(type: "FeedScreen", declaringModule: "Feed")
		#expect(output.modules["App"]?.generatedFiles == [fileName: generatedFileHeader + Self.importBlock("Core") + "\n" + Self.importBlock("Feed") + "\n\n" + """
		extension Root {
		    public init() {
		        func __safeDI_feedScreen() -> FeedScreen {
		            _ = FeedScreen.__safeDI_FeedScreen_84123128579D77AB.self\(pluginComment)
		            return FeedScreen(__safeDI_theme: nil)
		        }
		        let feedScreen: FeedScreen = __safeDI_feedScreen()
		        let settings = Settings()
		        self.init(feedScreen: feedScreen, settings: settings)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
	}

	// MARK: Tests – Access and spelling read through a view

	@Test(arguments: [(MultiModuleIntegration.moduleInfo, false), (.moduleInfo, true), (.swiftPackagePlugin, false)])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtProvider_whenTierComputedFromViewOmitsValueCallerInAnotherPackageProvides(integration: MultiModuleIntegration, listsCore: Bool) async {
		// Cell 7: `Feed`'s seam `Service` builds `Core`'s `Badge`, whose `package` initializer is the widest that mentions
		// `[3 of Int]`, so SafeDI proves the type `package` and `Service`'s `public` tier omits `theme`. `App`, in another
		// package, reads `Badge` from `Feed`'s view when it lists `Feed` alone: its `Screen`, which provides `theme`, gets the
		// error a run that reads `Core`'s own file reports, and no error names a module info `App` was not given. A view
		// carries no positions, so the note at `Badge`'s receive names no line until `App` lists `Core` too.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let screenPath: String
			let badgeNoteLocation: String
			switch integration {
			case .moduleInfo:
				screenPath = fixtures["App"]!["Screen.swift"]
				badgeNoteLocation = listsCore ? "\(fixtures["Core"]!["Badge.swift"]):7:5: " : ""
			case .swiftPackagePlugin:
				screenPath = NormalizedFilePath(fixtures["App"]!.compilerPath(of: "Screen.swift")).path
				badgeNoteLocation = "\(NormalizedFilePath(fixtures["Core"]!.compilerPath(of: "Badge.swift")).path):7:5: "
			}
			return """
			\(screenPath):11:5: error: `Screen` provides `theme: [3 of Int]`, but the `public` initializer SafeDI generated for `Service` in module `Feed`, the narrowest one module `App` can call, does not take it: `Service` takes `theme` only on its `package` initializer, so this call would pass `nil` to `Badge`, which the tree would hand `theme` were it built inline. `[3 of Int]` is `package` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feed` or on a type that receives it is `package` (`Badge.init(theme:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `Badge.init(theme:)` to `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; or stop providing `theme` on this path.
			\(badgeNoteLocation)note: `Badge` receives `theme: [3 of Int]?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.packageMentionChain(appPackage: "Other", appDependencies: listsCore ? ["Core", "Feed"] : ["Feed"]), integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesValueToPackageTierComputedFromView_whenCallerSharesSeamsPackage(integration: MultiModuleIntegration) async throws {
		// Cell 7's twin: `App` in `Service`'s package calls its `package` tier, which takes `theme`, so `Screen`'s `theme`
		// reaches `Badge`, as when `App` lists `Core` too.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.packageMentionChain(appPackage: "Shop"), integration: integration, filesToDelete: &filesToDelete)
		let directOutput = try await executeSafeDIToolMultiModuleTest(modules: Self.packageMentionChain(appPackage: "Shop", appDependencies: ["Core", "Feed"]), integration: integration, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == directOutput.modules["App"]?.generatedFiles)
		let fileName = integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift"
		let pluginComment = integration.seamCallComment(type: "Service", declaringModule: "Feed")
		#expect(output.modules["App"]?.generatedFiles == [fileName: generatedFileHeader + Self.importBlock("Core") + "\n" + Self.importBlock("Feed") + "\n" + Self.importBlock("SafeDI") + "\n\n" + """
		extension Root {
		    public init() {
		        func __safeDI_screenBuilder(theme: [3 of Int]) -> Screen {
		            func __safeDI_service() -> Service {
		                _ = Service.__safeDI_Service_5B09C61C1791E548.self\(pluginComment)
		                return Service(__safeDI_theme: theme)
		            }
		            let service: Service = __safeDI_service()
		            return Screen(theme: theme, service: service)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(theme: $0)
		        }
		        self.init(screenBuilder: screenBuilder)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicMockAsItsModuleComputesIt_whenAnotherFileOfModuleDeclaresPrivateTypeOfExtendedTypesName(integration: MultiModuleIntegration) async throws {
		// Cell 25: `Core` declares the public mock `Space.Panel` in an extension of `Kit`'s `public` `Space`, and another of
		// its files declares a `private` `Space`, invisible where the extension is. Whether `Panel` can have a public mock
		// depends on which `Space` the extension extends: `Kit`'s, as `Core`'s own run finds, so `Feed`'s public mock calls
		// `Panel`'s. `App` lists `Feed` alone and computes both plans through `Feed`'s view, which keeps each declaration's
		// file and level, so its call is the one it makes when it lists `Core` too. (The extended type bounds a public mock,
		// not a seam's parameter, whose type's own declaration decides its tier.)
		let modules = { (appDependencies: [String]) in
			[
				ModuleFixture(name: "Kit", packageName: "Toolkit", swiftFileContentByFilePath: ["Space.swift": "// The design system's namespace.\npublic enum Space {}"]),
				ModuleFixture(name: "Core", packageName: "Base", swiftFileContentByFilePath: [
					"Panel.swift": """
					import Kit

					extension Space {
					    @Instantiable(generateMock: .public)
					    public final class Panel: Instantiable {
					        init() {}
					    }
					}
					""",
					"Palette.swift": """
					// A file-private type that shares the extended type's name.
					private enum Space {
					    static let accent = 4
					}

					@Instantiable
					public struct Palette: Instantiable {
					    public init() {
					        accent = Space.accent
					    }

					    let accent: Int
					}
					""",
				], dependencies: ["Kit"]),
				ModuleFixture(name: "Feed", packageName: "Feed", swiftFileContentByFilePath: ["FeedService.swift": """
				import Core
				import Kit

				@Instantiable(generateMock: .public)
				public final class FeedService: Instantiable {
				    init(panel: Space.Panel) {
				        self.panel = panel
				    }

				    @Instantiated private let panel: Space.Panel
				}
				"""], dependencies: ["Core", "Kit"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppFeature.swift": """
				import Feed

				@Instantiable(generateMock: true)
				public final class AppFeature: Instantiable {
				    public init(feedService: FeedService) {
				        self.feedService = feedService
				    }

				    @Instantiated private let feedService: FeedService
				}
				"""], dependencies: appDependencies),
			]
		}
		let viewOutput = try await executeSafeDIToolMultiModuleTest(modules: modules(["Feed"]), integration: integration, filesToDelete: &filesToDelete)
		let directOutput = try await executeSafeDIToolMultiModuleTest(modules: modules(["Core", "Feed", "Kit"]), integration: integration, filesToDelete: &filesToDelete)
		#expect(viewOutput.modules["App"]?.generatedFiles == directOutput.modules["App"]?.generatedFiles)
		let imports = generatedFileHeader + Self.importBlock("Core") + "\n" + Self.importBlock("Feed") + "\n" + Self.importBlock("Kit")
		let pluginComment = integration.seamCallComment(type: "FeedService", declaringModule: "Feed")
		// `App`'s mock calls `FeedService`'s, which calls `Space.Panel`'s, under the enum `Feed` generated.
		let appMock = imports + "\n\n" + """
		#if DEBUG
		extension AppFeature {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            feedService: FeedService.SafeDIOverrides = .init()
		        ) {
		            self.feedService = feedService
		        }

		        let feedService: FeedService.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> AppFeature {
		        _ = FeedService.__safeDI_FeedService_mock_51799E6AA5E7B634.self\(pluginComment)
		        let feedService = FeedService.mock(safeDIOverrides: safeDIOverrides.feedService)
		        return AppFeature(feedService: feedService)
		    }
		}
		#endif
		"""
		#expect(viewOutput.modules["App"]?.generatedFiles == (integration == .moduleInfo
				? ["App.swift": appMock]
				: ["AppFeature+SafeDIMock.swift": appMock, "SafeDIMockConfiguration.swift": imports + "\n\n"]))
		try expectEveryModuleCompiled(viewOutput)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_computesSeamFromViewAsSeamsModuleComputesIt_whenParameterTypesAreNestedAndModuleQualified(integration: MultiModuleIntegration) async throws {
		// Cell 26: `Feed`'s seam `FeedScreen` builds its nested `Settings`, spelled unqualified, which receives `Session`'s
		// `Token` only if available, spelled `Session.Token`, qualified by its module. `Mid`'s seam `MidScreen` builds a
		// `FeedScreen`, and `App`, listing `Mid` alone, computes both signatures through `Mid`'s view: the nested
		// computation normalizes `Feed`'s declarations as `Feed`'s run did, so the call is the one `App` makes when it lists
		// every module.
		let modules = { (appDependencies: [String]) in
			[
				ModuleFixture(name: "Session", packageName: "Base", swiftFileContent: ["public struct Token {\n    public init() {}\n}"]),
				ModuleFixture(name: "Feed", packageName: "Base", swiftFileContent: [
					"""
					import Session

					@Instantiable(generateDependencyTree: true)
					public struct FeedScreen: Instantiable {
					    public init(settings: Settings) {
					        self.settings = settings
					    }

					    @Instantiated let settings: Settings

					    @Instantiable
					    public struct Settings: Instantiable {
					        public init(token: Session.Token?) {
					            self.token = token
					        }

					        @Received(onlyIfAvailable: true) let token: Session.Token?
					    }
					}
					""",
				], dependencies: ["Session"]),
				ModuleFixture(name: "Mid", packageName: "Base", swiftFileContent: ["import Feed\n\n" + seamFixtureType(named: "MidScreen", isSeam: true, declarations: ["@Instantiated let feedScreen: FeedScreen"])], dependencies: ["Feed"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Mid\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let midScreen: MidScreen"])], dependencies: appDependencies),
			]
		}
		let viewOutput = try await executeSafeDIToolMultiModuleTest(modules: modules(["Mid"]), integration: integration, filesToDelete: &filesToDelete)
		let directOutput = try await executeSafeDIToolMultiModuleTest(modules: modules(["Feed", "Mid", "Session"]), integration: integration, filesToDelete: &filesToDelete)
		#expect(viewOutput.modules["App"]?.generatedFiles == directOutput.modules["App"]?.generatedFiles)
		let fileName = integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift"
		let pluginComment = integration.seamCallComment(type: "MidScreen", declaringModule: "Mid")
		// `token` passes through `MidScreen` and `FeedScreen` to `FeedScreen.Settings`, which receives it only if available.
		#expect(viewOutput.modules["App"]?.generatedFiles == [fileName: generatedFileHeader + Self.importBlock("Feed") + "\n" + Self.importBlock("Mid") + "\n" + Self.importBlock("Session") + "\n\n" + """
		extension Root {
		    public init() {
		        func __safeDI_midScreen() -> MidScreen {
		            _ = MidScreen.__safeDI_MidScreen_1AE937BC12D77A01.self\(pluginComment)
		            return MidScreen(__safeDI_token: nil)
		        }
		        let midScreen: MidScreen = __safeDI_midScreen()
		        self.init(midScreen: midScreen)
		    }
		}
		"""])
		try expectEveryModuleCompiled(viewOutput)
	}

	// MARK: Tests – Names

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenModuleInfoOutputIsGivenWithoutModuleName() async {
		// Cell 8: a module info file names the module it describes.
		await assertThrowsError("'--module-info-output' requires '--module-name': a module info file names the module it describes.") {
			try await Generate.parse(["Sources.csv", "--module-info-output", "Module.safedi"]).generate()
		}
	}

	// MARK: Tests – Writes

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_leavesOutputsUntouched_whenRunAgainOverUnchangedInputs() async throws {
		// Cells 10c and 10d: a second run over the same inputs writes neither output, so their modification dates stay.
		let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
		filesToDelete.append(fixtureDirectory)
		let source = fixtureDirectory.appendingPathComponent("Clock.swift")
		try Self.clock.write(to: source, atomically: true, encoding: .utf8)
		let csv = fixtureDirectory.appendingPathComponent("Sources.csv")
		try source.path.write(to: csv, atomically: true, encoding: .utf8)
		let combinedOutput = fixtureDirectory.appendingPathComponent("Core.swift")
		let moduleInfoOutput = fixtureDirectory.appendingPathComponent("Core.safedi")
		let arguments = [csv.path, "--combined-output", combinedOutput.path, "--module-info-output", moduleInfoOutput.path, "--module-name", "Core"]
		try await Generate.parse(arguments).generate()
		let past = Date(timeIntervalSince1970: 1_000_000_000)
		for output in [combinedOutput, moduleInfoOutput] {
			try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: output.path)
		}
		try await Generate.parse(arguments).generate()
		for output in [combinedOutput, moduleInfoOutput] {
			#expect(try FileManager.default.attributesOfItem(atPath: output.path)[.modificationDate] as? Date == past)
		}
		// A declaration that changes the generated code writes both again.
		try (Self.clock + "\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let clock: Clock"])).write(to: source, atomically: true, encoding: .utf8)
		try await Generate.parse(arguments).generate()
		for output in [combinedOutput, moduleInfoOutput] {
			#expect(try FileManager.default.attributesOfItem(atPath: output.path)[.modificationDate] as? Date != past)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesNoModuleInfo_whenRunFails() async throws {
		// Cell 28: a run that fails leaves the module info an earlier run wrote exactly as it was.
		let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
		filesToDelete.append(fixtureDirectory)
		let source = fixtureDirectory.appendingPathComponent("Root.swift")
		try seamFixtureType(named: "Root", isRoot: true, declarations: []).write(to: source, atomically: true, encoding: .utf8)
		let csv = fixtureDirectory.appendingPathComponent("Sources.csv")
		try source.path.write(to: csv, atomically: true, encoding: .utf8)
		let moduleInfoOutput = fixtureDirectory.appendingPathComponent("App.safedi")
		let arguments = [csv.path, "--combined-output", fixtureDirectory.appendingPathComponent("App.swift").path, "--module-info-output", moduleInfoOutput.path, "--module-name", "App"]
		try await Generate.parse(arguments).generate()
		let writtenBytes = try Data(contentsOf: moduleInfoOutput)
		try seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let missing: Missing"]).write(to: source, atomically: true, encoding: .utf8)
		do {
			try await Generate.parse(arguments).generate()
			Issue.record("Did not throw error!")
		} catch {}
		#expect(try Data(contentsOf: moduleInfoOutput) == writtenBytes)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesDependentsModuleInfo_onlyWhenADeclarationASignatureCanReadChanges() async throws {
		// Cells 10a and 10b: a line moved in `Core` changes `Core.safedi` alone; a receive added beneath `Feed`'s seam
		// changes `App.safedi` too.
		let base = try await executeSafeDIToolMultiModuleTest(modules: Self.seamChain(appDependencies: ["Feed"]), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let moved = try await executeSafeDIToolMultiModuleTest(modules: Self.seamChain(appDependencies: ["Feed"], clockLeadingLines: 3), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let received = try await executeSafeDIToolMultiModuleTest(modules: Self.seamChain(appDependencies: ["Feed"], clockReceivesDate: true), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		func viewBytes(of output: MultiModuleTestOutput, _ moduleName: String) throws -> [UInt8] {
			var writer = BinaryWriter()
			try writer.write(#require(output.modules[moduleName]?.moduleInfoFile?.view))
			return writer.encoded
		}
		func ownDeclarationBytes(of output: MultiModuleTestOutput, _ moduleName: String) throws -> [UInt8] {
			var writer = BinaryWriter()
			try writer.write(#require(output.modules[moduleName]?.moduleInfoFile?.instantiables))
			return writer.encoded
		}
		// Fixture paths differ between runs, so the views are compared as the paths they hold allow: positions alone.
		#expect(try ownDeclarationBytes(of: base, "Core") != ownDeclarationBytes(of: moved, "Core"))
		#expect(try Self.withoutFixtureRoot(viewBytes(of: base, "App"), base) == Self.withoutFixtureRoot(viewBytes(of: moved, "App"), moved))
		#expect(try Self.withoutFixtureRoot(viewBytes(of: base, "App"), base) != Self.withoutFixtureRoot(viewBytes(of: received, "App"), received))
	}

	// MARK: Tests – A view seam named like this module's type

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsOwnTypeInline_whenSeamOnlyAViewCarriesSharesItsName(integration: MultiModuleIntegration) async throws {
		// Cell 24: `App` declares `Settings` and builds it; `Feed`'s seam reaches `Session`'s seam, also `Settings`.
		let modules = Self.settingsCollisionModules
		switch integration {
		case .moduleInfo:
			let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: integration, filesToDelete: &filesToDelete)
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + Self.importBlock("Feed") + "\n" + Self.importBlock("Session") + "\n\n" + """
			extension Root {
			    public init() {
			        func __safeDI_feedScreen() -> FeedScreen {
			            _ = FeedScreen.__safeDI_FeedScreen_84123128579D77AB.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "FeedScreen", declaringModule: "Feed"))
			            return FeedScreen(__safeDI_theme: nil)
			        }
			        let feedScreen: FeedScreen = __safeDI_feedScreen()
			        let settings = Settings()
			        self.init(feedScreen: feedScreen, settings: settings)
			    }
			}
			"""])
			try expectEveryModuleCompiled(output)
		case .swiftPackagePlugin:
			// The plugin's graph lists `Session` among `App`'s modules, whose `Settings` therefore fulfills `App`'s too.
			await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
				let appSettingsPath = NormalizedFilePath(fixtures["App"]!.compilerPath(of: "Settings.swift")).path
				let sessionSettingsPath = NormalizedFilePath(fixtures["Session"]!.compilerPath(of: "Settings.swift")).path
				return """
				\(appSettingsPath):3:1: error: `Settings` is declared in modules `App` and `Session`. SafeDI tells apart by name the @Instantiable types a module can name, and every seam and public mock a run reads. Rename one.
				\(sessionSettingsPath):1:1: error: `Settings` is declared in modules `App` and `Session`. SafeDI tells apart by name the @Instantiable types a module can name, and every seam and public mock a run reads. Rename one.
				"""
			}) {
				try await executeSafeDIToolMultiModuleTest(modules: modules, integration: integration, filesToDelete: &filesToDelete)
			}
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Clock`, `Core`'s `@Instantiable`.
	private static let clock = """
	@Instantiable
	public final class Clock: Instantiable {
	    public init() {}
	}
	"""

	/// `Core` declares `Clock`; `Session` declares `Session`, which builds a `Clock` and receives `token: Token?` only if
	/// available, where `Token` is `Session`'s plain type; `Feed` declares the seam `FeedScreen`, which builds a `Session`;
	/// `App` builds a `FeedScreen` from its root and imports `Feed` alone.
	private static func seamChain(
		appDependencies: [String],
		sessionRunsSafeDI: Bool = true,
		sessionIsSeam: Bool = false,
		rootAlsoBuildsClock: Bool = false,
		rootAlsoBuildsSession: Bool = false,
		clockLeadingLines: Int = 0,
		clockReceivesDate: Bool = false,
	) -> [ModuleFixture] {
		let clock = String(repeating: "\n", count: clockLeadingLines) + (clockReceivesDate
			? """
			public struct Date {}

			@Instantiable
			public final class Clock: Instantiable {
			    public init(date: Date?) {
			        self.date = date
			    }

			    @Received(onlyIfAvailable: true) let date: Date?
			}
			"""
			: Self.clock)
		return [
			ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: [clock]),
			ModuleFixture(name: "Session", packageName: "Base", swiftFileContent: [
				"""
				import Core

				public struct Token {
				    public init() {}
				}

				@Instantiable\(sessionIsSeam ? "(generateDependencyTree: true)" : "")
				public final class Session: Instantiable {
				    public init(clock: Clock, token: Token?) {
				        self.clock = clock
				        self.token = token
				    }

				    @Instantiated let clock: Clock
				    @Received(onlyIfAvailable: true) let token: Token?
				}
				""",
			], dependencies: ["Core"], runsSafeDI: sessionRunsSafeDI),
			ModuleFixture(name: "Feed", packageName: "Base", swiftFileContent: [
				"import Session\n\n" + seamFixtureType(named: "FeedScreen", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let session: Session"]),
			], dependencies: sessionIsSeam ? ["Session"] : ["Core", "Session"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
				"import Feed\n" + (rootAlsoBuildsClock ? "import Core\n" : "") + (rootAlsoBuildsSession ? "import Session\n" : "") + "\n" + seamFixtureType(
					named: "Root",
					isRoot: true,
					declarations: ["@Instantiated let feedScreen: FeedScreen"] + (rootAlsoBuildsClock ? ["@Instantiated let clock: Clock"] : []) + (rootAlsoBuildsSession ? ["@Instantiated let session: Session"] : []),
				),
			], dependencies: appDependencies),
		]
	}

	/// `Core`, in package `Shop`, declares `Badge`, whose `package` initializer receives `theme: [3 of Int]?` only if
	/// available; `Feed`, in `Shop`, declares the seam `Service`, which builds a `Badge`; `App`, in `appPackage`, lists
	/// `appDependencies`, and its `Screen`, which `Root` builds through an instantiator, forwards `theme` and builds a `Service`.
	private static func packageMentionChain(appPackage: String, appDependencies: [String] = ["Feed"]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: [
				"@Instantiable\npublic struct Badge: Instantiable {\n    package init(theme: [3 of Int]?) {\n        self.theme = theme\n    }\n\n    @Received(onlyIfAvailable: true) let theme: [3 of Int]?\n}",
			]),
			ModuleFixture(name: "Feed", packageName: "Shop", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"])], dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: appPackage, swiftFileContent: [
				"import Feed\nimport SafeDI\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let screenBuilder: Instantiator<Screen>"]),
				"import Feed\nimport SafeDI\n\n" + seamFixtureType(named: "Screen", declarations: ["@Forwarded let theme: [3 of Int]", "@Instantiated let service: Service"]),
			], dependencies: appDependencies),
		]
	}

	/// `Base` declares `BaseThing`; `Core`, `Session` and `Feed` each declare a public mock with an `internal` initializer,
	/// `CoreService` building a `BaseThing`, `SessionService` a `CoreService` and `FeedService` a `SessionService`, each
	/// module listing the one beneath it; `App`'s mocked `AppFeature` builds a `FeedService`.
	private static func publicMockChain(appDependencies: [String]) -> [ModuleFixture] {
		func publicMockType(named name: String, building dependency: (label: String, type: String)) -> String {
			"""
			@Instantiable(generateMock: .public)
			public final class \(name): Instantiable {
			    init(\(dependency.label): \(dependency.type)) {
			        self.\(dependency.label) = \(dependency.label)
			    }

			    @Instantiated private let \(dependency.label): \(dependency.type)
			}
			"""
		}
		return [
			ModuleFixture(name: "Base", packageName: "Base", swiftFileContent: [
				"""
				@Instantiable
				public final class BaseThing: Instantiable {
				    public init() {}
				}
				""",
			]),
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: ["import Base\n\n" + publicMockType(named: "CoreService", building: ("baseThing", "BaseThing"))], dependencies: ["Base"]),
			ModuleFixture(name: "Session", packageName: "Session", swiftFileContent: ["import Core\n\n" + publicMockType(named: "SessionService", building: ("coreService", "CoreService"))], dependencies: ["Core"]),
			ModuleFixture(name: "Feed", packageName: "Feed", swiftFileContent: ["import Session\n\n" + publicMockType(named: "FeedService", building: ("sessionService", "SessionService"))], dependencies: ["Session"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppFeature.swift": """
			import Feed

			@Instantiable(generateMock: true)
			public final class AppFeature: Instantiable {
			    public init(feedService: FeedService) {
			        self.feedService = feedService
			    }

			    @Instantiated private let feedService: FeedService
			}
			"""], dependencies: appDependencies),
		]
	}

	/// The header and imports of `App`'s generated files: what the files of `Feed`, `Session`, `Core` and `Base` import.
	private static let publicMockChainImports = generatedFileHeader + importBlock("Base") + "\n" + importBlock("Core") + "\n" + importBlock("Feed") + "\n" + importBlock("Session")

	/// `App`'s mock of `AppFeature`, which calls `FeedService`'s public mock under the enum `Feed` generated.
	private static func appCallingFeedServiceMock(carriesPluginComment: Bool) -> String {
		publicMockChainImports + "\n\n" + """
		#if DEBUG
		extension AppFeature {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            feedService: FeedService.SafeDIOverrides = .init()
		        ) {
		            self.feedService = feedService
		        }

		        let feedService: FeedService.SafeDIOverrides
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> AppFeature {
		        _ = FeedService.__safeDI_FeedService_mock_51799E6AA5E7B634.self\((carriesPluginComment ? MultiModuleIntegration.swiftPackagePlugin : .moduleInfo).seamCallComment(type: "FeedService", declaringModule: "Feed"))
		        let feedService = FeedService.mock(safeDIOverrides: safeDIOverrides.feedService)
		        return AppFeature(feedService: feedService)
		    }
		}
		#endif
		"""
	}

	/// `Feed` and `Bar` each declare a seam that builds `Core`'s type named `coreTypeName`; `App` lists both.
	private static func disagreementModules(coreTypeName: String, corePackageName: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: corePackageName, swiftFileContent: [seamFixtureType(named: coreTypeName, isFinalClass: true, declarations: [])]),
			ModuleFixture(name: "Bar", packageName: "Base", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "BarScreen", isSeam: true, declarations: ["@Instantiated let value: \(coreTypeName)"])], dependencies: ["Core"]),
			ModuleFixture(name: "Feed", packageName: "Base", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "FeedScreen", isSeam: true, declarations: ["@Instantiated let value: \(coreTypeName)"])], dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Bar\nimport Feed\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let barScreen: BarScreen", "@Instantiated let feedScreen: FeedScreen"])], dependencies: ["Bar", "Feed"]),
		]
	}

	/// `Session` declares the seam `Settings`; `Feed`'s seam `FeedScreen` builds it; `App` declares its own `Settings`
	/// and builds it beside a `FeedScreen`.
	private static let settingsCollisionModules = [
		ModuleFixture(name: "Session", packageName: "Base", swiftFileContent: [seamFixtureType(named: "Settings", isSeam: true, isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let theme: Theme?"]) + "\n\npublic struct Theme {\n    public init() {}\n}"]),
		ModuleFixture(name: "Feed", packageName: "Base", swiftFileContent: ["import Session\n\n" + seamFixtureType(named: "FeedScreen", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let settings: Settings"])], dependencies: ["Session"]),
		ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
			"import Feed\n\n" + seamFixtureType(named: "Settings", isFinalClass: true, declarations: []),
			"import Feed\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let feedScreen: FeedScreen", "@Instantiated let settings: Settings"]),
		], dependencies: ["Feed"]),
	]

	/// `App`'s generated file: `FeedScreen`'s generated initializer takes `token: Token?`, which `Session` receives only if
	/// available beneath it, and `App` passes `nil`; its file imports what the files of `Feed`, `Session` and `Core` do.
	/// `guardHash` is the guard of a `token` the initializer defers, as a pass-through; one `FeedScreen` receives itself
	/// is taken by value, and its guard hashes no deferral.
	private static func appCallingFeedScreen(guardHash: String = "F046DCFB1718557F", tokenLabel: String = "__safeDI_token") -> String {
		generatedFileHeader + importBlock("Core") + "\n" + importBlock("Feed") + "\n" + importBlock("Session") + "\n\n" + """
		extension Root {
		    public init() {
		        func __safeDI_feedScreen() -> FeedScreen {
		            _ = FeedScreen.__safeDI_FeedScreen_\(guardHash).self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "FeedScreen", declaringModule: "Feed"))
		            return FeedScreen(\(tokenLabel): nil)
		        }
		        let feedScreen: FeedScreen = __safeDI_feedScreen()
		        self.init(feedScreen: feedScreen)
		    }
		}
		"""
	}

	/// `appCallingFeedScreen` as the SwiftPM plugin generates it, whose call carries the plugin comment.
	private static let appCallingFeedScreenFromPlugin = generatedFileHeader + importBlock("Core") + "\n" + importBlock("Feed") + "\n" + importBlock("Session") + "\n\n" + """
	extension Root {
	    public init() {
	        func __safeDI_feedScreen() -> FeedScreen {
	            _ = FeedScreen.__safeDI_FeedScreen_F046DCFB1718557F.self // If this line does not compile, add the SafeDI plugin to the target that declares FeedScreen.
	            return FeedScreen(__safeDI_token: nil)
	        }
	        let feedScreen: FeedScreen = __safeDI_feedScreen()
	        self.init(feedScreen: feedScreen)
	    }
	}
	"""

	/// The lines a generated file repeats for a fixture's `import <moduleName>`.
	private static func importBlock(_ moduleName: String) -> String {
		"""
		#if canImport(\(moduleName))
		import \(moduleName)
		#endif
		"""
	}

	/// `bytes` with the test's fixture root removed from every path it holds, so two runs' files compare by what else they
	/// hold.
	private static func withoutFixtureRoot(_ bytes: [UInt8], _ output: MultiModuleTestOutput) -> [UInt8] {
		Array(String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: output.fixtureRoot.path, with: "").utf8)
	}

	/// Expects every module to have compiled, when compile verification runs.
	private func expectEveryModuleCompiled(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.moduleName) == output.moduleNames, sourceLocation: sourceLocation)
		#expect(compilation.failure == nil, sourceLocation: sourceLocation)
	}
}
