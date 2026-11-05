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
@testable import SafeDITool

/// What a module lists under a build system that runs `generate` once per module: the modules it imports, whose
/// `.safedi` files carry, in their views, what a seam or public mock of a module they depend on needs.
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
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.appCallingFeedScreen])
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
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.appCallingFeedScreen])
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
			\(fixtures["App"]!["Root.swift"]):12:5: error: No @Instantiable declaration of a module this module lists fulfills `Clock`, which @Instantiated property `clock: Clock` instantiates. `Clock` is declared in `Core`, which this module depends on through `Feed` but does not list; list `Core` where this module lists `Feed`: add its target to this target's `dependencies` in `Package.swift`, list its `<name>_safedi` target in this target's `safedi_deps` under Bazel, or list its module in the `dependencies:` of this target's `SafeDI.preCompileScript` under Tuist.
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
		#expect(appFiles == (integration == .moduleInfo ? ["App.swift": Self.appCallingFeedScreen] : ["Root+SafeDI.swift": Self.appCallingFeedScreenFromPlugin]))
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
		let call = spelling == "" ? "FeedScreen.__safeDI_FeedScreen_AB265D1ECB6CA342.self\n            return FeedScreen(token: nil)" : "FeedScreen.__safeDI_FeedScreen_CBF29CE484222325.self\n            return FeedScreen()"
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
		            _ = FeedScreen.__safeDI_FeedScreen_029593DA1BB2FBD5.self
		            return FeedScreen(token: nil)
		        }
		        let feedScreen: FeedScreen = __safeDI_feedScreen()
		        func __safeDI_session() -> Session {
		            _ = Session.__safeDI_Session_029593DA1BB2FBD5.self
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
		let pluginComment = integration == .moduleInfo ? "" : " // If this line does not compile, add the SafeDI plugin to the target that declares FeedScreen."
		#expect(output.modules["App"]?.generatedFiles == [fileName: generatedFileHeader + Self.importBlock("Core") + "\n" + Self.importBlock("Feed") + "\n\n" + """
		extension Root {
		    public init() {
		        func __safeDI_feedScreen() -> FeedScreen {
		            _ = FeedScreen.__safeDI_FeedScreen_717280493A095F31.self\(pluginComment)
		            return FeedScreen(theme: nil)
		        }
		        let feedScreen: FeedScreen = __safeDI_feedScreen()
		        let settings = Settings()
		        self.init(feedScreen: feedScreen, settings: settings)
		    }
		}
		"""])
		try expectEveryModuleCompiled(output)
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingBothNames_whenListedModuleInfoRecordsAnotherModule() async throws {
		// Cell 29: a renamed module's stale `.safedi` under the old name.
		let renamed = try await executeSafeDIToolTest(
			swiftFileContent: [Self.clock],
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "Renamed"],
		)
		let renamedPath = try renamed.writtenModuleInfoOutputPath
		await assertThrowsError("`\(URL(fileURLWithPath: renamedPath).path)` records module `Renamed`, which is not among the modules listed with `--dependent-module-name` (`Old`). Clean the build folder, or list `Renamed`.") {
			try await executeSafeDIToolTest(
				swiftFileContent: [seamFixtureType(named: "Root", isRoot: true, declarations: [])],
				dependentModuleInfoPaths: [renamedPath],
				buildCombinedOutput: true,
				filesToDelete: &filesToDelete,
				skipCompileVerification: true,
				moduleMembershipArguments: ["--dependent-module-name", "Old"],
			)
		}
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [seamFixtureType(named: "Root", isRoot: true, declarations: [])],
			dependentModuleInfoPaths: [renamedPath],
			buildCombinedOutput: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			moduleMembershipArguments: ["--dependent-module-name", "Renamed"],
		)
		#expect(output.combinedOutput != nil)
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
			            _ = FeedScreen.__safeDI_FeedScreen_717280493A095F31.self
			            return FeedScreen(theme: nil)
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
				\(appSettingsPath):3:1: error: Found multiple @Instantiable types or extensions that fulfill `Settings`. Each type can be fulfilled by only one @Instantiable declaration, across all modules. Keep one, and remove `Settings` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable.
				\(sessionSettingsPath):1:1: error: Found multiple @Instantiable types or extensions that fulfill `Settings`. Each type can be fulfilled by only one @Instantiable declaration, across all modules. Keep one, and remove `Settings` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable.
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
	private static let appCallingFeedScreen = generatedFileHeader + importBlock("Core") + "\n" + importBlock("Feed") + "\n" + importBlock("Session") + "\n\n" + """
	extension Root {
	    public init() {
	        func __safeDI_feedScreen() -> FeedScreen {
	            _ = FeedScreen.__safeDI_FeedScreen_029593DA1BB2FBD5.self
	            return FeedScreen(token: nil)
	        }
	        let feedScreen: FeedScreen = __safeDI_feedScreen()
	        self.init(feedScreen: feedScreen)
	    }
	}
	"""

	/// `appCallingFeedScreen` as the SwiftPM plugin generates it, whose call carries the plugin comment.
	private static let appCallingFeedScreenFromPlugin = generatedFileHeader + importBlock("Core") + "\n" + importBlock("Feed") + "\n" + importBlock("Session") + "\n\n" + """
	extension Root {
	    public init() {
	        func __safeDI_feedScreen() -> FeedScreen {
	            _ = FeedScreen.__safeDI_FeedScreen_029593DA1BB2FBD5.self // If this line does not compile, add the SafeDI plugin to the target that declares FeedScreen.
	            return FeedScreen(token: nil)
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
