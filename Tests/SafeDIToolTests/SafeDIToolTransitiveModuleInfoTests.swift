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

/// The modules beneath a module, which the Bazel rule hands every run of `generate` with
/// `--transitive-module-info-file-path` and which only a module that generates a dependency tree reads.
struct SafeDIToolTransitiveModuleInfoTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – A root that lists only its direct dependencies

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTypeOfModuleTwoLevelsDown_whenRootListsOnlyTheModuleItImports() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.rootOverMiddleOverDeep(appDependencies: ["Middle"]),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.appBuildingFeedScreen])
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Deep", "Middle"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsEveryLevel_whenRootSitsAboveAChainFourModulesDeep() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "LevelFour", packageName: "Base", swiftFileContent: [seamFixtureType(named: "Four", declarations: [])]),
				ModuleFixture(name: "LevelThree", packageName: "Base", swiftFileContent: ["import LevelFour\n\n" + seamFixtureType(named: "Three", declarations: ["@Instantiated let four: Four"])], dependencies: ["LevelFour"]),
				ModuleFixture(name: "LevelTwo", packageName: "Base", swiftFileContent: ["import LevelThree\n\n" + seamFixtureType(named: "Two", declarations: ["@Instantiated let three: Three"])], dependencies: ["LevelThree"]),
				ModuleFixture(name: "LevelOne", packageName: "Base", swiftFileContent: ["import LevelTwo\n\n" + seamFixtureType(named: "One", declarations: ["@Instantiated let two: Two"])], dependencies: ["LevelTwo"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import LevelOne\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let one: One"])], dependencies: ["LevelOne"]),
			],
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.generatedFile(importing: ["LevelFour", "LevelOne", "LevelThree", "LevelTwo"], """
		extension Root {
		    public init() {
		        func __safeDI_one() -> One {
		            func __safeDI_two() -> Two {
		                func __safeDI_three() -> Three {
		                    let four = Four()
		                    return Three(four: four)
		                }
		                let three: Three = __safeDI_three()
		                return Two(three: three)
		            }
		            let two: Two = __safeDI_two()
		            return One(two: two)
		        }
		        let one: One = __safeDI_one()
		        self.init(one: one)
		    }
		}
		""")])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: [
		ListingOrder.dependencyOrder,
		.reverseDependencyOrder,
		.everyModuleTwice,
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsEachModuleOnce_whenADiamondReachesOneModuleThroughTwoListedModules(order: ListingOrder) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Base", packageName: "Base", swiftFileContent: [Self.clock]),
				ModuleFixture(name: "Left", packageName: "Base", swiftFileContent: ["import Base\n\n" + seamFixtureType(named: "LeftScreen", declarations: ["@Instantiated let clock: Clock"])], dependencies: ["Base"]),
				ModuleFixture(name: "Right", packageName: "Base", swiftFileContent: ["import Base\n\n" + seamFixtureType(named: "RightScreen", declarations: ["@Instantiated let clock: Clock"])], dependencies: ["Base"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Left\nimport Right\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let leftScreen: LeftScreen", "@Instantiated let rightScreen: RightScreen"])], dependencies: ["Left", "Right"]),
			],
			integration: .moduleInfo,
			modulesBeneath: order.arranged,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.generatedFile(importing: ["Base", "Left", "Right"], """
		extension Root {
		    public init() {
		        func __safeDI_leftScreen() -> LeftScreen {
		            let clock = Clock()
		            return LeftScreen(clock: clock)
		        }
		        let leftScreen: LeftScreen = __safeDI_leftScreen()
		        func __safeDI_rightScreen() -> RightScreen {
		            let clock = Clock()
		            return RightScreen(clock: clock)
		        }
		        let rightScreen: RightScreen = __safeDI_rightScreen()
		        self.init(leftScreen: leftScreen, rightScreen: rightScreen)
		    }
		}
		""")])
		#expect(output.modules["App"]?.generateOutput?.dependentModules.map(\.moduleName) == ["Base", "Left", "Right"])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: [
		[0, 1, 2, 3, 4, 5],
		[5, 4, 3, 2, 1, 0],
		[2, 5, 0, 3, 1, 4],
		[3, 0, 4, 1, 5, 2],
		[1, 3, 5, 0, 2, 4],
		[4, 2, 0, 5, 3, 1],
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_combinesEveryModuleInPathOrder_whateverOrderTheModulesBeneathArriveIn(permutation: [Int]) async throws {
		// `Middle`, the module listed, sorts between the modules only the set names, so that appending the set after the
		// list would read them in another order than a complete list.
		let leafNames = ["Alpha", "Bravo", "Charlie", "Xray", "Yankee", "Zulu"]
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: leafNames.map { ModuleFixture(name: $0, packageName: "Base", swiftFileContent: [seamFixtureType(named: "\($0)Type", declarations: [])]) } + [
				ModuleFixture(name: "Middle", packageName: "Base", swiftFileContent: [
					leafNames.map { "import \($0)" }.joined(separator: "\n") + "\n\n" + seamFixtureType(named: "Hub", declarations: leafNames.map { "@Instantiated let \($0.lowercased()): \($0)Type" }),
				], dependencies: leafNames),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Middle\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let hub: Hub"])], dependencies: ["Middle"]),
			],
			integration: .moduleInfo,
			modulesBeneath: { moduleNames in
				let leaves = permutation.map { leafNames[$0] }
				return leaves + moduleNames.filter { !leaves.contains($0) }
			},
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generateOutput?.dependentModules.map(\.moduleName) == ["Alpha", "Bravo", "Charlie", "Middle", "Xray", "Yankee", "Zulu"])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.generatedFile(importing: ["Alpha", "Bravo", "Charlie", "Middle", "Xray", "Yankee", "Zulu"], """
		extension Root {
		    public init() {
		        func __safeDI_hub() -> Hub {
		            let alpha = AlphaType()
		            let bravo = BravoType()
		            let charlie = CharlieType()
		            let xray = XrayType()
		            let yankee = YankeeType()
		            let zulu = ZuluType()
		            return Hub(alpha: alpha, bravo: bravo, charlie: charlie, xray: xray, yankee: yankee, zulu: zulu)
		        }
		        let hub: Hub = __safeDI_hub()
		        self.init(hub: hub)
		    }
		}
		""")])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fulfillsExistentialAndInstantiatorFromModuleBeneath_whenRootListsOnlyTheModuleItImports() async throws {
		// The set widens which files are read and nothing else, so one spelling beyond a plain type stands for the rest.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [
					"public protocol Sink {}\n\n" + seamFixtureType(named: "ConsoleSink", declarations: [], conformances: ", Sink").replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Sink.self])\n"),
					Self.clock,
				]),
				ModuleFixture(name: "Middle", packageName: "Base", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "FeedScreen", declarations: ["@Instantiated let sink: any Sink", "@Instantiated let clockBuilder: Instantiator<Clock>"])], dependencies: ["Deep"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Middle\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let feedScreen: FeedScreen"])], dependencies: ["Middle"]),
			],
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.generatedFile(importing: ["Deep", "Middle"], """
		extension Root {
		    public init() {
		        func __safeDI_feedScreen() -> FeedScreen {
		            let sink: any Sink = ConsoleSink()
		            func __safeDI_clockBuilder() -> Clock {
		                Clock()
		            }
		            let clockBuilder = Instantiator<Clock>(__safeDI_clockBuilder)
		            return FeedScreen(sink: sink, clockBuilder: clockBuilder)
		        }
		        let feedScreen: FeedScreen = __safeDI_feedScreen()
		        self.init(feedScreen: feedScreen)
		    }
		}
		""")])
		try expectEveryModuleCompiled(output)
	}

	// MARK: Tests – A complete hand-written list

	@Test(arguments: [
		(list: HandWrittenList.direct, passesSet: true),
		(list: .complete, passesSet: false),
		(list: .complete, passesSet: true),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesTheSameCodeAndModuleInfo_whateverTheRootsListHolds(list: HandWrittenList, passesSet: Bool) async throws {
		// A complete list is what the manual asked of a root before the rule collected the set. The list, the set, or both
		// give the run the same files, so the same code and the same `.safedi`.
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: Self.rootOverMiddleOverDeep(appDependencies: ["Deep", "Middle"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.rootOverMiddleOverDeep(appDependencies: list == .direct ? ["Middle"] : ["Deep", "Middle"]),
			integration: .moduleInfo,
			modulesBeneath: passesSet ? { $0 } : nil,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.appBuildingFeedScreen])
		#expect(Self.withoutFixtureRoot(output, module: "App") == Self.withoutFixtureRoot(reference, module: "App"))
		try expectEveryModuleCompiled(output)
	}

	// MARK: Tests – A module with no tree

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesTheSameMock_whenModuleDeclaresNoTree(passesSet: Bool) async throws {
		// `mock()` keeps its parameter: a module with no tree generates what the modules it lists give it, whatever else
		// its build knows.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.deepAndMiddle + [Self.appWithMock(root: .none)],
			integration: .moduleInfo,
			modulesBeneath: passesSet ? { $0 } : nil,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.generatedFile(importing: ["Deep", "Middle"], """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            feedScreen: ((Clock) -> FeedScreen)? = nil
		        ) {
		            self.feedScreen = feedScreen
		        }

		        let feedScreen: ((Clock) -> FeedScreen)?
		    }

		    static func mock(
		        clock: Clock,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let feedScreen = if let safeDIBuilder = safeDIOverrides.feedScreen { safeDIBuilder(clock) } else { FeedScreen(clock: clock) }
		        return Screen(feedScreen: feedScreen)
		    }
		}
		#endif
		""")])
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Middle"])
		#expect(output.modules["App"]?.generateOutput?.dependentModules.map(\.moduleName) == ["Middle"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsNothingOfTheSet_whenModuleDeclaresNoTree() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [seamFixtureType(named: "Screen", declarations: [])],
			buildCombinedOutput: true,
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "App", "--transitive-module-info-file-path", "/nonexistent/modules-beneath.csv"],
		)
		#expect(output.combinedOutput == generatedFileHeader)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingTheFile_whenModuleDeclaresRootAndAModuleBeneathCannotBeRead() async throws {
		let unreadableModuleInfo = URL.temporaryFile.appendingPathExtension("safedi")
		try Data("not a module info file".utf8).write(to: unreadableModuleInfo)
		filesToDelete.append(unreadableModuleInfo)
		let modulesBeneathCSV = URL.temporaryFile
		try unreadableModuleInfo.path.write(to: modulesBeneathCSV, atomically: true, encoding: .utf8)
		filesToDelete.append(modulesBeneathCSV)
		await assertThrowsError(containing: "Could not read the SafeDI module info file at \(unreadableModuleInfo.path)") {
			try await executeSafeDIToolTest(
				swiftFileContent: [seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let clock: Clock"])],
				buildCombinedOutput: true,
				filesToDelete: &filesToDelete,
				skipCompileVerification: true,
				moduleMembershipArguments: ["--transitive-module-info-file-path", modulesBeneathCSV.path],
			)
		}
	}

	// MARK: Tests – Mocks

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTypeOfModuleBeneathInMock_whenModuleDeclaresRoot() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.deepAndMiddle + [Self.appWithMock(root: .buildingScreen)],
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.generatedFile(importing: ["Deep", "Middle"], """
		extension Root {
		    public init() {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_feedScreen() -> FeedScreen {
		                let clock = Clock()
		                return FeedScreen(clock: clock)
		            }
		            let feedScreen: FeedScreen = __safeDI_feedScreen()
		            return Screen(feedScreen: feedScreen)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(screen: screen)
		    }
		}

		\(Self.screenMockBuildingClock)
		""") + "\n"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesAdditionalMock_whenEntryNamesTypeOfModuleBeneath() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.deepAndMiddle + [
				ModuleFixture(
					name: "App",
					packageName: "App",
					swiftFileContent: ["import Middle\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let feedScreen: FeedScreen"])],
					swiftFileContentByFilePath: ["SafeDIConfiguration.swift": "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Clock\"])\n"],
					dependencies: ["Middle"],
				),
			],
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.generatedFile(importing: ["Deep", "Middle", "SafeDI"], """
		extension Root {
		    public init() {
		        func __safeDI_feedScreen() -> FeedScreen {
		            let clock = Clock()
		            return FeedScreen(clock: clock)
		        }
		        let feedScreen: FeedScreen = __safeDI_feedScreen()
		        self.init(feedScreen: feedScreen)
		    }
		}

		#if DEBUG
		extension Clock {
		    static func mock() -> Clock {
		        Clock()
		    }
		}
		#endif
		""")])
		try expectEveryModuleCompiled(output)
	}

	// MARK: Tests – Seams and public mocks of a middle module

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamOfMiddleModule_whenEveryModuleListsOnlyWhatItImports(listsComplete: Bool) async throws {
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: Self.seamOverInnerOverDeep(middleDependencies: ["Deep", "Inner"], appDependencies: ["Deep", "Inner", "Middle"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: listsComplete
				? Self.seamOverInnerOverDeep(middleDependencies: ["Deep", "Inner"], appDependencies: ["Deep", "Inner", "Middle"])
				: Self.seamOverInnerOverDeep(middleDependencies: ["Inner"], appDependencies: ["Middle"]),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Middle"]?.moduleInfoFile?.dependencyModuleNames == ["Deep", "Inner"])
		#expect(output.modules["Middle"]?.moduleInfoFile?.view.declarations.map(\.moduleName) == ["Deep", "Inner"])
		#expect(output.modules["Middle"]?.generatedFiles == reference.modules["Middle"]?.generatedFiles)
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		#expect(Self.withoutFixtureRoot(output, module: "Middle") == Self.withoutFixtureRoot(reference, module: "Middle"))
		// `App`'s tree stops at the seam, so a short list leaves nothing open, and its run reads `Middle` alone.
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == (listsComplete ? ["Deep", "Inner", "Middle"] : ["Middle"]))
		#expect(output.modules["Middle"]?.generatedFiles == ["Middle.swift": Self.generatedFile(importing: ["Deep", "Inner"], """
		extension FeedScreen {
		    public init() {
		        func __safeDI_innerScreen() -> InnerScreen {
		            let clock = Clock()
		            return InnerScreen(clock: clock)
		        }
		        let innerScreen: InnerScreen = __safeDI_innerScreen()
		        self.init(innerScreen: innerScreen)
		    }
		}

		extension FeedScreen {
		    public enum __safeDI_FeedScreen_CBF29CE484222325 {}
		}
		""")])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.generatedFile(importing: ["Deep", "Inner", "Middle"], """
		extension Root {
		    public init() {
		        func __safeDI_feedScreen() -> FeedScreen {
		            _ = FeedScreen.__safeDI_FeedScreen_CBF29CE484222325.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "FeedScreen", declaringModule: "Middle"))
		            return FeedScreen()
		        }
		        let feedScreen: FeedScreen = __safeDI_feedScreen()
		        self.init(feedScreen: feedScreen)
		    }
		}
		""")])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheModuleReadsOfAPublicMockModule_whenItDeclaresNoTree(listsComplete: Bool) async throws {
		// `Middle` declares a public mock and no tree, so its run reads only `Inner`, and its mock takes a builder of `Clock`,
		// which `Inner`'s `.safedi` does not declare. `App` declares a root, so it reads `Deep` too, which a complete list of
		// `App`'s would give it, and builds `FeedScreen` inline in its mocks, since it can construct every type of its tree.
		func modules(appDependencies: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [Self.clock]),
				ModuleFixture(name: "Inner", packageName: "Base", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "InnerScreen", declarations: ["@Instantiated let clock: Clock"])], dependencies: ["Deep"]),
				ModuleFixture(name: "Middle", packageName: "Base", swiftFileContent: [
					"import Inner\n\n" + seamFixtureType(named: "FeedScreen", declarations: ["@Instantiated let innerScreen: InnerScreen"]).replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: .public)\n"),
				], dependencies: ["Inner"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
					"import Middle\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let screen: Screen"]),
					"import Middle\n\n" + seamFixtureType(named: "Screen", declarations: ["@Instantiated let feedScreen: FeedScreen"]).replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n"),
				], dependencies: appDependencies),
			]
		}
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Deep", "Inner", "Middle"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: listsComplete ? ["Deep", "Inner", "Middle"] : ["Middle"]),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Middle"]?.moduleInfoFile?.dependencyModuleNames == ["Inner"])
		#expect(output.modules["Middle"]?.generatedFiles == ["Middle.swift": Self.generatedFile(importing: ["Deep", "Inner"], """
		#if DEBUG
		extension FeedScreen {
		    @frozen public enum SafeDIMockScope_Clock {
		        case innerScreen_clock(innerScreen_clock_Values)

		        public struct innerScreen_clock_Values {}
		    }

		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            innerScreen: ((Clock) -> InnerScreen)? = nil
		        ) {
		            self.innerScreen = innerScreen
		        }

		        public let innerScreen: ((Clock) -> InnerScreen)?
		    }

		    public static func mock(
		        clockBuilder: @escaping (FeedScreen.SafeDIMockScope_Clock) -> Clock,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> FeedScreen {
		        let __safeDI_clockBuilder = clockBuilder
		        func __safeDI_innerScreen() -> InnerScreen {
		            let clock: Clock = __safeDI_clockBuilder(.innerScreen_clock(SafeDIMockScope_Clock.innerScreen_clock_Values()))
		            return if let safeDIBuilder = safeDIOverrides.innerScreen { safeDIBuilder(clock) } else { InnerScreen(clock: clock) }
		        }
		        let innerScreen: InnerScreen = __safeDI_innerScreen()
		        return FeedScreen(innerScreen: innerScreen)
		    }
		}

		extension FeedScreen {
		    public enum __safeDI_FeedScreen_mock_6426765AFC8C4713 {}
		}
		#endif
		""")])
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		#expect(Self.withoutFixtureRoot(output, module: "App") == Self.withoutFixtureRoot(reference, module: "App"))
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.generatedFile(importing: ["Deep", "Inner", "Middle"], """
		extension Root {
		    public init() {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_feedScreen() -> FeedScreen {
		                func __safeDI_innerScreen() -> InnerScreen {
		                    let clock = Clock()
		                    return InnerScreen(clock: clock)
		                }
		                let innerScreen: InnerScreen = __safeDI_innerScreen()
		                return FeedScreen(innerScreen: innerScreen)
		            }
		            let feedScreen: FeedScreen = __safeDI_feedScreen()
		            return Screen(feedScreen: feedScreen)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(screen: screen)
		    }
		}

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            feedScreen: FeedScreen.SafeDIMockConfiguration = .init()
		        ) {
		            self.feedScreen = feedScreen
		        }

		        let feedScreen: FeedScreen.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_feedScreen() -> FeedScreen {
		            func __safeDI_innerScreen() -> InnerScreen {
		                let clock = if let safeDIBuilder = safeDIOverrides.feedScreen.innerScreen.clock { safeDIBuilder() } else { Clock() }
		                return if let safeDIBuilder = safeDIOverrides.feedScreen.innerScreen.safeDIBuilder { safeDIBuilder(clock) } else { InnerScreen(clock: clock) }
		            }
		            let innerScreen: InnerScreen = __safeDI_innerScreen()
		            return if let safeDIBuilder = safeDIOverrides.feedScreen.safeDIBuilder { safeDIBuilder(innerScreen) } else { FeedScreen(innerScreen: innerScreen) }
		        }
		        let feedScreen: FeedScreen = __safeDI_feedScreen()
		        return Screen(feedScreen: feedScreen)
		    }
		}
		#endif

		#if DEBUG
		extension InnerScreen {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            clock: (() -> Clock)? = nil,
		            _ safeDIBuilder: ((Clock) -> InnerScreen)? = nil
		        ) {
		            self.clock = clock
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let clock: (() -> Clock)?
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        let safeDIBuilder: ((Clock) -> InnerScreen)?
		    }
		}

		extension FeedScreen {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            innerScreen: InnerScreen.SafeDIMockConfiguration = .init(),
		            _ safeDIBuilder: ((InnerScreen) -> FeedScreen)? = nil
		        ) {
		            self.innerScreen = innerScreen
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let innerScreen: InnerScreen.SafeDIMockConfiguration
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        let safeDIBuilder: ((InnerScreen) -> FeedScreen)?
		    }
		}
		#endif
		""") + "\n"])
		try expectEveryModuleCompiled(output)
	}

	// MARK: Tests – One name through both sets

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateDeclaration_whenListingEveryModuleThatDeclaresOneType() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = Self.duplicateDeclarationMessage(of: "Clock", inModules: "`Deep` and `Left`")
			return "\(fixtures["Deep"]!["Clock.swift"]):1:1: \(message)\n\(fixtures["Left"]!["Clock.swift"]):1:1: \(message)"
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.twoModulesDeclaringClock(appDependencies: ["Deep", "Left", "Right"]),
				integration: .moduleInfo,
				modulesBeneath: { $0 },
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsListedModulesType_whenModuleBeneathDeclaresTheSameType() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.twoModulesDeclaringClock(appDependencies: ["Left", "Right"]),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.generatedFile(importing: ["Left"], """
		extension Root {
		    public init() {
		        let clock = Clock()
		        self.init(clock: clock)
		    }
		}
		""")])
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Left", "Right"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsOwnType_whenSeamModuleListsOnlyWhatItsTreeReachesAndModuleBeneathDeclaresTheSameInternalType() async throws {
		func modules() -> [ModuleFixture] {
			[
				ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [Self.internalHelper, seamFixtureType(named: "DeepScreen", isSeam: true, declarations: ["@Instantiated let helper: Helper"])]),
				ModuleFixture(name: "Mid", packageName: "Base", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "MidScreen", isSeam: true, declarations: ["@Instantiated let deepScreen: DeepScreen"])], dependencies: ["Deep"]),
				ModuleFixture(name: "Top", packageName: "App", swiftFileContent: [Self.internalHelper, "import Mid\n\n" + seamFixtureType(named: "TopScreen", isSeam: true, declarations: ["@Instantiated let helper: Helper", "@Instantiated let midScreen: MidScreen"])], dependencies: ["Mid"]),
			]
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(),
			integration: .moduleInfo,
			compileVerification: .skipped,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules(),
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Top"]?.generatedFiles == reference.modules["Top"]?.generatedFiles)
		#expect(output.modules["Top"]?.moduleInfoFile?.dependencyModuleNames == ["Mid"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsOwnType_whenRootBuildsItAndModuleBeneathDeclaresTheSameType() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [seamFixtureType(named: "Logger", declarations: [])]),
				ModuleFixture(name: "Mid", packageName: "Base", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "MidThing", declarations: [])], dependencies: ["Deep"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [seamFixtureType(named: "Logger", declarations: []), seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let logger: Logger"])], dependencies: ["Mid"]),
			],
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.generatedFile(importing: ["Deep"], """
		extension Root {
		    public init() {
		        let logger = Logger()
		        self.init(logger: logger)
		    }
		}
		""")])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_succeeds_whenTwoModulesBeneathDeclareATypeNoTreeReaches() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "DeepLeft", packageName: "Base", swiftFileContent: [Self.clock]),
				ModuleFixture(name: "DeepRight", packageName: "Base", swiftFileContent: [Self.clock]),
				ModuleFixture(name: "MidLeft", packageName: "Base", swiftFileContent: [seamFixtureType(named: "MidLeftThing", declarations: [])], dependencies: ["DeepLeft"]),
				ModuleFixture(name: "MidRight", packageName: "Base", swiftFileContent: [seamFixtureType(named: "MidRightThing", declarations: [])], dependencies: ["DeepRight"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import MidLeft\nimport MidRight\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let midLeftThing: MidLeftThing", "@Instantiated let midRightThing: MidRightThing"])], dependencies: ["MidLeft", "MidRight"]),
			],
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["MidLeft", "MidRight"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTheTypeUnfulfilled_whenOnlyAMockOnlyDeclarationBeneathNamesTheTypeARootBuilds() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"\(fixtures["App"]!["Root.swift"]):10:5: error: No @Instantiable type or extension fulfills `Clock`, which @Instantiated property `clock: Clock` instantiates. This file imports `Deep`, whose SafeDI module info this run was not given. If `Deep` declares `Clock`, build it with SafeDI and give this run its module info: under Bazel, declare it with `safedi_swift_library` (or a `safedi_compile` rule) and list its `<name>_safedi` target in this target's `safedi_deps`; under Tuist, give its target `SafeDI.preCompileScript` and list it in the `dependencies:` of this target's `SafeDI.preCompileScript`; in a custom build, pass its `.safedi` file to `--dependent-module-info-file-path`. Otherwise, decorate `Clock`, or an extension of it, with @Instantiable, or list `Clock` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it."
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [Self.mockOnlyClock]),
					ModuleFixture(name: "Mid", packageName: "Base", swiftFileContent: [seamFixtureType(named: "MidThing", declarations: [])], dependencies: ["Deep"]),
					ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Deep\nimport Mid\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let clock: Clock"])], dependencies: ["Mid"]),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				modulesBeneath: { $0 },
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – What the modules beneath cost

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_opensNoModuleBeneath_whenTheModuleAndTheModulesItListsFulfillEveryTree() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.clock, seamFixtureType(named: "Seam", isSeam: true, declarations: ["@Instantiated let clock: Clock"])],
			buildCombinedOutput: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			moduleMembershipArguments: ["--module-name", "App", "--transitive-module-info-file-path", "/nonexistent/modules-beneath.csv"],
		)
		#expect(output.combinedOutput?.contains("extension Seam") == true)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsNoModuleBeneath_whenSeamsTreeStopsAtAnotherSeam() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [Self.clock]),
				ModuleFixture(name: "Mid", packageName: "Base", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "MidScreen", isSeam: true, declarations: ["@Instantiated let clock: Clock"])], dependencies: ["Deep"]),
				ModuleFixture(name: "Top", packageName: "App", swiftFileContent: ["import Mid\n\n" + seamFixtureType(named: "TopScreen", isSeam: true, declarations: ["@Instantiated let midScreen: MidScreen"])], dependencies: ["Mid"]),
			],
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Top"]?.moduleInfoFile?.dependencyModuleNames == ["Mid"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsNoModuleBeneath_whenOnlyAForwardedDependencyNamesItsType() async throws {
		// A forwarded value comes from whoever calls the `Instantiator`, from outside the tree, so no tree needs `Deep`'s
		// declaration of `Token`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [seamFixtureType(named: "Token", declarations: [])]),
				ModuleFixture(name: "Middle", packageName: "Base", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "Feature", declarations: ["@Forwarded let token: Token"])], dependencies: ["Deep"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Middle\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let featureBuilder: Instantiator<Feature>"])], dependencies: ["Middle"]),
			],
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.generatedFile(importing: ["Deep", "Middle"], """
		extension Root {
		    public init() {
		        func __safeDI_featureBuilder(token: Token) -> Feature {
		            Feature(token: token)
		        }
		        let featureBuilder = Instantiator<Feature> {
		            __safeDI_featureBuilder(token: $0)
		        }
		        self.init(featureBuilder: featureBuilder)
		    }
		}
		""")])
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Middle"])
		try expectEveryModuleCompiled(output)
	}

	// MARK: Tests – A seam's initializer

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsSeamsTypeInsteadOfTakingABuilder_whenAModuleBeneathDeclaresIt(passesSet: Bool) async throws {
		// Without the set, `Clock` is a hole in the seam's tree, which the initializer takes as a builder. The set fills it,
		// as listing `Deep` does.
		func modules(seamModuleDependencies: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [Self.clock]),
				ModuleFixture(name: "Mid", packageName: "Base", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "MidThing", declarations: ["@Instantiated let clock: Clock"])], dependencies: ["Deep"]),
				ModuleFixture(name: "SeamModule", packageName: "App", swiftFileContent: ["import Mid\n\n" + seamFixtureType(named: "Seam", isSeam: true, declarations: ["@Instantiated let midThing: MidThing"])], dependencies: seamModuleDependencies),
			]
		}
		let listingEveryModule = try await executeSafeDIToolMultiModuleTest(
			modules: modules(seamModuleDependencies: ["Deep", "Mid"]),
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(seamModuleDependencies: ["Mid"]),
			integration: .moduleInfo,
			compileVerification: .skipped,
			modulesBeneath: passesSet ? { $0 } : nil,
			filesToDelete: &filesToDelete,
		)
		#expect((output.modules["SeamModule"]?.generatedFiles == listingEveryModule.modules["SeamModule"]?.generatedFiles) == passesSet)
		let generated = try #require(output.modules["SeamModule"]?.generatedFiles["SeamModule.swift"])
		#expect(generated.contains("clockBuilder") == !passesSet)
	}

	// MARK: Tests – A module with no tree above a module with one

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_leavesModuleWithNoTreeUnchanged_whenASeamModuleItListsNeedsNothingBeneath() async throws {
		func run(modulesBeneath: ((_ moduleNames: [String]) -> [String])?) async throws -> MultiModuleTestOutput {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Unrelated", packageName: "Base", swiftFileContent: ["public struct Unrelated {\n    public init() {}\n}\n"]),
					ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: ["import Unrelated\n\n" + Self.clock], dependencies: ["Unrelated"]),
					ModuleFixture(name: "Mid", packageName: "Base", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "MidThing", declarations: [])], dependencies: ["Deep"]),
					ModuleFixture(name: "SeamModule", packageName: "Base", swiftFileContent: ["import Mid\n\n" + seamFixtureType(named: "Seam", isSeam: true, declarations: ["@Instantiated let midThing: MidThing"])], dependencies: ["Mid"]),
					ModuleFixture(name: "Consumer", packageName: "App", swiftFileContent: ["import Mid\nimport SeamModule\n\n" + seamFixtureType(named: "Screen", declarations: ["@Instantiated let seam: Seam", "@Instantiated let midThing: MidThing"]).replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n")], dependencies: ["Mid", "SeamModule"]),
				],
				integration: .moduleInfo,
				modulesBeneath: modulesBeneath,
				filesToDelete: &filesToDelete,
			)
		}
		let reference = try await run(modulesBeneath: nil)
		let output = try await run(modulesBeneath: { $0 })
		#expect(output.modules["Consumer"]?.generatedFiles == reference.modules["Consumer"]?.generatedFiles)
		#expect(Self.withoutFixtureRoot(output, module: "Consumer") == Self.withoutFixtureRoot(reference, module: "Consumer"))
		try expectEveryModuleCompiled(output)
	}

	// MARK: Tests – A module beneath that declares a root

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsWhatARootOfAModuleBeneathReaches_whenTheModuleIsReadForAnotherType(moduleDeclaresSeam: Bool) async throws {
		func modules(appDependencies: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Deeper", packageName: "Base", swiftFileContent: [seamFixtureType(named: "Other", declarations: [])]),
				ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: ["import Deeper\n\n" + seamFixtureType(named: "DeepRoot", isRoot: true, declarations: ["@Instantiated let other: Other"]), Self.clock], dependencies: ["Deeper"]),
				ModuleFixture(name: "Middle", packageName: "Base", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "FeedScreen", declarations: ["@Instantiated let clock: Clock"])], dependencies: ["Deep", "Deeper"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Middle\n\n" + seamFixtureType(named: "Top", isSeam: moduleDeclaresSeam, isRoot: !moduleDeclaresSeam, declarations: ["@Instantiated let feedScreen: FeedScreen"])], dependencies: appDependencies),
			]
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Middle"]),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Deep", "Deeper", "Middle"]),
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Deep", "Deeper", "Middle"])
		try expectEveryModuleCompiled(output)
	}

	// MARK: Tests – A seam another module generates

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsTheModuleBeneathAFill_whenTheFillOfAnotherModulesSeamReachesIt() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.seamFilledOverDeep(appDependencies: ["Core", "Impl", "SeamModule"]),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: Self.seamFilledOverDeep(appDependencies: ["Core", "Deep", "Impl", "SeamModule"]),
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Core", "Deep", "Impl", "SeamModule"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsTheModuleBeneathAFill_whenTheHoleIsPassedUpThroughAnotherModulesSeam() async throws {
		func modules(appDependencies: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: ["public protocol Tracker {}\n"]),
				ModuleFixture(name: "InnerSeamModule", packageName: "Base", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "InnerSeam", isSeam: true, declarations: ["@Instantiated let tracker: any Tracker"])], dependencies: ["Core"]),
				ModuleFixture(name: "PlainModule", packageName: "Base", swiftFileContent: ["import InnerSeamModule\n\n" + seamFixtureType(named: "Plain", declarations: ["@Instantiated let innerSeam: InnerSeam"])], dependencies: ["InnerSeamModule"]),
				ModuleFixture(name: "OuterSeamModule", packageName: "Base", swiftFileContent: ["import PlainModule\n\n" + seamFixtureType(named: "OuterSeam", isSeam: true, declarations: ["@Instantiated let plain: Plain"])], dependencies: ["PlainModule"]),
				ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [Self.clock]),
				ModuleFixture(name: "Impl", packageName: "Base", swiftFileContent: ["import Core\nimport Deep\n\n" + Self.trackerImplementation], dependencies: ["Core", "Deep"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Core\nimport Impl\nimport OuterSeamModule\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let outerSeam: OuterSeam"])], dependencies: appDependencies),
			]
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Core", "Impl", "InnerSeamModule", "OuterSeamModule", "PlainModule"]),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Core", "Deep", "Impl", "InnerSeamModule", "OuterSeamModule", "PlainModule"]),
			integration: .moduleInfo,
			compileVerification: .skipped,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Core", "Deep", "Impl", "InnerSeamModule", "OuterSeamModule", "PlainModule"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesTheHoleUp_whenNothingReadFillsAHoleOfAnotherModulesSeam() async throws {
		func modules() -> [ModuleFixture] {
			[
				ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: ["public protocol Tracker {}\n"]),
				ModuleFixture(name: "SeamModule", packageName: "Base", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "Feature", isSeam: true, declarations: ["@Instantiated let tracker: any Tracker"])], dependencies: ["Core"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import SeamModule\n\n" + seamFixtureType(named: "TopSeam", isSeam: true, declarations: ["@Instantiated let feature: Feature"])], dependencies: ["SeamModule"]),
			]
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules(),
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["SeamModule"])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: [["Core", "Impl", "OuterSeamModule"], ["Core", "Impl", "InnerSeamModule", "OuterSeamModule"], ["Core", "Impl", "OuterSeamModule", "PlainModule"]])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsTheHole_whenAModuleOnThePathBetweenTwoSeamsIsNotListed(appDependencies: [String]) async throws {
		func modules(appDependencies: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: ["public protocol Tracker {}\n"]),
				ModuleFixture(name: "InnerSeamModule", packageName: "Base", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "InnerSeam", isSeam: true, declarations: ["@Instantiated let tracker: any Tracker"])], dependencies: ["Core"]),
				ModuleFixture(name: "PlainModule", packageName: "Base", swiftFileContent: ["import InnerSeamModule\n\n" + seamFixtureType(named: "Plain", declarations: ["@Instantiated let innerSeam: InnerSeam"])], dependencies: ["InnerSeamModule"]),
				ModuleFixture(name: "OuterSeamModule", packageName: "Base", swiftFileContent: ["import PlainModule\n\n" + seamFixtureType(named: "OuterSeam", isSeam: true, declarations: ["@Instantiated let plain: Plain"])], dependencies: ["PlainModule"]),
				ModuleFixture(name: "Impl", packageName: "Base", swiftFileContent: ["import Core\n\n" + Self.leafTrackerImplementation], dependencies: ["Core"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Core\nimport Impl\nimport OuterSeamModule\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let outerSeam: OuterSeam"])], dependencies: appDependencies),
			]
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: appDependencies),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Core", "Impl", "InnerSeamModule", "OuterSeamModule", "PlainModule"]),
			integration: .moduleInfo,
			compileVerification: .skipped,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Core", "Impl", "InnerSeamModule", "OuterSeamModule", "PlainModule"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsTheModuleBeneathThatFillsTheHole_whenARootCallsAnotherModulesSeam() async throws {
		func modules(appDependencies: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: ["public protocol Tracker {}\n"]),
				ModuleFixture(name: "SeamModule", packageName: "Base", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "Feature", isSeam: true, declarations: ["@Instantiated let tracker: any Tracker"])], dependencies: ["Core"]),
				ModuleFixture(name: "Impl", packageName: "Base", swiftFileContent: ["import Core\n\n" + Self.leafTrackerImplementation], dependencies: ["Core"]),
				ModuleFixture(name: "Sub", packageName: "Base", swiftFileContent: ["import Impl\n\n" + seamFixtureType(named: "SubThing", declarations: [])], dependencies: ["Impl"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Core\nimport SeamModule\nimport Sub\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let feature: Feature"])], dependencies: appDependencies),
			]
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Core", "SeamModule", "Sub"]),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Core", "Impl", "SeamModule", "Sub"]),
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Core", "Impl", "SeamModule", "Sub"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsTheHoleInsteadOfTakingABuilder_whenASeamCallsAnotherModulesSeamAndAModuleBeneathDeclaresTheFill() async throws {
		func modules(appDependencies: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: ["public protocol Tracker {}\n"]),
				ModuleFixture(name: "SeamModule", packageName: "Base", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "Feature", isSeam: true, declarations: ["@Instantiated let tracker: any Tracker"])], dependencies: ["Core"]),
				ModuleFixture(name: "Impl", packageName: "Base", swiftFileContent: ["import Core\n\n" + Self.leafTrackerImplementation], dependencies: ["Core"]),
				ModuleFixture(name: "Sub", packageName: "Base", swiftFileContent: ["import Impl\n\n" + seamFixtureType(named: "SubThing", declarations: [])], dependencies: ["Impl"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Core\nimport SeamModule\nimport Sub\n\n" + seamFixtureType(named: "TopSeam", isSeam: true, declarations: ["@Instantiated let feature: Feature"])], dependencies: appDependencies),
			]
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Core", "SeamModule", "Sub"]),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Core", "Impl", "SeamModule", "Sub"]),
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Core", "Impl", "SeamModule", "Sub"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsTheFillAndEveryModuleBetweenTheSeams_whenTheRootListsOnlyTheOuterSeamsModule() async throws {
		func modules(appDependencies: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: ["public protocol Tracker {}\n"]),
				ModuleFixture(name: "InnerSeamModule", packageName: "Base", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "InnerSeam", isSeam: true, declarations: ["@Instantiated let tracker: any Tracker"])], dependencies: ["Core"]),
				ModuleFixture(name: "PlainModule", packageName: "Base", swiftFileContent: ["import InnerSeamModule\n\n" + seamFixtureType(named: "Plain", declarations: ["@Instantiated let innerSeam: InnerSeam"])], dependencies: ["InnerSeamModule"]),
				ModuleFixture(name: "OuterSeamModule", packageName: "Base", swiftFileContent: ["import PlainModule\n\n" + seamFixtureType(named: "OuterSeam", isSeam: true, declarations: ["@Instantiated let plain: Plain"])], dependencies: ["PlainModule"]),
				ModuleFixture(name: "Impl", packageName: "Base", swiftFileContent: ["import Core\n\n" + Self.leafTrackerImplementation], dependencies: ["Core"]),
				ModuleFixture(name: "Sub", packageName: "Base", swiftFileContent: ["import Impl\n\n" + seamFixtureType(named: "SubThing", declarations: [])], dependencies: ["Impl"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Core\nimport OuterSeamModule\nimport Sub\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let outerSeam: OuterSeam"])], dependencies: appDependencies),
			]
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Core", "OuterSeamModule", "Sub"]),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Core", "Impl", "InnerSeamModule", "OuterSeamModule", "PlainModule", "Sub"]),
			integration: .moduleInfo,
			compileVerification: .skipped,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Core", "Impl", "InnerSeamModule", "OuterSeamModule", "PlainModule", "Sub"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsNothingBeneath_whenASeamBetweenTheRootAndTheHoleFillsIt() async throws {
		// `OuterSeam`'s module reads `TrackerImpl`, so its tree fills the hole of the seam it calls, and `App`'s tree needs nothing.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: ["public protocol Tracker {}\n"]),
				ModuleFixture(name: "InnerSeamModule", packageName: "Base", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "InnerSeam", isSeam: true, declarations: ["@Instantiated let tracker: any Tracker"])], dependencies: ["Core"]),
				ModuleFixture(name: "Impl", packageName: "Base", swiftFileContent: ["import Core\n\n" + Self.leafTrackerImplementation], dependencies: ["Core"]),
				ModuleFixture(name: "OuterSeamModule", packageName: "Base", swiftFileContent: ["import Impl\nimport InnerSeamModule\n\n" + seamFixtureType(named: "OuterSeam", isSeam: true, declarations: ["@Instantiated let innerSeam: InnerSeam"])], dependencies: ["Impl", "InnerSeamModule"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import OuterSeamModule\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let outerSeam: OuterSeam"])], dependencies: ["OuterSeamModule"]),
			],
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["OuterSeamModule"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsWhatTheFillOfASeamBetweenLeavesOpen_whenTheFillHasAHoleOfItsOwn() async throws {
		func modules(appDependencies: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: ["public protocol Logger {}\n\npublic protocol Tracker {}\n"]),
				ModuleFixture(name: "InnerSeamModule", packageName: "Base", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "InnerSeam", isSeam: true, declarations: ["@Instantiated let tracker: any Tracker"])], dependencies: ["Core"]),
				ModuleFixture(name: "Impl", packageName: "Base", swiftFileContent: ["import Core\n\n@Instantiable(fulfillingAdditionalTypes: [Tracker.self])\npublic struct TrackerImpl: Instantiable, Tracker {\n    public init(logger: any Logger) {\n        self.logger = logger\n    }\n\n    @Instantiated let logger: any Logger\n}\n"], dependencies: ["Core"]),
				ModuleFixture(name: "OuterSeamModule", packageName: "Base", swiftFileContent: ["import Impl\nimport InnerSeamModule\n\n" + seamFixtureType(named: "OuterSeam", isSeam: true, declarations: ["@Instantiated let innerSeam: InnerSeam"])], dependencies: ["Impl", "InnerSeamModule"]),
				ModuleFixture(name: "LogImpl", packageName: "Base", swiftFileContent: ["import Core\n\n@Instantiable(fulfillingAdditionalTypes: [Logger.self])\npublic struct LoggerImpl: Instantiable, Logger {\n    public init() {}\n}\n"], dependencies: ["Core"]),
				ModuleFixture(name: "Sub", packageName: "Base", swiftFileContent: ["import LogImpl\n\n" + seamFixtureType(named: "SubThing", declarations: [])], dependencies: ["LogImpl"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Core\nimport OuterSeamModule\nimport Sub\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let outerSeam: OuterSeam"])], dependencies: appDependencies),
			]
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Core", "OuterSeamModule", "Sub"]),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Core", "Impl", "InnerSeamModule", "LogImpl", "OuterSeamModule", "Sub"]),
			integration: .moduleInfo,
			compileVerification: .skipped,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Core", "Impl", "InnerSeamModule", "LogImpl", "OuterSeamModule", "Sub"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsNoModuleOnARouteASeamFills_whenAnotherRouteReachesTheSameHole() async throws {
		// `Root` reaches `HoleOwner` through its own `InnerSeam` and through `FillingSeam`, whose module fills the hole, so
		// `Mid`, which only that second route passes through, is not needed.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: ["public protocol Tracker {}\n"]),
				ModuleFixture(name: "InnerSeamModule", packageName: "Base", swiftFileContent: [
					"import Core\n\n" + seamFixtureType(named: "HoleOwner", declarations: ["@Instantiated let tracker: any Tracker"]),
					"import Core\n\n" + seamFixtureType(named: "InnerSeam", isSeam: true, declarations: ["@Instantiated let holeOwner: HoleOwner"]),
				], dependencies: ["Core"]),
				ModuleFixture(name: "Impl", packageName: "Base", swiftFileContent: ["import Core\n\n" + Self.leafTrackerImplementation], dependencies: ["Core"]),
				ModuleFixture(name: "MidModule", packageName: "Base", swiftFileContent: ["import InnerSeamModule\n\n" + seamFixtureType(named: "Mid", declarations: ["@Instantiated let innerSeam: InnerSeam"])], dependencies: ["InnerSeamModule"]),
				ModuleFixture(name: "CallingSeamModule", packageName: "Base", swiftFileContent: ["import MidModule\n\n" + seamFixtureType(named: "CallingSeam", isSeam: true, declarations: ["@Instantiated let mid: Mid"])], dependencies: ["MidModule"]),
				ModuleFixture(name: "FillingSeamModule", packageName: "Base", swiftFileContent: ["import CallingSeamModule\nimport Impl\n\n" + seamFixtureType(named: "FillingSeam", isSeam: true, declarations: ["@Instantiated let callingSeam: CallingSeam"])], dependencies: ["CallingSeamModule", "Impl"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Core\nimport FillingSeamModule\nimport Impl\nimport InnerSeamModule\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let fillingSeam: FillingSeam", "@Instantiated let innerSeam: InnerSeam"])], dependencies: ["Core", "FillingSeamModule", "Impl", "InnerSeamModule"]),
			],
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Core", "FillingSeamModule", "Impl", "InnerSeamModule"])
		try expectEveryModuleCompiled(output)
	}

	// MARK: Tests – Access of a declaration beneath

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsPackageTypeOfModuleBeneath_whenTheModuleNamingItIsInItsPackage() async throws {
		func modules(appDependencies: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: ["@Instantiable\npackage final class Cache: Instantiable {\n    package init() {}\n}\n"]),
				ModuleFixture(name: "Middle", packageName: "Base", swiftFileContent: ["import Deep\n\n@Instantiable\npackage struct FeedScreen: Instantiable {\n    package init(cache: Cache) {\n        self.cache = cache\n    }\n\n    @Instantiated let cache: Cache\n}\n"], dependencies: ["Deep"]),
				ModuleFixture(name: "App", packageName: "Base", swiftFileContent: ["import Middle\n\n@Instantiable(isRoot: true)\npackage struct Root: Instantiable {\n    package init(feedScreen: FeedScreen) {\n        self.feedScreen = feedScreen\n    }\n\n    @Instantiated let feedScreen: FeedScreen\n}\n"], dependencies: appDependencies),
			]
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Middle"]),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Deep", "Middle"]),
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		try expectEveryModuleCompiled(output)
	}

	// MARK: Tests – How the module was read

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsModulesBeneath_whenTheRootIsInAnAdditionalDirectory() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.deepAndMiddle + [
				ModuleFixture(name: "Extra", packageName: "App", swiftFileContent: ["import Middle\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let feedScreen: FeedScreen"])], runsSafeDI: false),
				ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
					"SafeDIConfiguration.swift": "#SafeDIConfiguration(additionalDirectoriesToInclude: [\"$FIXTURE_ROOT/App/Sources/Extra\"])\n",
				], dependencies: ["Middle"]),
			],
			integration: .moduleInfo,
			compileVerification: .skipped,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		// The module's run validated `Root`, which it does not generate, with `Deep`'s declarations.
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.generatedFile(importing: ["Deep", "Middle"], """
		// SafeDI generates Root's init() only in the module that declares Root. If Root() does not compile, add the SafeDI plugin to the target that declares Root.
		""")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsModulesBeneath_whenTheModuleComesFromScansCache() async throws {
		let deep = try await executeSafeDIToolTest(
			swiftFileContent: [Self.clock],
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "Deep"],
		)
		let modulesBeneathCSV = URL.temporaryFile
		try deep.writtenModuleInfoOutputPath.write(to: modulesBeneathCSV, atomically: true, encoding: .utf8)
		filesToDelete.append(modulesBeneathCSV)
		let output = try await executeSafeDIToolTest(
			swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let clock: Clock"])],
			pluginInvocation: .scanWhilePlanning(reportsFixtureDirectoryThroughSymbolicLink: false),
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			moduleMembershipArguments: ["--transitive-module-info-file-path", modulesBeneathCSV.path],
		)
		#expect(output.generatedFiles == ["Root+SafeDI.swift": Self.generatedFile(importing: ["Deep"], """
		extension Root {
		    public init() {
		        let clock = Clock()
		        self.init(clock: clock)
		    }
		}
		""")])
	}

	// MARK: Tests – Only trees ask, and nothing declines

	@Test(arguments: [
		(seamModuleDependencies: ["Mid"], passesSet: true),
		(seamModuleDependencies: ["Deep", "Mid"], passesSet: false),
	] as [(seamModuleDependencies: [String], passesSet: Bool)])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateDeclaration_whenTheModuleBeneathASeamNeedsCollidesWithTheSeamsModule(seamModuleDependencies: [String], passesSet: Bool) async {
		await assertThrowsMultiModuleError(inModule: "SeamModule", diagnostics: { fixtures in
			let message = Self.duplicateDeclarationMessage(of: "Helper", inModules: "`Deep` and `SeamModule`")
			return "\(fixtures["SeamModule"]!["Helper.swift"]):1:1: \(message)\n\(fixtures["Deep"]!["Helper.swift"]):1:1: \(message)"
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [Self.clock, Self.publicHelper]),
					ModuleFixture(name: "Mid", packageName: "Base", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "MidThing", declarations: ["@Instantiated let clock: Clock"])], dependencies: ["Deep"]),
					ModuleFixture(name: "SeamModule", packageName: "App", swiftFileContent: [Self.publicHelper, "import Mid\n\n" + seamFixtureType(named: "Seam", isSeam: true, declarations: ["@Instantiated let midThing: MidThing"])], dependencies: seamModuleDependencies),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				modulesBeneath: passesSet ? { $0 } : nil,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesTheSameMock_whenOnlyAMockReachesAModuleBeneathThatHoldsAnInternalHandWrittenMock() async throws {
		try await expectTheSetChangesNothing(for: [
			ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: ["@Instantiable\npublic struct Clock: Instantiable {\n    public init() {}\n\n    static func mock() -> Clock {\n        Clock()\n    }\n}\n"]),
			ModuleFixture(name: "Middle", packageName: "Base", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "FeedScreen", declarations: ["@Instantiated let clock: Clock"])], dependencies: ["Deep"]),
			Self.appWithMock(root: .buildingNothing),
		], module: "App", expectedDependencies: ["Middle"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesTheSameMock_whenOnlyAMockReachesAModuleBeneathThatExtendsAnInternalTypeOfTheName() async throws {
		try await expectTheSetChangesNothing(for: [
			ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: ["struct Cache {\n    init() {}\n}\n\n@Instantiable\nextension Cache: Instantiable {\n    static func instantiate() -> Cache {\n        Cache()\n    }\n}\n"]),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: ["public struct Cache {\n    public init() {}\n}\n", "import Deep\n\n" + seamFixtureType(named: "FeedScreen", declarations: ["@Received let cache: Cache"])], dependencies: ["Deep"]),
			Self.appWithMock(root: .buildingNothing),
		], module: "App", expectedDependencies: ["Middle"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTypeOfModuleBeneath_whenAFileWithNoSafeDIDeclarationReExportsTheModule() async throws {
		// `Facade`, whose re-export is how `Sub` sees `Models`, is not read, so the generated code imports `Models` itself.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Models", packageName: "Base", swiftFileContent: [Self.clock]),
				ModuleFixture(name: "Facade", packageName: "Base", swiftFileContent: ["@_exported import Models\n", seamFixtureType(named: "FacadeThing", declarations: [])], dependencies: ["Models"]),
				ModuleFixture(name: "Sub", packageName: "Base", swiftFileContent: ["import Facade\n\n" + seamFixtureType(named: "FeedScreen", declarations: ["@Instantiated let clock: Clock"])], dependencies: ["Facade", "Models"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Sub\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let feedScreen: FeedScreen"])], dependencies: ["Sub"]),
			],
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.generatedFile(importing: ["Facade", "Models", "Sub"], """
		extension Root {
		    public init() {
		        func __safeDI_feedScreen() -> FeedScreen {
		            let clock = Clock()
		            return FeedScreen(clock: clock)
		        }
		        let feedScreen: FeedScreen = __safeDI_feedScreen()
		        self.init(feedScreen: feedScreen)
		    }
		}
		""")])
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Models", "Sub"])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: [
		(appDependencies: ["Middle"], passesSet: true),
		(appDependencies: ["Deep", "M2", "Middle"], passesSet: false),
	] as [(appDependencies: [String], passesSet: Bool)])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateDeclaration_whenARootOfAModuleReadFromBeneathNeedsAModuleThatCollides(appDependencies: [String], passesSet: Bool) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = Self.duplicateDeclarationMessage(of: "Helper", inModules: "`App` and `Deep`")
			return "\(fixtures["App"]!["Helper.swift"]):1:1: \(message)\n\(fixtures["Deep"]!["Helper.swift"]):1:1: \(message)"
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [seamFixtureType(named: "DeepThing", declarations: []), Self.publicHelper]),
					ModuleFixture(name: "M2", packageName: "Base", swiftFileContent: [seamFixtureType(named: "Thing", declarations: []), "import Deep\n\n" + seamFixtureType(named: "OtherRoot", isRoot: true, declarations: ["@Instantiated let deepThing: DeepThing"])], dependencies: ["Deep"]),
					ModuleFixture(name: "Middle", packageName: "Base", swiftFileContent: ["import M2\n\n" + seamFixtureType(named: "Screen", declarations: ["@Instantiated let thing: Thing"])], dependencies: ["M2", "Deep"]),
					ModuleFixture(name: "App", packageName: "App", swiftFileContent: [Self.publicHelper, "import Middle\n\n" + seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let screen: Screen"])], dependencies: appDependencies),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				modulesBeneath: passesSet ? { $0 } : nil,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsNothingBeneath_whenOnlyAMockReachesATypeNoTreeReaches() async throws {
		try await expectTheSetChangesNothing(for: Self.deepAndMiddle + [Self.appWithMock(root: .buildingNothing)], module: "App", expectedDependencies: ["Middle"])
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTheTypeUnfulfilled_whenOnlyAModuleItListsDeclaresARootAndThatRootNeedsAModuleBeneath(passesSet: Bool) async {
		// A module with no tree of its own asks for nothing, whatever the trees of the modules it lists need.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"\(fixtures["Middle"]!["MiddleRoot.swift"]):9:5: error: No @Instantiable type or extension fulfills `Clock`, which @Instantiated property `clock: Clock` instantiates. Decorate `Clock`, or an extension of it, with @Instantiable; list `Clock` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; or, if such a declaration is in another module, make that module one SafeDI reads for this target: add its target to this target's `dependencies` in `Package.swift`, declare that module with `safedi_swift_library` (or a `safedi_compile` rule) and list its `<name>_safedi` target in this target's `safedi_deps` under Bazel, or give its target `SafeDI.preCompileScript` and list its module in the `dependencies:` of this target's `SafeDI.preCompileScript` under Tuist."
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [Self.clock]),
					ModuleFixture(name: "Middle", packageName: "Base", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "MiddleRoot", isRoot: true, declarations: ["@Instantiated let clock: Clock"])], dependencies: ["Deep"]),
					ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Middle\n\n" + seamFixtureType(named: "Screen", declarations: [])], dependencies: ["Middle"]),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				modulesBeneath: passesSet ? { $0 } : nil,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: ["isRoot: true", "generateDependencyTree: true"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsNothingBeneath_whenTheOnlyTreeIsInAnInactiveClause(treeArgument: String) async throws {
		try await expectTheSetChangesNothing(for: Self.deepAndMiddle + [
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
				"""
				import Middle

				#if FEATURE
				@Instantiable(\(treeArgument))
				public struct Tree: Instantiable {
				    public init(feedScreen: FeedScreen) {
				        self.feedScreen = feedScreen
				    }

				    @Instantiated let feedScreen: FeedScreen
				}
				#endif

				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(feedScreen: FeedScreen) {
				        self.feedScreen = feedScreen
				    }

				    @Instantiated let feedScreen: FeedScreen
				}
				""",
			], dependencies: ["Middle"]),
		], module: "App", expectedDependencies: ["Middle"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateDeclaration_whenTwoModulesBeneathDeclareTheTypeARootBuilds() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = Self.duplicateDeclarationMessage(of: "Clock", inModules: "`DeepLeft` and `DeepRight`")
			return "\(fixtures["DeepLeft"]!["Clock.swift"]):1:1: \(message)\n\(fixtures["DeepRight"]!["Clock.swift"]):1:1: \(message)"
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "DeepLeft", packageName: "Base", swiftFileContent: [Self.clock]),
					ModuleFixture(name: "DeepRight", packageName: "Base", swiftFileContent: [Self.clock]),
					ModuleFixture(name: "MidLeft", packageName: "Base", swiftFileContent: [seamFixtureType(named: "MidLeftThing", declarations: [])], dependencies: ["DeepLeft"]),
					ModuleFixture(name: "MidRight", packageName: "Base", swiftFileContent: [seamFixtureType(named: "MidRightThing", declarations: [])], dependencies: ["DeepRight"]),
					ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import DeepLeft\nimport DeepRight\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let clock: Clock"])], dependencies: ["MidLeft", "MidRight"]),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				modulesBeneath: { $0 },
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [
		[0, 1, 2, 3, 4, 5],
		[5, 4, 3, 2, 1, 0],
		[3, 0, 5, 1, 4, 2],
		[1, 3, 0, 4, 2, 5],
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsEveryDuplicateDeclaration_whateverTheTypesThatReachTheCollidingModulesAreNamed(screenNumbers: [Int]) async {
		let moduleIndices = Array(screenNumbers.indices)
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = Self.duplicateDeclarationMessage(
				of: "Helper",
				inModules: "`Deep0`, `Deep1`, `Deep2`, `Deep3`, `Deep4`, and `Deep5`",
				remedy: "Rename all but one",
			)
			return moduleIndices
				.map { "\(fixtures["Deep\($0)"]!["Helper.swift"]):1:1: \(message)" }
				.joined(separator: "\n")
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: moduleIndices.flatMap { index in
					[
						ModuleFixture(name: "Deep\(index)", packageName: "Base", swiftFileContent: [seamFixtureType(named: "Value\(index)", declarations: []), Self.publicHelper]),
						ModuleFixture(name: "Middle\(index)", packageName: "Base", swiftFileContent: ["import Deep\(index)\n\n" + seamFixtureType(named: "Owner\(index)", declarations: ["@Instantiated let value: Value\(index)"])], dependencies: ["Deep\(index)"]),
					]
				} + [
					ModuleFixture(
						name: "App",
						packageName: "App",
						swiftFileContent: moduleIndices.map { index in
							"import Middle\(index)\n\n" + seamFixtureType(named: "Screen\(screenNumbers[index])", declarations: ["@Instantiated let owner: Owner\(index)"])
						} + [seamFixtureType(named: "Root", isRoot: true, declarations: screenNumbers.map { "@Instantiated let screen\($0): Screen\($0)" })],
						dependencies: moduleIndices.map { "Middle\($0)" },
					),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				modulesBeneath: { $0 },
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTypeARootNamesByString_whenTheRootDoesNotImportTheModuleBeneathThatDeclaresIt() async throws {
		func modules(appDependencies: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Contracts", packageName: "Base", swiftFileContent: ["public protocol Thing {}\n\npublic struct AnyThing: Thing {\n    public init(_ thing: some Thing) {}\n}\n"]),
				ModuleFixture(name: "Impl", packageName: "Base", swiftFileContent: ["import Contracts\n\n" + seamFixtureType(named: "DefaultThing", declarations: [], conformances: ", Thing")], dependencies: ["Contracts"]),
				ModuleFixture(name: "Sub", packageName: "Base", swiftFileContent: ["import Impl\n\n" + seamFixtureType(named: "SubThing", declarations: [])], dependencies: ["Impl"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Contracts\nimport Sub\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated(fulfilledByType: \"DefaultThing\", erasedToConcreteExistential: true) let thing: AnyThing"])], dependencies: appDependencies),
			]
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Contracts", "Sub"]),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Contracts", "Impl", "Sub"]),
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Contracts", "Impl", "Sub"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsTheModuleBeneath_whenATreeBuildsItsTypeAndNoModuleTheRunReadsImportsIt() async throws {
		// `Sub` imports `Impl`, but no tree needs `Sub`, so no file this run reads imports the module that declares `DefaultThing`.
		func modules(appDependencies: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Contracts", packageName: "Base", swiftFileContent: ["public protocol Thing {}\n\npublic struct AnyThing: Thing {\n    public init(_ thing: some Thing) {}\n}\n"]),
				ModuleFixture(name: "Impl", packageName: "Base", swiftFileContent: ["import Contracts\n\n" + seamFixtureType(named: "DefaultThing", declarations: [], conformances: ", Thing")], dependencies: ["Contracts"]),
				ModuleFixture(name: "Sub", packageName: "Base", swiftFileContent: ["import Impl\n\n" + seamFixtureType(named: "SubThing", declarations: [])], dependencies: ["Impl"]),
				ModuleFixture(name: "Top", packageName: "Base", swiftFileContent: ["import Sub\n\n" + seamFixtureType(named: "TopThing", declarations: [])], dependencies: ["Sub"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Contracts\nimport Top\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated(fulfilledByType: \"DefaultThing\", erasedToConcreteExistential: true) let thing: AnyThing", "@Instantiated let topThing: TopThing"])], dependencies: appDependencies),
			]
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Contracts", "Top"]),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Contracts", "Impl", "Sub", "Top"]),
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.generatedFile(importing: ["Contracts", "Impl", "Sub", "Top"], """
		extension Root {
		    public init() {
		        let thing = AnyThing(DefaultThing())
		        let topThing = TopThing()
		        self.init(thing: thing, topThing: topThing)
		    }
		}
		""")])
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Contracts", "Impl", "Top"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsTheModuleBeneath_whenARootFillsASeamsHoleWithItsTypeAndNoModuleTheRunReadsImportsIt() async throws {
		func modules(appDependencies: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Contracts", packageName: "Base", swiftFileContent: ["public protocol Thing {}\n"]),
				ModuleFixture(name: "Feature", packageName: "Base", swiftFileContent: ["import Contracts\n\n" + seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let thing: any Thing"])], dependencies: ["Contracts"]),
				ModuleFixture(name: "Impl", packageName: "Base", swiftFileContent: ["import Contracts\n\n" + Self.leafThingImplementation], dependencies: ["Contracts"]),
				ModuleFixture(name: "Sub", packageName: "Base", swiftFileContent: ["import Impl\n\n" + seamFixtureType(named: "SubThing", declarations: [])], dependencies: ["Impl"]),
				ModuleFixture(name: "Top", packageName: "Base", swiftFileContent: ["import Sub\n\n" + seamFixtureType(named: "TopThing", declarations: [])], dependencies: ["Sub"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Feature\nimport Top\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let screen: Screen", "@Instantiated let topThing: TopThing"])], dependencies: appDependencies),
			]
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Feature", "Top"]),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Feature", "Impl", "Sub", "Top"]),
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Feature", "Impl", "Top"])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsTheModuleBeneathInAMockFile_whenTheMockBuildsItsTypeAndNoModuleTheRunReadsImportsIt() async throws {
		// A run that writes a file per output imports in each what that file needs, and only such a run writes a mock on its own.
		let contracts = try await executeSafeDIToolTest(
			swiftFileContent: ["public protocol Thing {}\n\npublic struct AnyThing: Thing {\n    public init(_ thing: some Thing) {}\n}\n"],
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "Contracts"],
		)
		let impl = try await executeSafeDIToolTest(
			swiftFileContent: [seamFixtureType(named: "DefaultThing", declarations: [])],
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "Impl"],
		)
		let modulesBeneathCSV = URL.temporaryFile
		try impl.writtenModuleInfoOutputPath.write(to: modulesBeneathCSV, atomically: true, encoding: .utf8)
		filesToDelete.append(modulesBeneathCSV)
		let thingDeclaration = "@Instantiated(fulfilledByType: \"DefaultThing\", erasedToConcreteExistential: true) let thing: AnyThing"
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"import Contracts\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [thingDeclaration]),
				"import Contracts\n\n" + seamFixtureType(named: "Screen", declarations: [thingDeclaration]).replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n"),
			],
			dependentModuleInfoPaths: [contracts.writtenModuleInfoOutputPath],
			pluginInvocation: .scanWhilePlanning(reportsFixtureDirectoryThroughSymbolicLink: false),
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			moduleMembershipArguments: ["--transitive-module-info-file-path", modulesBeneathCSV.path],
		)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": Self.generatedFile(importing: ["Contracts", "Impl"], """
			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			"""),
			"SafeDIMockConfiguration.swift": Self.generatedFile(importing: ["Contracts", "Impl"], ""),
			"Screen+SafeDIMock.swift": Self.generatedFile(importing: ["Contracts", "Impl"], """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            thing: (() -> AnyThing)? = nil
			        ) {
			            self.thing = thing
			        }

			        let thing: (() -> AnyThing)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let thing = if let safeDIBuilder = safeDIOverrides.thing { safeDIBuilder() } else { AnyThing(DefaultThing()) }
			        return Screen(thing: thing)
			    }
			}
			#endif
			"""),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheAttributeOfTheImport_whenAFileTheRunReadsImportsTheModuleBeneathWithOne() async throws {
		// `Clock`'s initializer is visible only through `Sub`'s `@_spi` import, which the code generated for `App` must repeat.
		func modules(appDependencies: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: ["@Instantiable\npublic struct Clock: Instantiable {\n    @_spi(Inner) public init() {}\n}\n"]),
				ModuleFixture(name: "Sub", packageName: "Base", swiftFileContent: ["@_spi(Inner) import Deep\n\n" + seamFixtureType(named: "FeedScreen", declarations: ["@Instantiated let clock: Clock"])], dependencies: ["Deep"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Sub\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let feedScreen: FeedScreen"])], dependencies: appDependencies),
			]
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Sub"]),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Deep", "Sub"]),
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Deep)
		@_spi(Inner) import Deep
		#endif
		#if canImport(Sub)
		import Sub
		#endif

		extension Root {
		    public init() {
		        func __safeDI_feedScreen() -> FeedScreen {
		            let clock = Clock()
		            return FeedScreen(clock: clock)
		        }
		        let feedScreen: FeedScreen = __safeDI_feedScreen()
		        self.init(feedScreen: feedScreen)
		    }
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsTheModuleBeneathInProductionCode_whenAReadFileImportsItOnlyForMocks() async throws {
		// With `DEBUG` inactive, `Impl` is among the file's mock imports alone, so production code gets no import of it from the file.
		let contracts = try await executeSafeDIToolTest(
			swiftFileContent: ["public protocol Thing {}\n\npublic struct AnyThing: Thing {\n    public init(_ thing: some Thing) {}\n}\n"],
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "Contracts"],
		)
		let impl = try await executeSafeDIToolTest(
			swiftFileContent: [seamFixtureType(named: "DefaultThing", declarations: [])],
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "Impl"],
		)
		let modulesBeneathCSV = URL.temporaryFile
		try impl.writtenModuleInfoOutputPath.write(to: modulesBeneathCSV, atomically: true, encoding: .utf8)
		filesToDelete.append(modulesBeneathCSV)
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"import Contracts\n#if DEBUG\nimport Impl\n#endif\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated(fulfilledByType: \"DefaultThing\", erasedToConcreteExistential: true) let thing: AnyThing"]),
			],
			dependentModuleInfoPaths: [contracts.writtenModuleInfoOutputPath],
			pluginInvocation: .scanWhilePlanning(reportsFixtureDirectoryThroughSymbolicLink: false),
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
			moduleMembershipArguments: ["--transitive-module-info-file-path", modulesBeneathCSV.path],
		)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": Self.generatedFile(importing: ["Contracts", "Impl"], """
			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			"""),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTheHoleAtTheRoot_whenNoModuleBeneathDeclaresTheFill() async {
		// `App` opens the files for `Clock`, and no module beneath declares what fills the hole, so a root cannot fill it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):12:5: error: No @Instantiable type or extension that module `App` can see fulfills `Tracker`, which @Instantiated property `tracker: any Tracker` instantiates in chain: Root -> Feature. `Feature` generates its dependency tree in module `SeamModule`, which cannot see one either, so the initializer SafeDI generated for it takes `trackerBuilder`, whose case `tracker` builds `tracker`, and `Root`, a root, must fill it. Decorate `Tracker`, or an extension of it, with @Instantiable; list `Tracker` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; or, if such a declaration is in another module, make that module one SafeDI reads for this target: add its target to this target's `dependencies` in `Package.swift`, declare that module with `safedi_swift_library` (or a `safedi_compile` rule) and list its `<name>_safedi` target in this target's `safedi_deps` under Bazel, or give its target `SafeDI.preCompileScript` and list its module in the `dependencies:` of this target's `SafeDI.preCompileScript` under Tuist.
			\(fixtures["SeamModule"]!["Feature.swift"]):9:5: note: `Feature` instantiates `tracker: any Tracker` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: ["public protocol Tracker {}\n"]),
					ModuleFixture(name: "SeamModule", packageName: "Base", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "Feature", isSeam: true, declarations: ["@Instantiated let tracker: any Tracker"])], dependencies: ["Core"]),
					ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [Self.clock]),
					ModuleFixture(name: "Middle", packageName: "Base", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "FeedScreen", declarations: ["@Instantiated let clock: Clock"])], dependencies: ["Deep"]),
					ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Core\nimport Middle\nimport SeamModule\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let feature: Feature", "@Instantiated let feedScreen: FeedScreen"])], dependencies: ["Core", "Middle", "SeamModule"]),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				modulesBeneath: { $0 },
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsTheModuleASeamNeeds_whenNoModuleIsKnownToGenerateTheSeam() async throws {
		// A declaration in a directory a module's `#SafeDIConfiguration` adds records no module, so every tree builds it inline.
		func modules(appDependencies: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [Self.clock]),
				ModuleFixture(name: "Extra", packageName: "Lib", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "ExtraSeam", isSeam: true, declarations: ["@Instantiated let clock: Clock"])], runsSafeDI: false),
				ModuleFixture(name: "Lib", packageName: "Lib", swiftFileContentByFilePath: [
					"SafeDIConfiguration.swift": "#SafeDIConfiguration(additionalDirectoriesToInclude: [\"$FIXTURE_ROOT/Lib/Sources/Extra\"])\n",
				], dependencies: ["Deep"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Lib\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let extraSeam: ExtraSeam"])], dependencies: appDependencies),
			]
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Lib"]),
			integration: .moduleInfo,
			compileVerification: .skipped,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules(appDependencies: ["Deep", "Lib"]),
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Deep", "Lib"])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let clock = seamFixtureType(named: "Clock", declarations: [])

	/// `DefaultThing`, which fulfills `Thing` and builds nothing.
	private static let leafThingImplementation = """
	@Instantiable(fulfillingAdditionalTypes: [Thing.self])
	public struct DefaultThing: Instantiable, Thing {
	    public init() {}
	}
	"""

	/// `TrackerImpl`, which fulfills `Tracker` and builds nothing.
	private static let leafTrackerImplementation = """
	@Instantiable(fulfillingAdditionalTypes: [Tracker.self])
	public struct TrackerImpl: Instantiable, Tracker {
	    public init() {}
	}
	"""

	/// `TrackerImpl`, which fulfills `Tracker` and builds a `Clock`.
	private static let trackerImplementation = """
	@Instantiable(fulfillingAdditionalTypes: [Tracker.self])
	public struct TrackerImpl: Instantiable, Tracker {
	    public init(clock: Clock) {
	        self.clock = clock
	    }

	    @Instantiated let clock: Clock
	}
	"""

	/// `App`, whose root builds `SeamModule`'s seam, whose hole `Impl`'s `TrackerImpl` fills, whose tree builds `Deep`'s `Clock`.
	private static func seamFilledOverDeep(appDependencies: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: ["public protocol Tracker {}\n"]),
			ModuleFixture(name: "SeamModule", packageName: "Base", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "Feature", isSeam: true, declarations: ["@Instantiated let tracker: any Tracker"])], dependencies: ["Core"]),
			ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [clock]),
			ModuleFixture(name: "Impl", packageName: "Base", swiftFileContent: ["import Core\nimport Deep\n\n" + trackerImplementation], dependencies: ["Core", "Deep"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Core\nimport Impl\nimport SeamModule\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let feature: Feature"])], dependencies: appDependencies),
		]
	}

	/// A type no other module can name, which more than one module can declare.
	private static let internalHelper = """
	@Instantiable
	final class Helper: Instantiable {
	    init() {}
	}
	"""

	/// A type every module that reads its module can name, so two modules' declarations of it collide wherever a run reads both.
	private static let publicHelper = seamFixtureType(named: "Helper", declarations: [])

	/// A `mockOnly` declaration of `Clock`.
	private static let mockOnlyClock = """
	@Instantiable(mockOnly: true)
	extension Clock: Instantiable {
	    public static func mock() -> Clock {
	        Clock()
	    }
	}
	"""

	/// `Left` and `Deep` each declare `Clock`, `Right` lists `Deep`, and `App`'s root instantiates `Clock`.
	private static func twoModulesDeclaringClock(appDependencies: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [clock]),
			ModuleFixture(name: "Left", packageName: "Base", swiftFileContent: [clock]),
			ModuleFixture(name: "Right", packageName: "Base", swiftFileContent: [seamFixtureType(named: "RightScreen", declarations: [])], dependencies: ["Deep"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Left\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let clock: Clock"])], dependencies: appDependencies),
		]
	}

	/// `Deep`, which declares `Clock`, and `Middle`, which lists it and declares `FeedScreen`, which builds a `Clock`.
	private static let deepAndMiddle = [
		ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [clock]),
		ModuleFixture(name: "Middle", packageName: "Base", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "FeedScreen", declarations: ["@Instantiated let clock: Clock"])], dependencies: ["Deep"]),
	]

	/// `App`, whose root builds `Middle`'s `FeedScreen`, which builds `Deep`'s `Clock`.
	private static func rootOverMiddleOverDeep(appDependencies: [String]) -> [ModuleFixture] {
		deepAndMiddle + [
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Middle\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let feedScreen: FeedScreen"])], dependencies: appDependencies),
		]
	}

	/// What `appWithMock` declares beside the mock.
	private enum RootBesideMock {
		case none
		case buildingScreen
		case buildingNothing

		var declarations: [String] {
			switch self {
			case .none:
				[]
			case .buildingScreen:
				[seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let screen: Screen"])]
			case .buildingNothing:
				[seamFixtureType(named: "Root", isRoot: true, declarations: [])]
			}
		}
	}

	/// `App`, whose `Screen` generates a mock whose tree reaches `Deep`, with `root` beside it.
	private static func appWithMock(root: RootBesideMock) -> ModuleFixture {
		ModuleFixture(
			name: "App",
			packageName: "App",
			swiftFileContent: [
				"import Middle\n\n" + seamFixtureType(named: "Screen", declarations: ["@Instantiated let feedScreen: FeedScreen"]).replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n"),
			] + root.declarations,
			dependencies: ["Middle"],
		)
	}

	/// The error `generate` reports at each declaration of a type named `typeName`, when the modules `modules` spells each declare one.
	private static func duplicateDeclarationMessage(of typeName: String, inModules modules: String, remedy: String = "Rename one") -> String {
		"error: `\(typeName)` is declared in modules \(modules). SafeDI tells apart by name the @Instantiable types a module can name. \(remedy)."
	}

	/// `App`, whose root builds `Middle`'s seam `FeedScreen`, whose tree builds `Inner`'s `InnerScreen` and `Deep`'s `Clock`.
	private static func seamOverInnerOverDeep(middleDependencies: [String], appDependencies: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Deep", packageName: "Base", swiftFileContent: [clock]),
			ModuleFixture(name: "Inner", packageName: "Base", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "InnerScreen", declarations: ["@Instantiated let clock: Clock"])], dependencies: ["Deep"]),
			ModuleFixture(name: "Middle", packageName: "Base", swiftFileContent: ["import Inner\n\n" + seamFixtureType(named: "FeedScreen", isSeam: true, declarations: ["@Instantiated let innerScreen: InnerScreen"])], dependencies: middleDependencies),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Middle\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let feedScreen: FeedScreen"])], dependencies: appDependencies),
		]
	}

	private static let appBuildingFeedScreen = generatedFile(importing: ["Deep", "Middle"], """
	extension Root {
	    public init() {
	        func __safeDI_feedScreen() -> FeedScreen {
	            let clock = Clock()
	            return FeedScreen(clock: clock)
	        }
	        let feedScreen: FeedScreen = __safeDI_feedScreen()
	        self.init(feedScreen: feedScreen)
	    }
	}
	""")

	/// `Screen.mock()` and the mock configuration of `FeedScreen`, when the module's mock builds `Deep`'s `Clock`.
	private static let screenMockBuildingClock = """
	#if DEBUG
	extension Screen {
	    /// Overrides for the mock dependency tree.
	    struct SafeDIOverrides {
	        init(
	            feedScreen: FeedScreen.SafeDIMockConfiguration = .init()
	        ) {
	            self.feedScreen = feedScreen
	        }

	        let feedScreen: FeedScreen.SafeDIMockConfiguration
	    }

	    static func mock(
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Screen {
	        func __safeDI_feedScreen() -> FeedScreen {
	            let clock = if let safeDIBuilder = safeDIOverrides.feedScreen.clock { safeDIBuilder() } else { Clock() }
	            return if let safeDIBuilder = safeDIOverrides.feedScreen.safeDIBuilder { safeDIBuilder(clock) } else { FeedScreen(clock: clock) }
	        }
	        let feedScreen: FeedScreen = __safeDI_feedScreen()
	        return Screen(feedScreen: feedScreen)
	    }
	}
	#endif

	#if DEBUG
	extension FeedScreen {
	    /// Configuration for how this type is constructed within a mock tree.
	    struct SafeDIMockConfiguration {
	        init(
	            clock: (() -> Clock)? = nil,
	            _ safeDIBuilder: ((Clock) -> FeedScreen)? = nil
	        ) {
	            self.clock = clock
	            self.safeDIBuilder = safeDIBuilder
	        }

	        let clock: (() -> Clock)?
	        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
	        let safeDIBuilder: ((Clock) -> FeedScreen)?
	    }
	}
	#endif
	"""

	private static func generatedFile(importing moduleNames: [String], _ body: String) -> String {
		generatedFileHeader + moduleNames.map { "#if canImport(\($0))\nimport \($0)\n#endif" }.joined(separator: "\n") + "\n\n" + body
	}

	/// What the module's `.safedi` holds, with the test's fixture root removed from every path, so two runs' files compare
	/// by what else they hold.
	private static func withoutFixtureRoot(_ output: MultiModuleTestOutput, module moduleName: String) -> String? {
		output.modules[moduleName]?.moduleInfoFile.map {
			reflectedDescription(of: $0).description.replacingOccurrences(of: output.fixtureRoot.path, with: "")
		}
	}

	/// Expects `moduleName` to generate what it generates when no module beneath is passed, to read only
	/// `expectedDependencies`, and to compile.
	private mutating func expectTheSetChangesNothing(for modules: [ModuleFixture], module moduleName: String, expectedDependencies: [String], sourceLocation: SourceLocation = #_sourceLocation) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules,
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules,
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules[moduleName]?.generatedFiles == reference.modules[moduleName]?.generatedFiles, sourceLocation: sourceLocation)
		#expect(output.modules[moduleName]?.moduleInfoFile?.dependencyModuleNames == expectedDependencies, sourceLocation: sourceLocation)
		try expectEveryModuleCompiled(output, sourceLocation: sourceLocation)
	}

	/// Expects every module of `output` to have compiled, when this run verifies compilation.
	private func expectEveryModuleCompiled(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.moduleName) == output.moduleNames, sourceLocation: sourceLocation)
		#expect(compilation.failure == nil, sourceLocation: sourceLocation)
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension URL {
	fileprivate static var temporaryFile: URL {
		#if os(Linux)
			FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		#else
			URL.temporaryDirectory.appending(path: UUID().uuidString)
		#endif
	}
}

/// How a root's `safedi_deps` read.
enum HandWrittenList: Sendable {
	/// The modules the root imports.
	case direct
	/// Every module beneath the root, as the manual asked before SafeDI's Bazel rule collected them.
	case complete
}

/// The order `generate` is told of the modules beneath a module, which must decide nothing.
enum ListingOrder: Sendable {
	case dependencyOrder
	case reverseDependencyOrder
	case everyModuleTwice

	func arranged(_ moduleNames: [String]) -> [String] {
		switch self {
		case .dependencyOrder:
			moduleNames
		case .reverseDependencyOrder:
			moduleNames.reversed()
		case .everyModuleTwice:
			moduleNames + moduleNames.reversed()
		}
	}
}
