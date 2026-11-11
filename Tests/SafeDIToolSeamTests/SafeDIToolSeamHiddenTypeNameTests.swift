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

/// Types a module cannot name do not compete with the types it can: two modules that each keep an internal `Store` build
/// an app that reaches both through seams, as Swift accepts them, and SafeDI still checks each one. Every successful cell
/// is compiled, and the code the app generates is compared with a build that gives the second type another name.
struct SafeDIToolSeamHiddenTypeNameTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Types the app cannot name

	@Test(arguments: MultiModuleIntegration.allCases, HiddenAccessScenario.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAppAsIfTypesHadDifferentNames_whenAppCannotNameTypesOfOneName(integration: MultiModuleIntegration, scenario: HiddenAccessScenario) async throws {
		func modules(secondStoreName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: scenario.packageOfFirstModule, swiftFileContentByFilePath: ["Store.swift": Self.store(scenario.accessLevel), "SeamA.swift": Self.seam("SeamA")]),
				ModuleFixture(name: "ModB", packageName: scenario.packageOfSecondModule, swiftFileContentByFilePath: ["Store.swift": Self.store(scenario.accessLevel, named: secondStoreName), "SeamB.swift": Self.seam("SeamB", holding: secondStoreName)]),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"])], dependencies: ["ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondStoreName: "Store"), visible: modules(secondStoreName: "OtherStore"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsApp_whenRootBeneathTwoModulesSharesNameThatAppCannotName(integration: MultiModuleIntegration) async throws {
		func modules(secondRootName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Home.swift": Self.internalRoot(named: "Home")]),
				ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["\(secondRootName).swift": Self.internalRoot(named: secondRootName)]),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: [], importing: ["ModA", "ModB"])], dependencies: ["ModA", "ModB"]),
			]
		}

		let hidden = try await executeSafeDIToolMultiModuleTest(modules: modules(secondRootName: "Home"), integration: integration, filesToDelete: &filesToDelete)
		let visible = try await executeSafeDIToolMultiModuleTest(modules: modules(secondRootName: "OtherHome"), integration: integration, compileVerification: .skipped, filesToDelete: &filesToDelete)

		// The Swift package plugin writes a file for each root its target's files list, and tells apart files of one root's name.
		#expect(hidden.modules["App"]?.generatedFiles[integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift"] == visible.modules["App"]?.generatedFiles[integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift"])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAppAsIfTypesHadDifferentNames_whenThirdModuleOfPackageMentionsItsPackagesType(integration: MultiModuleIntegration) async throws {
		// `SeamN` names `ModA`'s `package` type, which the app, in another package, cannot.
		func modules(secondStoreName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: "PackageA", swiftFileContentByFilePath: ["Store.swift": Self.store("package")]),
				ModuleFixture(name: "ModB", packageName: "PackageB", swiftFileContentByFilePath: ["Store.swift": Self.store("package", named: secondStoreName), "SeamB.swift": Self.seam("SeamB", holding: secondStoreName)]),
				ModuleFixture(name: "ModN", packageName: "PackageA", swiftFileContentByFilePath: ["SeamN.swift": "import ModA\n\n" + Self.seam("SeamN")], dependencies: ["ModA"]),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamN: SeamN", "seamB: SeamB"], importing: ["ModB", "ModN"])], dependencies: ["ModA", "ModB", "ModN"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondStoreName: "Store"), visible: modules(secondStoreName: "OtherStore"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsMissingDependencyOfPackageType_whenThirdModuleOfPackageMentionsIt(integration: MultiModuleIntegration) async {
		// The check beneath `SeamN`'s mention is what a rename only inside the declaring module would lose.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Store.swift", in: "ModA", fixtures: fixtures, integration: integration)):4:5: \(Self.missingDatabaseMessage(chain: "Root -> SeamN -> ModA.Store"))
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "ModA", packageName: "PackageA", swiftFileContentByFilePath: ["Store.swift": Self.storeReceivingDatabase("package"), "Database.swift": Self.database]),
					ModuleFixture(name: "ModB", packageName: "PackageB", swiftFileContentByFilePath: ["Store.swift": Self.store("package"), "SeamB.swift": Self.seam("SeamB")]),
					ModuleFixture(name: "ModN", packageName: "PackageA", swiftFileContentByFilePath: ["SeamN.swift": "import ModA\n\n" + Self.seam("SeamN")], dependencies: ["ModA"]),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamN: SeamN", "seamB: SeamB"], importing: ["ModB", "ModN"])], dependencies: ["ModA", "ModB", "ModN"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – Types the app sees beside types it cannot name

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAppsOwnType_whenAppsInternalTypeIsBesideOneAModuleKeeps(integration: MultiModuleIntegration) async throws {
		func modules(storeNameInModule: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal", named: storeNameInModule), "SeamA.swift": Self.seam("SeamA", holding: storeNameInModule)]),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal"), "Root.swift": Self.root(holding: ["store: Store", "seamA: SeamA"], importing: ["ModA"], access: "internal")], dependencies: ["ModA"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(storeNameInModule: "Store"), visible: modules(storeNameInModule: "OtherStore"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsEachModule_whenEachModuleOfDependencyChainKeepsTypeOfOneName(integration: MultiModuleIntegration) async throws {
		func modules(lowestStoreName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal", named: lowestStoreName), "SeamB.swift": Self.seam("SeamB", holding: lowestStoreName)]),
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal"), "SeamA.swift": "import ModB\n\n" + Self.seam("SeamA", holding: "Store", andHolding: "seamB: SeamB")], dependencies: ["ModB"]),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal"), "Root.swift": Self.root(holding: ["store: Store", "seamA: SeamA"], importing: ["ModA"], access: "internal")], dependencies: ["ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(lowestStoreName: "Store"), visible: modules(lowestStoreName: "OtherStore"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsVisibleModulesType_whenAppCanNameOneOfTwoTypesOfOneName(integration: MultiModuleIntegration) async throws {
		// `ModA`'s `package` type is in the app's package and `ModB`'s is not, so a bare `Store` in the app is `ModA`'s.
		func modules(secondStoreName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("package")]),
				ModuleFixture(name: "ModB", packageName: "Elsewhere", swiftFileContentByFilePath: ["Store.swift": Self.store("package", named: secondStoreName), "SeamB.swift": Self.seam("SeamB", holding: secondStoreName)]),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["store: Store", "seamB: SeamB"], importing: ["ModA", "ModB"], access: "internal")], dependencies: ["ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondStoreName: "Store"), visible: modules(secondStoreName: "OtherStore"), integration: integration)
	}

	// MARK: Tests – Claims of one name

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_letsEachModuleFulfillPublicProtocol_whenTwoHiddenTypesFulfillIt(integration: MultiModuleIntegration) async throws {
		func modules(secondProtocolName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Storing.swift": "public protocol Storing {}\npublic protocol OtherStoring {}"]),
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Disk.swift": "import Core\n\n" + Self.fulfiller("Disk", of: "Storing"), "SeamA.swift": "import Core\n\n" + Self.seam("SeamA", holding: "Storing")], dependencies: ["Core"]),
				ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Memory.swift": "import Core\n\n" + Self.fulfiller("Memory", of: secondProtocolName), "SeamB.swift": "import Core\n\n" + Self.seam("SeamB", holding: secondProtocolName)], dependencies: ["Core"]),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"])], dependencies: ["Core", "ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondProtocolName: "Storing"), visible: modules(secondProtocolName: "OtherStoring"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_letsEachModuleFulfillItsProtocol_whenPublicTypesClaimInternalProtocolsOfOneName(integration: MultiModuleIntegration) async throws {
		// The fulfilling types are `public`, but the name they claim is one the app cannot write.
		func modules(secondProtocolName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Storing.swift": "protocol Storing {}", "Disk.swift": Self.fulfiller("Disk", of: "Storing", access: "public"), "SeamA.swift": Self.seam("SeamA", holding: "Storing")]),
				ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["\(secondProtocolName).swift": "protocol \(secondProtocolName) {}", "Memory.swift": Self.fulfiller("Memory", of: secondProtocolName, access: "public"), "SeamB.swift": Self.seam("SeamB", holding: secondProtocolName)]),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"])], dependencies: ["ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondProtocolName: "Storing"), visible: modules(secondProtocolName: "OtherStoring"), integration: integration)
	}

	// MARK: Tests – A claimed name the app can write

	@Test(arguments: MultiModuleIntegration.allCases, ["Logger", "Logger?", "any Logger", "[Logger]"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsPublicProtocolAsWritten_whenPublicTypeForwardsProtocolItsModuleKeepsAFulfillerOf(integration: MultiModuleIntegration, loggerType: String) async throws {
		func modules(secondProtocolName: String) -> [ModuleFixture] {
			[
				Self.loggerCore,
				Self.moduleKeepingLogger(named: "ModA", fulfiller: "ALogger", seam: "SeamA", protocolName: "Logger", additionalFiles: ["DetailA.swift": Self.detail(named: "DetailA", attribute: "Forwarded", loggerType: loggerType)]),
				Self.moduleKeepingLogger(named: "ModB", fulfiller: "BLogger", seam: "SeamB", protocolName: secondProtocolName),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB", "makeDetail: Instantiator<DetailA>"], importing: ["Core", "ModA", "ModB"])], dependencies: ["Core", "ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondProtocolName: "Logger"), visible: modules(secondProtocolName: "OtherLogger"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamWithPublicProtocol_whenSeamForwardsProtocolItsModuleKeepsAFulfillerOf(integration: MultiModuleIntegration) async throws {
		func modules(secondProtocolName: String) -> [ModuleFixture] {
			[
				Self.loggerCore,
				ModuleFixture(name: "ModA", packageName: "ModAPackage", swiftFileContentByFilePath: ["ALogger.swift": "import Core\n\n" + Self.fulfiller("ALogger", of: "Logger"), "Inner.swift": Self.innerHoldingLogger, "SeamA.swift": Self.seamBeside(attribute: "Forwarded")], dependencies: ["Core"]),
				Self.moduleKeepingLogger(named: "ModB", fulfiller: "BLogger", seam: "SeamB", protocolName: secondProtocolName),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["makeSeamA: Instantiator<SeamA>", "seamB: SeamB"], importing: ["Core", "ModA", "ModB"])], dependencies: ["Core", "ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondProtocolName: "Logger"), visible: modules(secondProtocolName: "OtherLogger"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesAppsValue_whenPublicTypeReceivesProtocolItsModuleKeepsAFulfillerOf(integration: MultiModuleIntegration) async throws {
		func modules(secondProtocolName: String) -> [ModuleFixture] {
			[
				Self.loggerCore,
				Self.moduleKeepingLogger(named: "ModA", fulfiller: "ALogger", seam: "SeamA", protocolName: "Logger", additionalFiles: ["DetailA.swift": Self.detail(named: "DetailA", attribute: "Received")]),
				Self.moduleKeepingLogger(named: "ModB", fulfiller: "BLogger", seam: "SeamB", protocolName: secondProtocolName),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["AppLogger.swift": "import Core\n\n" + Self.fulfiller("AppLogger", of: "Logger", access: "public"), "Root.swift": Self.root(holding: ["logger: Logger", "seamA: SeamA", "seamB: SeamB", "detail: DetailA"], importing: ["Core", "ModA", "ModB"])], dependencies: ["Core", "ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondProtocolName: "Logger"), visible: modules(secondProtocolName: "OtherLogger"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesAppsValueToSeam_whenSeamReceivesProtocolItsModuleKeepsAFulfillerOf(integration: MultiModuleIntegration) async throws {
		func modules(secondProtocolName: String) -> [ModuleFixture] {
			[
				Self.loggerCore,
				ModuleFixture(name: "ModA", packageName: "ModAPackage", swiftFileContentByFilePath: ["ALogger.swift": "import Core\n\n" + Self.fulfiller("ALogger", of: "Logger"), "Inner.swift": Self.innerHoldingLogger, "SeamA.swift": Self.seamBeside(attribute: "Received")], dependencies: ["Core"]),
				Self.moduleKeepingLogger(named: "ModB", fulfiller: "BLogger", seam: "SeamB", protocolName: secondProtocolName),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["AppLogger.swift": "import Core\n\n" + Self.fulfiller("AppLogger", of: "Logger", access: "public"), "Root.swift": Self.root(holding: ["logger: Logger", "seamA: SeamA", "seamB: SeamB"], importing: ["Core", "ModA", "ModB"])], dependencies: ["Core", "ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondProtocolName: "Logger"), visible: modules(secondProtocolName: "OtherLogger"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesModulesOwnValue_whenDependencyReceivesProtocolThatTwoModulesBeneathKeepFulfillersOf(integration: MultiModuleIntegration) async throws {
		func modules(modulesBeneathClaim claimedProtocolName: String) -> [ModuleFixture] {
			[
				Self.loggerCore,
				Self.moduleKeepingLogger(named: "Feature", fulfiller: "FLogger", seam: "SeamF", protocolName: claimedProtocolName, additionalFiles: ["Detail.swift": Self.detail(named: "Detail", attribute: "Received")]),
				Self.moduleKeepingLogger(named: "Other", fulfiller: "OLogger", seam: "SeamO", protocolName: claimedProtocolName),
				ModuleFixture(
					name: "ModA",
					packageName: "ModAPackage",
					swiftFileContentByFilePath: [
						"ALogger.swift": "import Core\n\n" + Self.fulfiller("ALogger", of: "Logger"),
						"SeamA.swift": "import Core\nimport Feature\nimport Other\n\n" + Self.seam("SeamA", holding: "Logger", label: "logger", andHolding: "detail: Detail"),
					],
					dependencies: ["Core", "Feature", "Other"],
				),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA"], importing: ["ModA"])], dependencies: ["Core", "ModA"]),
			]
		}

		let hidden = try await executeSafeDIToolMultiModuleTest(modules: modules(modulesBeneathClaim: "Logger"), integration: integration, filesToDelete: &filesToDelete)
		let visible = try await executeSafeDIToolMultiModuleTest(modules: modules(modulesBeneathClaim: "OtherLogger"), integration: integration, compileVerification: .skipped, filesToDelete: &filesToDelete)

		#expect(hidden.modules["ModA"]?.generatedFiles == visible.modules["ModA"]?.generatedFiles)
	}

	// `Instantiator` requires an `Instantiable` type, which a protocol's existential is not.
	@Test(arguments: MultiModuleIntegration.allCases, [HiddenReachForm.erasedFulfilledByType, .alias, .lazilyInstantiated])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAppAsIfClaimsHadDifferentNames_whenSeamReachesPublicProtocolThroughForm(integration: MultiModuleIntegration, form: HiddenReachForm) async throws {
		func modules(secondProtocolName: String) -> [ModuleFixture] {
			[
				Self.loggerCore,
				ModuleFixture(name: "ModA", packageName: "ModAPackage", swiftFileContentByFilePath: ["ALogger.swift": "import Core\n\n" + Self.fulfiller("ALogger", of: "Logger"), "SeamA.swift": "import Core\n\n" + form.seam(named: "SeamA", storeName: "Logger")], dependencies: ["Core"]),
				ModuleFixture(name: "ModB", packageName: "ModBPackage", swiftFileContentByFilePath: ["BLogger.swift": "import Core\n\n" + Self.fulfiller("BLogger", of: secondProtocolName), "SeamB.swift": "import Core\n\n" + form.seam(named: "SeamB", storeName: secondProtocolName)], dependencies: ["Core"]),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"])], dependencies: ["Core", "ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondProtocolName: "Logger"), visible: modules(secondProtocolName: "OtherLogger"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAppAsIfClaimsHadDifferentNames_whenSeamHoldsProtocolSpelledWithAny(integration: MultiModuleIntegration) async throws {
		func modules(secondProtocolName: String) -> [ModuleFixture] {
			[
				Self.loggerCore,
				ModuleFixture(name: "ModA", packageName: "ModAPackage", swiftFileContentByFilePath: ["ALogger.swift": "import Core\n\n" + Self.fulfiller("ALogger", of: "Logger"), "SeamA.swift": "import Core\n\n" + Self.seam("SeamA", holding: "any Logger", label: "logger")], dependencies: ["Core"]),
				Self.moduleKeepingLogger(named: "ModB", fulfiller: "BLogger", seam: "SeamB", protocolName: secondProtocolName),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"])], dependencies: ["Core", "ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondProtocolName: "Logger"), visible: modules(secondProtocolName: "OtherLogger"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsPublicProtocolAsWritten_whenFulfillersModuleDeclaresTheProtocol(integration: MultiModuleIntegration) async throws {
		// `ModB`'s protocol of the name is `internal`, so only `ModA`'s is one the app can write.
		func modules(secondProtocolName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: "ModAPackage", swiftFileContentByFilePath: ["Logger.swift": "public protocol Logger {}", "ALogger.swift": Self.fulfiller("ALogger", of: "Logger"), "SeamA.swift": Self.seam("SeamA", holding: "Logger", label: "logger"), "DetailA.swift": Self.detail(named: "DetailA", attribute: "Forwarded", imports: "")]),
				ModuleFixture(name: "ModB", packageName: "ModBPackage", swiftFileContentByFilePath: ["\(secondProtocolName).swift": "protocol \(secondProtocolName) {}", "BLogger.swift": Self.fulfiller("BLogger", of: secondProtocolName), "SeamB.swift": Self.seam("SeamB", holding: secondProtocolName, label: "logger")]),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB", "makeDetail: Instantiator<DetailA>"], importing: ["ModA", "ModB"])], dependencies: ["ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondProtocolName: "Logger"), visible: modules(secondProtocolName: "OtherLogger"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsPackageProtocolAsWritten_whenAppIsInThePackageThatDeclaresIt(integration: MultiModuleIntegration) async throws {
		func modules(secondProtocolName: String) -> [ModuleFixture] {
			func module(named moduleName: String, fulfiller fulfillerName: String, seam seamName: String, protocolName: String, additionalFiles: [String: String] = [:]) -> ModuleFixture {
				var files = ["\(fulfillerName).swift": "import Core\n\n" + Self.fulfiller(fulfillerName, of: protocolName), "\(seamName).swift": "import Core\n\n" + Self.seam(seamName, holding: protocolName, label: "logger")]
				files.merge(additionalFiles) { _, additional in additional }
				return ModuleFixture(name: moduleName, packageName: "Shop", swiftFileContentByFilePath: files, dependencies: ["Core"])
			}
			return [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Logger.swift": "package protocol Logger {}\npackage protocol OtherLogger {}"]),
				module(named: "ModA", fulfiller: "ALogger", seam: "SeamA", protocolName: "Logger", additionalFiles: ["DetailA.swift": Self.detail(named: "DetailA", attribute: "Forwarded", access: "package")]),
				module(named: "ModB", fulfiller: "BLogger", seam: "SeamB", protocolName: secondProtocolName),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB", "makeDetail: Instantiator<DetailA>"], importing: ["Core", "ModA", "ModB"], access: "package")], dependencies: ["Core", "ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondProtocolName: "Logger"), visible: modules(secondProtocolName: "OtherLogger"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsProtocolAsWritten_whenNoModuleSafeDIReadsDeclaresIt(integration: MultiModuleIntegration) async throws {
		func modules(secondProtocolName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: "ModAPackage", swiftFileContentByFilePath: ["Disk.swift": Self.fulfiller("Disk", of: "Sendable"), "SeamA.swift": Self.seam("SeamA", holding: "Sendable", label: "logger"), "DetailA.swift": Self.detail(named: "DetailA", attribute: "Forwarded", imports: "", loggerType: "Sendable")]),
				ModuleFixture(name: "ModB", packageName: "ModBPackage", swiftFileContentByFilePath: ["Memory.swift": Self.fulfiller("Memory", of: secondProtocolName), "SeamB.swift": Self.seam("SeamB", holding: secondProtocolName, label: "logger")]),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB", "makeDetail: Instantiator<DetailA>"], importing: ["ModA", "ModB"])], dependencies: ["ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondProtocolName: "Sendable"), visible: modules(secondProtocolName: "Error"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_leavesAppUnchanged_whenModuleHoldsMockOnlyDeclarationOfProtocolItsTypeFulfills(integration: MultiModuleIntegration) async throws {
		// A `mockOnly` declaration left under the bare name would be the mock of `Logger` in the app, which cannot build it.
		func modules(additionalFiles: [String: String]) -> [ModuleFixture] {
			[
				Self.loggerCore,
				Self.moduleKeepingLogger(named: "ModA", fulfiller: "ALogger", seam: "SeamA", protocolName: "Logger", additionalFiles: additionalFiles),
				Self.moduleKeepingLogger(named: "ModB", fulfiller: "BLogger", seam: "SeamB", protocolName: "Logger"),
				ModuleFixture(
					name: "App",
					packageName: "AppPackage",
					swiftFileContentByFilePath: [
						"Thing.swift": "import Core\n\n" + Self.detail(named: "Thing", attribute: "Received", imports: "", attributes: "generateMock: true"),
						"Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"]),
					],
					dependencies: ["Core", "ModA", "ModB"],
				),
			]
		}
		let fakeLogger = """
		import Core

		struct FakeLogger: Logger {}

		@Instantiable(fulfillingAdditionalTypes: [Logger.self], mockOnly: true)
		extension FakeLogger {
		    static func mock() -> FakeLogger {
		        FakeLogger()
		    }
		}
		"""

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(additionalFiles: ["FakeLogger.swift": fakeLogger]), visible: modules(additionalFiles: [:]), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsMissingDependency_whenTypeTheAppCannotNameFulfillsPublicProtocolAndReceivesIt(integration: MultiModuleIntegration) async {
		// The tree beneath the fulfiller is still checked, though the name it claims is left as written.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "ALogger.swift", in: "ModA", fixtures: fixtures, integration: integration)):7:5: \(Self.missingDatabaseMessage(chain: "Root -> SeamA -> ALogger"))
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.loggerCore,
					ModuleFixture(
						name: "ModA",
						packageName: "ModAPackage",
						swiftFileContentByFilePath: [
							"Database.swift": Self.database,
							"ALogger.swift": """
							import Core

							@Instantiable(fulfillingAdditionalTypes: [Logger.self])
							struct ALogger: Logger, Instantiable {
							    init(database: Database) { self.database = database }

							    @Received let database: Database
							}
							""",
							"SeamA.swift": "import Core\n\n" + Self.seam("SeamA", holding: "Logger", label: "logger"),
						],
						dependencies: ["Core"],
					),
					Self.moduleKeepingLogger(named: "ModB", fulfiller: "BLogger", seam: "SeamB", protocolName: "Logger"),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"])], dependencies: ["Core", "ModA", "ModB"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – A mention that means another type

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsModulesOwnTypeAsWritten_whenModuleDeclaresPlainTypeOfNameItsPackageHides(integration: MultiModuleIntegration) async throws {
		func modules(secondStoreName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("package"), "SeamA.swift": Self.seam("SeamA")]),
				ModuleFixture(name: "ModB", packageName: "Other", swiftFileContentByFilePath: ["Store.swift": Self.store("internal", named: secondStoreName), "SeamB.swift": Self.seam("SeamB", holding: secondStoreName)]),
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContentByFilePath: [
						"Store.swift": "import ModA\n\npublic struct Store {\n    public init() {}\n}",
						"Detail.swift": Self.detail(named: "Detail", attribute: "Forwarded", imports: "", loggerType: "Store"),
					],
					dependencies: ["ModA"],
				),
				ModuleFixture(name: "App", packageName: "Elsewhere", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB", "makeDetail: Instantiator<Detail>"], importing: ["ModA", "ModB", "Feature"])], dependencies: ["ModA", "ModB", "Feature"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondStoreName: "Store"), visible: modules(secondStoreName: "OtherStore"), integration: integration)
	}

	// MARK: Tests – What a mention in another module means

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateName_whenModuleThatMentionsNameReadsPublicTypeBesidePackageTypeOfIt(integration: MultiModuleIntegration) async {
		// `Detail` means `Lib`'s `Store`; only another file of `Feature` imports `ModA`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Store.swift", in: "ModB", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateNameMessage)
			\(Self.path(of: "Store.swift", in: "ModA", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateNameMessage)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("package"), "SeamA.swift": Self.seam("SeamA")]),
					Self.libWithPublicStore(),
					ModuleFixture(name: "ModB", packageName: "Other", swiftFileContentByFilePath: ["Store.swift": Self.store("package"), "SeamB.swift": Self.seam("SeamB")]),
					Self.featureForwardingStore(dependencies: ["Lib", "ModA"]),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB", "makeDetail: Instantiator<Detail>"], importing: ["ModA", "ModB", "Feature"])], dependencies: ["ModA", "ModB", "Feature"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateName_whenModuleThatMentionsNameReadsPublicTypeBesidePackageProtocolOfIt(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Memory.swift", in: "ModB", fixtures: fixtures, integration: integration)):1:1: \(Self.claimedNameMessage(modules: "`ModA` and `ModB`"))
			\(Self.path(of: "Disk.swift", in: "ModA", fixtures: fixtures, integration: integration)):1:1: \(Self.claimedNameMessage(modules: "`ModA` and `ModB`"))
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": "package protocol Store {}", "Disk.swift": Self.fulfiller("Disk", of: "Store", access: "package"), "SeamA.swift": Self.seam("SeamA")]),
					Self.libWithPublicStore(),
					ModuleFixture(name: "ModB", packageName: "Other", swiftFileContentByFilePath: ["Store.swift": "package protocol Store {}", "Memory.swift": Self.fulfiller("Memory", of: "Store", access: "package"), "SeamB.swift": Self.seam("SeamB")]),
					Self.featureForwardingStore(dependencies: ["Lib", "ModA"]),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB", "makeDetail: Instantiator<Detail>"], importing: ["ModA", "ModB", "Feature"])], dependencies: ["ModA", "ModB", "Feature"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateName_whenModuleThatMentionsNameReadsTypeOfItThroughAdditionalDirectory(integration: MultiModuleIntegration) async {
		// `Feature` reads `Lib`'s files through `additionalDirectoriesToInclude`, so SafeDI knows no module of the `Store` its
		// `Detail` means.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Store.swift", in: "ModB", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateNameMessage)
			\(Self.path(of: "Store.swift", in: "ModA", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateNameMessage)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("package"), "SeamA.swift": Self.seam("SeamA")]),
					Self.libWithPublicStore(),
					ModuleFixture(name: "ModB", packageName: "Other", swiftFileContentByFilePath: ["Store.swift": Self.store("package"), "SeamB.swift": Self.seam("SeamB")]),
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"Detail.swift": Self.detail(named: "Detail", attribute: "Forwarded", imports: "import Lib\n\n", loggerType: "Store"),
							"SafeDIConfiguration.swift": "#SafeDIConfiguration(additionalDirectoriesToInclude: [\"$FIXTURE_ROOT/Shop/Sources/Lib\"])\n",
						],
						dependencies: ["ModA"],
					),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB", "makeDetail: Instantiator<Detail>"], importing: ["ModA", "ModB", "Feature"])], dependencies: ["ModA", "ModB", "Feature"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_treatsMentionByModulesItReads_whenModuleReadsPackageTypeOnlyBeneathFacade(integration: MultiModuleIntegration) async throws {
		// `Feature` depends only on `Lib`, whose public `Store` it means. The Swift package plugin reads `ModA` for it too, so
		// `Feature` could mean either there.
		func modules(secondStoreName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("package"), "SeamA.swift": Self.seam("SeamA")]),
				Self.libWithPublicStore(dependencies: ["ModA"]),
				ModuleFixture(name: "ModB", packageName: "Other", swiftFileContentByFilePath: ["Store.swift": Self.store("package", named: secondStoreName), "SeamB.swift": Self.seam("SeamB", holding: secondStoreName)]),
				Self.featureForwardingStore(dependencies: ["Lib"], importsModA: false),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB", "makeDetail: Instantiator<Detail>"], importing: ["ModA", "ModB", "Feature"])], dependencies: ["ModA", "ModB", "Feature"]),
			]
		}

		switch integration {
		case .moduleInfo:
			try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondStoreName: "Store"), visible: modules(secondStoreName: "OtherStore"), integration: integration)
		case .swiftPackagePlugin:
			await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
				"""
				\(Self.path(of: "Store.swift", in: "ModB", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateNameMessage)
				\(Self.path(of: "Store.swift", in: "ModA", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateNameMessage)
				"""
			}) {
				try await executeSafeDIToolMultiModuleTest(modules: modules(secondStoreName: "Store"), integration: integration, compileVerification: .skipped, filesToDelete: &filesToDelete)
			}
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateName_whenModuleThatMentionsPublicProtocolReadsPackageTypeOfItsName(integration: MultiModuleIntegration) async {
		// `Mid` can name `Other`'s `Store` and means `Base`'s. Its run under module info reports the name it cannot tell apart;
		// under the Swift package plugin, `Mid` generates nothing, and the app reports it.
		await assertThrowsMultiModuleError(inModule: integration == .moduleInfo ? "Mid" : "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Disk.swift", in: "Base", fixtures: fixtures, integration: integration)):1:1: \(Self.claimedNameMessage(modules: "`Base` and `Other`"))
			\(Self.path(of: "Store.swift", in: "Other", fixtures: fixtures, integration: integration)):1:1: \(Self.claimedNameMessage(modules: "`Base` and `Other`"))
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.baseWithPublicStore(),
					ModuleFixture(name: "Other", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("package"), "SeamOther.swift": Self.seam("SeamOther")]),
					ModuleFixture(
						name: "Mid",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"Detail.swift": Self.detail(named: "Detail", attribute: "Forwarded", imports: "import Base\n\n", loggerType: "Store"),
							"UsesOther.swift": "import Other\n\nenum UsesOther {}",
						],
						dependencies: ["Base", "Other"],
					),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamBase: SeamBase", "seamOther: SeamOther", "makeDetail: Instantiator<Detail>"], importing: ["Base", "Other", "Mid"])], dependencies: ["Base", "Other", "Mid"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases, [["Lib", "ModA"], ["ModA", "Lib"]])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateName_whenModuleThatMentionsNameReadsTwoPackageTypesOfIt(integration: MultiModuleIntegration, readOrder: [String]) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Store.swift", in: "ModB", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateNameMessage)
			\(Self.path(of: "Store.swift", in: "ModA", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateNameMessage)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("package"), "SeamA.swift": Self.seam("SeamA")]),
					ModuleFixture(name: "Lib", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": "package struct Store {\n    package init() {}\n}"]),
					ModuleFixture(name: "ModB", packageName: "Other", swiftFileContentByFilePath: ["Store.swift": Self.store("package"), "SeamB.swift": Self.seam("SeamB")]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Detail.swift": "import Lib\n\n" + Self.forwardingStore(named: "Detail", type: "Store"), "SeamF.swift": Self.seam("SeamF", holding: "Instantiator<Detail>", label: "makeDetail")], dependencies: readOrder),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB", "seamF: SeamF"], importing: ["ModA", "ModB", "Feature"])], dependencies: ["ModA", "ModB", "Feature"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_treatsPackageTypeByWhatSafeDIIsTold_whenRunIsNotToldModulesPackage(integration: MultiModuleIntegration) async throws {
		// `ModA` and `ModN` share a package that module info runs are not told of, so those cannot say what `ModN` can name.
		func modules(secondStoreName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("package")], omitsPackageName: true),
				ModuleFixture(name: "ModB", packageName: "Other", swiftFileContentByFilePath: ["Store.swift": Self.store("package", named: secondStoreName), "SeamB.swift": Self.seam("SeamB", holding: secondStoreName)]),
				ModuleFixture(name: "ModN", packageName: "Shop", swiftFileContentByFilePath: ["Detail.swift": "import ModA\n\n" + Self.forwardingStore(named: "Detail", type: "Store"), "SeamN.swift": Self.seam("SeamN", holding: "Instantiator<Detail>", label: "makeDetail")], dependencies: ["ModA"], omitsPackageName: true),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamN: SeamN", "seamB: SeamB"], importing: ["ModB", "ModN"])], dependencies: ["ModA", "ModB", "ModN"]),
			]
		}

		switch integration {
		case .moduleInfo:
			await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
				"""
				\(Self.path(of: "Store.swift", in: "ModB", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateNameMessage)
				\(Self.path(of: "Store.swift", in: "ModA", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateNameMessage)
				"""
			}) {
				try await executeSafeDIToolMultiModuleTest(modules: modules(secondStoreName: "Store"), integration: integration, compileVerification: .skipped, filesToDelete: &filesToDelete)
			}
		case .swiftPackagePlugin:
			try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondStoreName: "Store"), visible: modules(secondStoreName: "OtherStore"), integration: integration)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_treatsMentionByWhatSafeDIRecords_whenThirdModuleAlsoReadsModuleWithoutTypeOfName(integration: MultiModuleIntegration) async throws {
		// A module's info does not record a `public` type no declaration of its module mentions, so `Core` could declare the
		// `Store` that `ModN` means. The Swift package plugin reads every file of `ModN`'s dependencies.
		func modules(secondStoreName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Core", packageName: "PackageA", swiftFileContentByFilePath: ["Theme.swift": "public struct Theme {\n    public init() {}\n}"]),
				ModuleFixture(name: "ModA", packageName: "PackageA", swiftFileContentByFilePath: ["Store.swift": Self.store("package")]),
				ModuleFixture(name: "ModB", packageName: "PackageB", swiftFileContentByFilePath: ["Store.swift": Self.store("package", named: secondStoreName), "SeamB.swift": Self.seam("SeamB", holding: secondStoreName)]),
				ModuleFixture(name: "ModN", packageName: "PackageA", swiftFileContentByFilePath: ["SeamN.swift": "import Core\nimport ModA\n\n" + Self.seam("SeamN")], dependencies: ["Core", "ModA"]),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamN: SeamN", "seamB: SeamB"], importing: ["ModB", "ModN"])], dependencies: ["Core", "ModA", "ModB", "ModN"]),
			]
		}

		switch integration {
		case .moduleInfo:
			await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
				"""
				\(Self.path(of: "Store.swift", in: "ModA", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateNameMessage)
				\(Self.path(of: "Store.swift", in: "ModB", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateNameMessage)
				"""
			}) {
				try await executeSafeDIToolMultiModuleTest(modules: modules(secondStoreName: "Store"), integration: integration, compileVerification: .skipped, filesToDelete: &filesToDelete)
			}
		case .swiftPackagePlugin:
			try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondStoreName: "Store"), visible: modules(secondStoreName: "OtherStore"), integration: integration)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAppAsIfTypesHadDifferentNames_whenThirdModuleOfPackageMentionsItsPackagesNestedType(integration: MultiModuleIntegration) async throws {
		func modules(secondStoreName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: "PackageA", swiftFileContentByFilePath: ["Outer.swift": Self.outerHoldingStore("package")]),
				ModuleFixture(name: "ModB", packageName: "PackageB", swiftFileContentByFilePath: ["Outer.swift": Self.outerHoldingStore("package", named: secondStoreName), "SeamB.swift": Self.seam("SeamB", holding: "Outer.\(secondStoreName)")]),
				ModuleFixture(name: "ModN", packageName: "PackageA", swiftFileContentByFilePath: ["SeamN.swift": "import ModA\n\n" + Self.seam("SeamN", holding: "Outer.Store")], dependencies: ["ModA"]),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamN: SeamN", "seamB: SeamB"], importing: ["ModB", "ModN"])], dependencies: ["ModA", "ModB", "ModN"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondStoreName: "Store"), visible: modules(secondStoreName: "OtherStore"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateName_whenModuleThatMentionsNestedNameReadsPublicTypeBesidePackageTypeOfIt(integration: MultiModuleIntegration) async {
		let message = "error: `Outer.Store` is declared in modules `ModA` and `ModB`. SafeDI tells apart by name the @Instantiable types a module can name. Rename one."
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Outer.swift", in: "ModB", fixtures: fixtures, integration: integration)):2:5: \(message)
			\(Self.path(of: "Outer.swift", in: "ModA", fixtures: fixtures, integration: integration)):2:5: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Outer.swift": Self.outerHoldingStore("package"), "SeamA.swift": Self.seam("SeamA", holding: "Outer.Store")]),
					ModuleFixture(name: "Lib", packageName: "Shop", swiftFileContentByFilePath: ["Outer.swift": "public enum Outer {\n    public struct Store {\n        public init() {}\n    }\n}"]),
					ModuleFixture(name: "ModB", packageName: "Other", swiftFileContentByFilePath: ["Outer.swift": Self.outerHoldingStore("package"), "SeamB.swift": Self.seam("SeamB", holding: "Outer.Store")]),
					Self.featureForwardingStore(type: "Outer.Store", dependencies: ["Lib", "ModA"]),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB", "makeDetail: Instantiator<Detail>"], importing: ["ModA", "ModB", "Feature"])], dependencies: ["ModA", "ModB", "Feature"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsModulesOwnNestedTypeAsWritten_whenModuleDeclaresNestedTypeOfNameItsPackageHides(integration: MultiModuleIntegration) async throws {
		func modules(secondStoreName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Outer.swift": Self.outerHoldingStore("package"), "SeamA.swift": Self.seam("SeamA", holding: "Outer.Store")]),
				ModuleFixture(name: "ModB", packageName: "Other", swiftFileContentByFilePath: ["Outer.swift": Self.outerHoldingStore("package", named: secondStoreName), "SeamB.swift": Self.seam("SeamB", holding: "Outer.\(secondStoreName)")]),
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContentByFilePath: [
						"Outer.swift": "import ModA\n\npublic enum Outer {\n    public struct Store {\n        public init() {}\n    }\n}",
						"Detail.swift": Self.detail(named: "Detail", attribute: "Forwarded", imports: "", loggerType: "Outer.Store"),
					],
					dependencies: ["ModA"],
				),
				ModuleFixture(name: "App", packageName: "Elsewhere", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB", "makeDetail: Instantiator<Detail>"], importing: ["ModA", "ModB", "Feature"])], dependencies: ["ModA", "ModB", "Feature"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondStoreName: "Store"), visible: modules(secondStoreName: "OtherStore"), integration: integration)
	}

	// MARK: Tests – Different types of a name the app can write

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateName_whenAppsTypeSharesNameOfPublicProtocolAThirdModuleReceives(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(Self.claimedNameMessage(modules: "`App` and `Base`"))
			\(Self.path(of: "Disk.swift", in: "Base", fixtures: fixtures, integration: integration)):1:1: \(Self.claimedNameMessage(modules: "`App` and `Base`"))
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.baseWithPublicStore(),
					Self.midReceivingStore(),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Store.swift": Self.store("public"), "Root.swift": Self.root(holding: ["store: Store", "seamBase: SeamBase", "feature: Feature"], importing: ["Base", "Mid"])], dependencies: ["Base", "Mid"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateName_whenAppsTypeSharesNameOfPublicProtocolAThirdModuleProvidesAMockOf(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(Self.claimedNameMessage(modules: "`App` and `Base`"))
			\(Self.path(of: "Disk.swift", in: "Base", fixtures: fixtures, integration: integration)):1:1: \(Self.claimedNameMessage(modules: "`App` and `Base`"))
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.baseWithPublicStore(),
					ModuleFixture(
						name: "Mid",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"FakeStore.swift": """
							import Base

							public struct FakeStore: Store {
							    public init() {}
							}

							@Instantiable(fulfillingAdditionalTypes: [Store.self], mockOnly: true)
							extension FakeStore {
							    public static func mock() -> FakeStore {
							        FakeStore()
							    }
							}
							""",
						],
						dependencies: ["Base"],
					),
					ModuleFixture(
						name: "App",
						packageName: "AppPackage",
						swiftFileContentByFilePath: [
							"Store.swift": Self.store("public"),
							"Thing.swift": """
							@Instantiable(generateMock: true)
							public struct Thing: Instantiable {
							    public init(store: Store) { self.store = store }
							    @Received let store: Store
							}
							""",
							"Root.swift": Self.root(holding: ["store: Store", "thing: Thing"], importing: ["Base", "Mid"]),
						],
						dependencies: ["Base", "Mid"],
					),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateName_whenAppsTypeSharesNameOfPublicProtocolItsFulfillersModuleReceives(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(Self.claimedNameMessage(modules: "`App` and `Base`"))
			\(Self.path(of: "Disk.swift", in: "Base", fixtures: fixtures, integration: integration)):1:1: \(Self.claimedNameMessage(modules: "`App` and `Base`"))
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.baseWithPublicStore(additionalFiles: [
						"Feature.swift": """
						@Instantiable(generateDependencyTree: true)
						public final class Feature: Instantiable {
						    init(store: Store) { self.store = store }
						    @Received let store: Store
						}
						""",
					]),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Store.swift": Self.store("public"), "Root.swift": Self.root(holding: ["store: Store", "seamBase: SeamBase", "feature: Feature"], importing: ["Base"])], dependencies: ["Base"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateName_whenModuleTheAppReadsDeclaresPublicTypeOfNameOfPublicProtocol(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Store.swift", in: "ModZ", fixtures: fixtures, integration: integration)):1:1: \(Self.claimedNameMessage(modules: "`Base` and `ModZ`"))
			\(Self.path(of: "Disk.swift", in: "Base", fixtures: fixtures, integration: integration)):1:1: \(Self.claimedNameMessage(modules: "`Base` and `ModZ`"))
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.baseWithPublicStore(),
					ModuleFixture(name: "ModZ", packageName: "Elsewhere", swiftFileContentByFilePath: ["Store.swift": Self.store("public")]),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamBase: SeamBase"], importing: ["Base", "ModZ"])], dependencies: ["Base", "ModZ"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateName_whenAppsTypeClaimsAppsOwnProtocolOfNameOfPublicProtocol(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Cloud.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(Self.claimedNameMessage(modules: "`App` and `Base`"))
			\(Self.path(of: "Disk.swift", in: "Base", fixtures: fixtures, integration: integration)):1:1: \(Self.claimedNameMessage(modules: "`App` and `Base`"))
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.baseWithPublicStore(),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Store.swift": "public protocol Store {}", "Cloud.swift": Self.fulfiller("Cloud", of: "Store", access: "public"), "Root.swift": Self.root(holding: ["store: Store", "seamBase: SeamBase"], importing: ["Base"])], dependencies: ["Base"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – Ways of reaching a type

	@Test(arguments: MultiModuleIntegration.allCases, HiddenReachForm.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAppAsIfTypesHadDifferentNames_whenSeamReachesHiddenTypeThroughForm(integration: MultiModuleIntegration, form: HiddenReachForm) async throws {
		func modules(secondStoreName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal"), "SeamA.swift": form.seam(named: "SeamA", storeName: "Store")]),
				ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal", named: secondStoreName), "SeamB.swift": form.seam(named: "SeamB", storeName: secondStoreName)]),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"])], dependencies: ["ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondStoreName: "Store"), visible: modules(secondStoreName: "OtherStore"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases, HiddenReachForm.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsMissingDependencyThroughModuleQualifiedName_whenSeamReachesHiddenTypeThroughForm(integration: MultiModuleIntegration, form: HiddenReachForm) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Store.swift", in: "ModA", fixtures: fixtures, integration: integration)):4:5: \(Self.missingDatabaseMessage(chain: "Root -> SeamA -> ModA.Store"))
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.storeReceivingDatabase("internal"), "Database.swift": Self.database, "SeamA.swift": form.seam(named: "SeamA", storeName: "Store")]),
					ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal"), "SeamB.swift": form.seam(named: "SeamB", storeName: "Store")]),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"])], dependencies: ["ModA", "ModB"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsCycleThroughHiddenType_whenAppClosesCycle(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Store.swift", in: "ModA", fixtures: fixtures, integration: integration)):6:5: error: Dependency cycle: `Thing` -> `SeamA` -> `ModA.Store` -> `Thing`. `ModA.Store` receives `thing: Thing`, which is still being built when `ModA.Store` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
			\(Self.path(of: "Impl.swift", in: "ModT", fixtures: fixtures, integration: integration)):4:1: note: `Thing` is part of the cycle
			\(Self.path(of: "SeamA.swift", in: "ModA", fixtures: fixtures, integration: integration)):3:1: note: `SeamA` is part of the cycle
			\(Self.path(of: "Store.swift", in: "ModA", fixtures: fixtures, integration: integration)):3:1: note: `ModA.Store` is part of the cycle
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Thing.swift": "public protocol Thing {}"]),
					ModuleFixture(
						name: "ModA",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"Store.swift": """
							import Core

							@Instantiable
							struct Store: Instantiable {
							    init(thing: Thing) { self.thing = thing }
							    @Received let thing: Thing
							}
							""",
							"SeamA.swift": "import Core\n\n" + Self.seam("SeamA"),
						],
						dependencies: ["Core"],
					),
					ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal"), "SeamB.swift": Self.seam("SeamB")]),
					ModuleFixture(
						name: "ModT",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"Impl.swift": """
							import Core
							import ModA

							@Instantiable(fulfillingAdditionalTypes: [Thing.self])
							public final class Impl: Thing, Instantiable {
							    public init(seamA: SeamA) { self.seamA = seamA }
							    @Instantiated let seamA: SeamA
							}
							""",
						],
						dependencies: ["Core", "ModA"],
					),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["thing: Thing", "seamB: SeamB"], importing: ["Core", "ModB"])], dependencies: ["Core", "ModA", "ModB", "ModT"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – Kinds of declaration

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAppAsIfTypesHadDifferentNames_whenExtensionsDeclareHiddenTypes(integration: MultiModuleIntegration) async throws {
		func modules(secondStoreName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.storeExtension(), "SeamA.swift": Self.seam("SeamA")]),
				ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.storeExtension(named: secondStoreName), "SeamB.swift": Self.seam("SeamB", holding: secondStoreName)]),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"])], dependencies: ["ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondStoreName: "Store"), visible: modules(secondStoreName: "OtherStore"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAppAsIfTypesHadDifferentNames_whenHiddenTypesAreNested(integration: MultiModuleIntegration) async throws {
		// `Middle` names `Store` bare, inside the type both are nested in.
		func modules(secondStoreName: String) -> [ModuleFixture] {
			func files(seam seamName: String, storeName: String) -> [String: String] {
				[
					"Feature.swift": """
					public enum Feature {
					    @Instantiable
					    struct \(storeName): Instantiable {
					        init() {}
					    }

					    @Instantiable
					    struct Middle\(seamName): Instantiable {
					        init(store: \(storeName)) { self.store = store }
					        @Instantiated let store: \(storeName)
					    }
					}
					""",
					"\(seamName).swift": Self.seam(seamName, holding: "Feature.Middle\(seamName)", label: "middle"),
				]
			}
			return [
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: files(seam: "SeamA", storeName: "Store")),
				ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: files(seam: "SeamB", storeName: secondStoreName)),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"])], dependencies: ["ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondStoreName: "Store"), visible: modules(secondStoreName: "OtherStore"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAppAsIfTypesHadDifferentNames_whenModuleQualifiesItsOwnTypeInAForwardedProperty(integration: MultiModuleIntegration) async throws {
		func modules(secondStoreName: String) -> [ModuleFixture] {
			func files(module moduleName: String, seam seamName: String, storeName: String) -> [String: String] {
				[
					"\(storeName).swift": Self.store("internal", named: storeName),
					"Child\(seamName).swift": """
					@Instantiable
					struct Child\(seamName): Instantiable {
					    init(store: \(moduleName).\(storeName)) { self.store = store }
					    @Forwarded let store: \(moduleName).\(storeName)
					}
					""",
					"\(seamName).swift": Self.seam(seamName, holding: "Instantiator<Child\(seamName)>", label: "childBuilder", andHolding: "store: \(storeName)"),
				]
			}
			return [
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: files(module: "ModA", seam: "SeamA", storeName: "Store")),
				ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: files(module: "ModB", seam: "SeamB", storeName: secondStoreName)),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"])], dependencies: ["ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondStoreName: "Store"), visible: modules(secondStoreName: "OtherStore"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAppAsIfTypesHadDifferentNames_whenModuleHoldsMockOnlyDeclarationOfHiddenType(integration: MultiModuleIntegration) async throws {
		func modules(secondStoreName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal"), "StoreFake.swift": Self.mockOnlyDeclaration(of: "Store"), "SeamA.swift": Self.seam("SeamA")]),
				ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal", named: secondStoreName), "SeamB.swift": Self.seam("SeamB", holding: secondStoreName)]),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"])], dependencies: ["ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondStoreName: "Store"), visible: modules(secondStoreName: "OtherStore"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_usesAppsMockOnlyDeclaration_whenAppDeclaresNameTwoModulesHide(integration: MultiModuleIntegration) async throws {
		func modules(secondStoreName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal", named: secondStoreName == "Store" ? "Store" : "FirstStore"), "SeamA.swift": Self.seam("SeamA", holding: secondStoreName == "Store" ? "Store" : "FirstStore")]),
				ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal", named: secondStoreName), "SeamB.swift": Self.seam("SeamB", holding: secondStoreName)]),
				ModuleFixture(
					name: "App",
					packageName: "AppPackage",
					swiftFileContentByFilePath: [
						"Store.swift": "public struct Store {\n    public init() {}\n}",
						"StoreFake.swift": Self.mockOnlyDeclaration(of: "Store"),
						"Thing.swift": """
						@Instantiable(generateMock: true)
						public struct Thing: Instantiable {
						    public init(store: Store) { self.store = store }
						    @Received let store: Store
						}
						""",
						"Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"]),
					],
					dependencies: ["ModA", "ModB"],
				),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondStoreName: "Store"), visible: modules(secondStoreName: "OtherStore"), integration: integration)
	}

	// MARK: Tests – Holes in a seam's tree

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsHoleWithAppsType_whenTypesAppCannotNameAlsoClaimTheHolesType(integration: MultiModuleIntegration) async throws {
		func modules(secondProtocolName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Storing.swift": "public protocol Storing {}\npublic protocol OtherStoring {}"]),
				ModuleFixture(name: "ModS", packageName: "Shop", swiftFileContentByFilePath: ["SeamS.swift": "import Core\n\n" + Self.seam("SeamS", holding: "Storing")], dependencies: ["Core"]),
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Disk.swift": "import Core\n\n" + Self.fulfiller("Disk", of: "Storing"), "SeamA.swift": "import Core\n\n" + Self.seam("SeamA", holding: "Storing")], dependencies: ["Core"]),
				ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Memory.swift": "import Core\n\n" + Self.fulfiller("Memory", of: secondProtocolName), "SeamB.swift": "import Core\n\n" + Self.seam("SeamB", holding: secondProtocolName)], dependencies: ["Core"]),
				ModuleFixture(
					name: "App",
					packageName: "AppPackage",
					swiftFileContentByFilePath: [
						"Cloud.swift": "import Core\n\n" + Self.fulfiller("Cloud", of: "Storing", access: "public"),
						"Root.swift": Self.root(holding: ["seamS: SeamS", "seamA: SeamA", "seamB: SeamB"], importing: ["Core", "ModS", "ModA", "ModB"]),
					],
					dependencies: ["Core", "ModS", "ModA", "ModB"],
				),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondProtocolName: "Storing"), visible: modules(secondProtocolName: "OtherStoring"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsUnfilledHole_whenOnlyTypesAppCannotNameClaimTheHolesType(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Root.swift", in: "App", fixtures: fixtures, integration: integration)):9:5: error: No @Instantiable type or extension that module `App` can see fulfills `Storing`, which @Instantiated property `store: Storing` instantiates in chain: Root -> SeamS. `SeamS` generates its dependency tree in module `ModS`, which cannot see one either, so the initializer SafeDI generated for it takes a builder for `store`, and `Root`, a root, must fill it. Decorate `Storing`, or an extension of it, with @Instantiable; list `Storing` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; or, if such a declaration is in another module, make that module one SafeDI reads for this target: add its target to this target's `dependencies` in `Package.swift`, declare that module with `safedi_swift_library` (or a `safedi_compile` rule) and list its `<name>_safedi` target in this target's `safedi_deps` under Bazel, or give its target `SafeDI.preCompileScript` and list its module in the `dependencies:` of this target's `SafeDI.preCompileScript` under Tuist.
			\(Self.path(of: "SeamS.swift", in: "ModS", fixtures: fixtures, integration: integration)):9:5: note: `SeamS` instantiates `store: Storing` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Storing.swift": "public protocol Storing {}"]),
					ModuleFixture(name: "ModS", packageName: "Shop", swiftFileContentByFilePath: ["SeamS.swift": "import Core\n\n" + Self.seam("SeamS", holding: "Storing")], dependencies: ["Core"]),
					ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Disk.swift": "import Core\n\n" + Self.fulfiller("Disk", of: "Storing"), "SeamA.swift": "import Core\n\n" + Self.seam("SeamA", holding: "Storing")], dependencies: ["Core"]),
					ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Memory.swift": "import Core\n\n" + Self.fulfiller("Memory", of: "Storing"), "SeamB.swift": "import Core\n\n" + Self.seam("SeamB", holding: "Storing")], dependencies: ["Core"]),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamS: SeamS"], importing: ["ModS"])], dependencies: ["Core", "ModS", "ModA", "ModB"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – Mocks

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAppAsIfTypesHadDifferentNames_whenSeamsHavePublicMocks(integration: MultiModuleIntegration) async throws {
		func modules(secondStoreName: String) -> [ModuleFixture] {
			[
				ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal"), "SeamA.swift": Self.seam("SeamA", attributes: "generateDependencyTree: true, generateMock: .public")]),
				ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal", named: secondStoreName), "SeamB.swift": Self.seam("SeamB", holding: secondStoreName, attributes: "generateDependencyTree: true, generateMock: .public")]),
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"], attributes: "isRoot: true, generateMock: true")], dependencies: ["ModA", "ModB"]),
			]
		}

		try await expectAppMatchesBuildWithDistinctNames(hidden: modules(secondStoreName: "Store"), visible: modules(secondStoreName: "OtherStore"), integration: integration)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_leadsWithPublicMockAndOffersNoFixIt_whenRootMockWouldBuildHiddenTypeOfOneName(integration: MultiModuleIntegration) async {
		// Widening both types, as a fix-it on each would, makes them compete in the app, which is the error this change
		// removes. The seam's initializer is an error of its own, as it is whatever the type is named.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.seamInitializerMockDiagnostics(atPath: Self.path(of: "SeamA.swift", in: "ModA", fixtures: fixtures, integration: integration), seam: "SeamA", module: "ModA"))
			\(Self.path(of: "Store.swift", in: "ModA", fixtures: fixtures, integration: integration)):2:1: \(Self.hiddenStoreMockMessage(subject: "`ModA.Store`", module: "ModA", seam: "SeamA", fixed: "`ModA.Store`"))
			\(Self.seamInitializerMockDiagnostics(atPath: Self.path(of: "SeamB.swift", in: "ModB", fixtures: fixtures, integration: integration), seam: "SeamB", module: "ModB"))
			\(Self.path(of: "Store.swift", in: "ModB", fixtures: fixtures, integration: integration)):2:1: \(Self.hiddenStoreMockMessage(subject: "`ModB.Store`", module: "ModB", seam: "SeamB", fixed: "`ModB.Store`"))
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.storeWithPublicInitializer, "SeamA.swift": Self.seam("SeamA")]),
					ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.storeWithPublicInitializer, "SeamB.swift": Self.seam("SeamB")]),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"], attributes: "isRoot: true, generateMock: true")], dependencies: ["ModA", "ModB"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsAccessOfExtendedType_whenRootMockWouldBuildHiddenTypeDeclaredByExtension(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			func diagnostics(module moduleName: String, seam seamName: String) -> String {
				let storePath = Self.path(of: "Store.swift", in: moduleName, fixtures: fixtures, integration: integration)
				return """
				\(Self.seamInitializerMockDiagnostics(atPath: Self.path(of: "\(seamName).swift", in: moduleName, fixtures: fixtures, integration: integration), seam: seamName, module: moduleName))
				\(storePath):1:1: \(Self.hiddenStoreMockMessage(subject: "`\(moduleName).Store`", module: moduleName, seam: seamName, fixed: "`\(moduleName).Store`"))
				\(storePath):7:5: \(Self.hiddenStoreMockMessage(subject: "`\(moduleName).Store.instantiate()`", module: moduleName, seam: seamName, fixed: "`\(moduleName).Store.instantiate()`"))
				"""
			}
			return diagnostics(module: "ModA", seam: "SeamA") + "\n" + diagnostics(module: "ModB", seam: "SeamB")
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.storeExtension(), "SeamA.swift": Self.seam("SeamA")]),
					ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.storeExtension(), "SeamB.swift": Self.seam("SeamB")]),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"], attributes: "isRoot: true, generateMock: true")], dependencies: ["ModA", "ModB"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – Names that stay an error

	@Test(arguments: MultiModuleIntegration.allCases, ["public", "package"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateName_whenAppCanNameBothTypes(integration: MultiModuleIntegration, accessLevel: String) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Store.swift", in: "ModA", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateNameMessage)
			\(Self.path(of: "Store.swift", in: "ModB", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateNameMessage)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel), "SeamA.swift": Self.seam("SeamA")]),
					ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel), "SeamB.swift": Self.seam("SeamB")]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"])], dependencies: ["ModA", "ModB"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateName_whenRunKnowsNoModuleAsTheXcodeProjectPluginDoes() async {
		let message = "error: Found multiple @Instantiable types or extensions that fulfill `Store`. Each type can be fulfilled by only one @Instantiable declaration, across all modules. If they are different types, rename one. If they are one type, keep one, and remove the others’ @Instantiable."
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Store.swift", in: "ModA", fixtures: fixtures, integration: .swiftPackagePlugin)):1:1: \(message)
			\(Self.path(of: "Store.swift", in: "ModB", fixtures: fixtures, integration: .swiftPackagePlugin)):1:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal"), "SeamA.swift": Self.seam("SeamA")]),
					ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal"), "SeamB.swift": Self.seam("SeamB")]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"])], dependencies: ["ModA", "ModB"]),
				],
				integration: .swiftPackagePlugin,
				compileVerification: .skipped,
				writesTargetGraph: false,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateName_whenHiddenTypesOfOneNameAreSeams(integration: MultiModuleIntegration) async {
		let message = "error: `Inner` is declared in modules `ModA` and `ModB`. SafeDI tells apart by name the @Instantiable types a module can name, and every seam and public mock a run reads. Rename one."
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Inner.swift", in: "ModA", fixtures: fixtures, integration: integration)):1:1: \(message)
			\(Self.path(of: "Inner.swift", in: "ModB", fixtures: fixtures, integration: integration)):1:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Inner.swift": Self.internalSeam(named: "Inner"), "SeamA.swift": Self.seam("SeamA", holding: "Inner", label: "inner")]),
					ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Inner.swift": Self.internalSeam(named: "Inner"), "SeamB.swift": Self.seam("SeamB", holding: "Inner", label: "inner")]),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"])], dependencies: ["ModA", "ModB"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateName_whenModuleQualifiedNameIsTakenByAnotherType(integration: MultiModuleIntegration) async {
		// `ModA.Store` already names a type, so nothing can tell `ModA`'s `Store` apart from it by that spelling.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = "error: `Store` is declared in modules `ModA` and `ModB`. SafeDI tells apart by name the @Instantiable types a module can name. Rename one."
			return """
			\(Self.path(of: "Store.swift", in: "ModA", fixtures: fixtures, integration: integration)):1:1: \(message)
			\(Self.path(of: "Store.swift", in: "ModB", fixtures: fixtures, integration: integration)):1:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["ModA.swift": "public enum ModA {\n    @Instantiable\n    public struct Store: Instantiable {\n        public init() {}\n    }\n}"]),
					ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal"), "SeamA.swift": Self.seam("SeamA")]),
					ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal"), "SeamB.swift": Self.seam("SeamB")]),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["seamA: SeamA", "seamB: SeamB"], importing: ["ModA", "ModB"])], dependencies: ["Core", "ModA", "ModB"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateName_whenTypesTheAppCannotNameClaimASpellingThatIsNotAName(integration: MultiModuleIntegration) async {
		// A `fulfillingAdditionalTypes` entry can be spelled so that no module's name can be put before it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = "error: Found multiple @Instantiable types or extensions that fulfill `[Storing]`, in modules `ModA` and `ModB`. Each type can be fulfilled by only one @Instantiable declaration a module can name. If `[Storing]` names different types, rename one. If it names one type, keep one, and remove `[Storing]` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable."
			return """
			\(Self.path(of: "Disk.swift", in: "ModA", fixtures: fixtures, integration: integration)):3:1: \(message)
			\(Self.path(of: "Memory.swift", in: "ModB", fixtures: fixtures, integration: integration)):3:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Storing.swift": "public protocol Storing {}"]),
					ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Disk.swift": "import Core\n\n" + Self.fulfiller("Disk", of: "Storing", claim: "[Storing].self")], dependencies: ["Core"]),
					ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Memory.swift": "import Core\n\n" + Self.fulfiller("Memory", of: "Storing", claim: "[Storing].self")], dependencies: ["Core"]),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: [], importing: [])], dependencies: ["Core", "ModA", "ModB"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – A tree the app builds itself

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_leadsWithSeamAndOffersNoFixIt_whenAppWouldBuildHiddenTypeOfOneNameInline(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			func message(module moduleName: String, parent parentName: String) -> String {
				"error: `\(moduleName).Store` is `internal`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Declare `\(parentName)` with `generateDependencyTree: true`, so that module `\(moduleName)` generates its tree and this module calls the initializer it generates. Making `\(moduleName).Store` `public` instead also needs a new name, if module `App` can then name another type called `Store`."
			}
			func initializerDiagnostics(module moduleName: String, parent parentName: String) -> String {
				let path = Self.path(of: "\(parentName).swift", in: moduleName, fixtures: fixtures, integration: integration)
				return """
				\(path):3:5: error: `\(parentName)`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix, or declare `\(parentName)` with `generateDependencyTree: true`, so that module `\(moduleName)` generates its tree and this module calls the initializer it generates.
				\(path):3:5-3:5: fixit: public\u{20}
				"""
			}
			return """
			\(initializerDiagnostics(module: "ModA", parent: "ParentA"))
			\(Self.path(of: "Store.swift", in: "ModA", fixtures: fixtures, integration: integration)):2:1: \(message(module: "ModA", parent: "ParentA"))
			\(initializerDiagnostics(module: "ModB", parent: "ParentB"))
			\(Self.path(of: "Store.swift", in: "ModB", fixtures: fixtures, integration: integration)):2:1: \(message(module: "ModB", parent: "ParentB"))
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "ModA", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.storeWithPublicInitializer, "ParentA.swift": Self.inlineParent(named: "ParentA")]),
					ModuleFixture(name: "ModB", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.storeWithPublicInitializer, "ParentB.swift": Self.inlineParent(named: "ParentB")]),
					ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: ["parentA: ParentA", "parentB: ParentB"], importing: ["ModA", "ModB"])], dependencies: ["ModA", "ModB"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – Determinism

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesOnlyTheTypesAppCanName_whenTwoOfTwentyFourModulesDeclareVisibleTypesOfOneName() async {
		// The names are listed neither sorted nor reversed, and the two visible declarations are neither first nor last by
		// name, so a choice made by the order of the modules, of the files, or of a dictionary fails on nearly every run.
		let moduleNames = Self.twentyFourModuleNames
		let visibleModuleNames = ["Module09", "Module14"]
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = "error: `Store` is declared in modules `Module09` and `Module14`. SafeDI tells apart by name the @Instantiable types a module can name. Rename one."
			return visibleModuleNames
				.map { "\(fixtures[$0]!["Store.swift"]):1:1: \(message)" }
				.joined(separator: "\n")
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: moduleNames.map { moduleName in
					ModuleFixture(name: moduleName, packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(visibleModuleNames.contains(moduleName) ? "public" : "internal")])
				} + [
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: [], importing: [])], dependencies: moduleNames),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsAppAsIfTypesHadDifferentNames_whenTwentyFourModulesKeepTypesOfOneName() async throws {
		func modules(storeName: (String) -> String) -> [ModuleFixture] {
			Self.twentyFourModuleNames.map { moduleName in
				ModuleFixture(name: moduleName, packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store("internal", named: storeName(moduleName)), "Seam\(moduleName).swift": Self.seam("Seam\(moduleName)", holding: storeName(moduleName))])
			} + [
				ModuleFixture(name: "App", packageName: "AppPackage", swiftFileContentByFilePath: ["Root.swift": Self.root(holding: Self.twentyFourModuleNames.map { "seam\($0): Seam\($0)" }, importing: Self.twentyFourModuleNames)], dependencies: Self.twentyFourModuleNames),
			]
		}
		let hidden = try await executeSafeDIToolMultiModuleTest(modules: modules { _ in "Store" }, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let visible = try await executeSafeDIToolMultiModuleTest(modules: modules { "Store\($0)" }, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)

		#expect(hidden.modules["App"]?.generatedFiles == visible.modules["App"]?.generatedFiles)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Compiles `hidden`, in which two modules declare a type of one name the app cannot name, and asserts the code the
	/// app generates is the code `visible`, which gives those types different names, generates, as the value it builds is.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectAppMatchesBuildWithDistinctNames(
		hidden: [ModuleFixture],
		visible: [ModuleFixture],
		integration: MultiModuleIntegration,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let hiddenOutput = try await executeSafeDIToolMultiModuleTest(modules: hidden, integration: integration, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visible, integration: integration, compileVerification: .skipped, filesToDelete: &filesToDelete, sourceLocation: sourceLocation)
		#expect(hiddenOutput.modules["App"]?.generatedFiles == visibleOutput.modules["App"]?.generatedFiles, sourceLocation: sourceLocation)
	}

	/// How two modules keep a type of one name from an app that uses both.
	enum HiddenAccessScenario: CaseIterable, CustomTestStringConvertible, Sendable {
		case internalTypes
		case packageTypesInTwoOtherPackages
		case packageTypesInOneOtherPackage

		var accessLevel: String {
			switch self {
			case .internalTypes:
				"internal"
			case .packageTypesInOneOtherPackage, .packageTypesInTwoOtherPackages:
				"package"
			}
		}

		var packageOfFirstModule: String {
			switch self {
			case .internalTypes, .packageTypesInOneOtherPackage:
				"Shop"
			case .packageTypesInTwoOtherPackages:
				"PackageA"
			}
		}

		var packageOfSecondModule: String {
			switch self {
			case .internalTypes, .packageTypesInOneOtherPackage:
				"Shop"
			case .packageTypesInTwoOtherPackages:
				"PackageB"
			}
		}

		var testDescription: String {
			"\(self)"
		}
	}

	/// A way a seam's tree reaches a type the app cannot name.
	enum HiddenReachForm: CaseIterable, CustomTestStringConvertible, Sendable {
		case erasedFulfilledByType
		case alias
		case lazilyInstantiated
		case instantiator

		func seam(named seamName: String, storeName: String) -> String {
			switch self {
			case .erasedFulfilledByType:
				"""
				struct Any\(seamName)Store {
				    init(_ store: \(storeName)) { self.store = store }
				    let store: \(storeName)
				}

				@Instantiable(generateDependencyTree: true)
				public final class \(seamName): Instantiable {
				    init(store: Any\(seamName)Store) { self.store = store }
				    @Instantiated(fulfilledByType: "\(storeName)", erasedToConcreteExistential: true) let store: Any\(seamName)Store
				}
				"""
			case .alias:
				"""
				@Instantiable(generateDependencyTree: true)
				public final class \(seamName): Instantiable {
				    init(store: \(storeName), renamed: \(storeName)) {
				        self.store = store
				        self.renamed = renamed
				    }

				    @Instantiated let store: \(storeName)
				    @Received(fulfilledByDependencyNamed: "store", ofType: \(storeName).self) let renamed: \(storeName)
				}
				"""
			case .lazilyInstantiated:
				"""
				@Instantiable(generateDependencyTree: true)
				public final class \(seamName): Instantiable {
				    init(store: LazilyInstantiated<\(storeName)>) { self.store = store }
				    @Instantiated let store: LazilyInstantiated<\(storeName)>
				}
				"""
			case .instantiator:
				"""
				@Instantiable(generateDependencyTree: true)
				public final class \(seamName): Instantiable {
				    init(store: Instantiator<\(storeName)>) { self.store = store }
				    @Instantiated let store: Instantiator<\(storeName)>
				}
				"""
			}
		}

		var testDescription: String {
			"\(self)"
		}
	}

	private static let twentyFourModuleNames = (0..<24).map { index in
		"Module\(String(format: "%02d", (index * 7) % 24))"
	}

	private static let duplicateNameMessage = "error: `Store` is declared in modules `ModA` and `ModB`. SafeDI tells apart by name the @Instantiable types a module can name. Rename one."

	/// The error for a `Store` that `modules` each fulfill, which cannot be told apart since the app can name both.
	private static func claimedNameMessage(modules: String) -> String {
		"error: Found multiple @Instantiable types or extensions that fulfill `Store`, in modules \(modules). Each type can be fulfilled by only one @Instantiable declaration a module can name. If `Store` names different types, rename one. If it names one type, keep one, and remove `Store` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable."
	}

	/// `Core`, which declares the `public` protocols `ModA` and `ModB` fulfill with types they keep.
	private static let loggerCore = ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Logger.swift": "public protocol Logger {}\npublic protocol OtherLogger {}"])

	/// A module, in a package of its own, that keeps a fulfiller of `protocolName`, and a seam that holds it.
	private static func moduleKeepingLogger(named moduleName: String, fulfiller fulfillerName: String, seam seamName: String, protocolName: String, additionalFiles: [String: String] = [:]) -> ModuleFixture {
		var files = [
			"\(fulfillerName).swift": "import Core\n\n" + fulfiller(fulfillerName, of: protocolName),
			"\(seamName).swift": "import Core\n\n" + seam(seamName, holding: protocolName, label: "logger"),
		]
		files.merge(additionalFiles) { _, additional in additional }
		return ModuleFixture(name: moduleName, packageName: "\(moduleName)Package", swiftFileContentByFilePath: files, dependencies: ["Core"])
	}

	/// A type at `access` that holds `logger: loggerType` under `@attribute`.
	private static func detail(named name: String, attribute: String, imports: String = "import Core\n\n", loggerType: String = "Logger", access: String = "public", attributes: String? = nil) -> String {
		"""
		\(imports)@Instantiable\(attributes.map { "(\($0))" } ?? "")
		\(access) struct \(name): Instantiable {
		    \(access) init(logger: \(loggerType)) { self.logger = logger }
		    @\(attribute) \(access) let logger: \(loggerType)
		}
		"""
	}

	private static let innerHoldingLogger = """
	import Core

	@Instantiable
	struct Inner: Instantiable {
	    init(logger: Logger) { self.logger = logger }
	    @Instantiated let logger: Logger
	}
	"""

	/// A seam that holds `logger: Logger` under `@attribute`, beside a dependency that makes SafeDI generate its tree.
	private static func seamBeside(attribute: String) -> String {
		"""
		import Core

		@Instantiable(generateDependencyTree: true)
		public struct SeamA: Instantiable {
		    init(logger: Logger, inner: Inner) {
		        self.logger = logger
		        self.inner = inner
		    }

		    @\(attribute) public let logger: Logger
		    @Instantiated let inner: Inner
		}
		"""
	}

	/// `Base`, which declares a `public` protocol `Store`, an `internal` type that fulfills it, and a seam that holds it.
	private static func baseWithPublicStore(additionalFiles: [String: String] = [:]) -> ModuleFixture {
		var files = [
			"Store.swift": "public protocol Store {}",
			"Disk.swift": fulfiller("Disk", of: "Store"),
			"SeamBase.swift": seam("SeamBase", holding: "Store"),
		]
		files.merge(additionalFiles) { _, additional in additional }
		return ModuleFixture(name: "Base", packageName: "Shop", swiftFileContentByFilePath: files)
	}

	/// A module of `Base`'s package with a `public` type that receives `Base`'s `Store`.
	private static func midReceivingStore() -> ModuleFixture {
		ModuleFixture(
			name: "Mid",
			packageName: "Shop",
			swiftFileContentByFilePath: [
				"Feature.swift": """
				import Base

				@Instantiable
				public struct Feature: Instantiable {
				    public init(store: Store) { self.store = store }
				    @Received let store: Store
				}
				""",
			],
			dependencies: ["Base"],
		)
	}

	/// `Lib`, a module of `Shop` that declares a `public` `Store` no declaration of its module mentions.
	private static func libWithPublicStore(dependencies: [String] = []) -> ModuleFixture {
		ModuleFixture(name: "Lib", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": "public struct Store {\n    public init() {}\n}"], dependencies: dependencies)
	}

	/// `Feature`, a module of `Shop` whose `public` `Detail` forwards `type`, in a file that imports only `Lib`; another of
	/// its files imports `ModA` when `importsModA`.
	private static func featureForwardingStore(type: String = "Store", dependencies: [String], importsModA: Bool = true) -> ModuleFixture {
		var files = ["Detail.swift": detail(named: "Detail", attribute: "Forwarded", imports: "import Lib\n\n", loggerType: type)]
		if importsModA {
			files["UsesModA.swift"] = "import ModA\n\nenum UsesModA {}"
		}
		return ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: files, dependencies: dependencies)
	}

	/// An `internal` type that forwards `store: type`, so that a module can mention a `package` type without constructing it.
	private static func forwardingStore(named name: String, type: String) -> String {
		"""
		@Instantiable
		struct \(name): Instantiable {
		    init(store: \(type)) { self.store = store }
		    @Forwarded let store: \(type)
		}
		"""
	}

	/// `Outer`, at `access`, with an `@Instantiable` type nested in it.
	private static func outerHoldingStore(_ access: String, named name: String = "Store") -> String {
		"""
		\(access) enum Outer {
		    @Instantiable
		    \(access) struct \(name): Instantiable {
		        \(access) init() {}
		    }
		}
		"""
	}

	private static let database = """
	public final class Database {
	    public init() {}
	}
	"""

	private static func missingDatabaseMessage(chain: String) -> String {
		"error: @Received property `database: Database` is not @Instantiated or @Forwarded in chain: \(chain). No @Instantiable declaration fulfills `Database`, so SafeDI cannot instantiate it. Declare `@Forwarded let database: Database` on a type below `Root` in the chain, and pass the value to the `Instantiator` that builds that type; or decorate `Database`, or an extension of it, with @Instantiable and declare `@Instantiated let database: Database` on `Root` or on another type in the chain, to fix."
	}

	/// The error at a hidden `store` or its generated-mock reach, whose fix leads with what keeps it out of the app.
	private static func hiddenStoreMockMessage(subject: String, module moduleName: String, seam seamName: String, fixed fixedDeclaration: String) -> String {
		"error: \(subject) is `internal`, so the mock of `Root`, generated in module `App`, in another package, cannot \(subject.contains("initializer") || subject.contains("instantiate") ? "call" : "construct") it in the code SafeDI generates. Give `\(seamName)` a public mock: `generateMock: .public`, or a hand-written public `mock`: mocks build a seam's tree inline, and this mock would call the mock `\(moduleName)` generates instead. Making \(fixedDeclaration) `public` instead also needs a new name, if module `App` can then name another type called `Store`."
	}

	/// The error at an `internal` seam initializer a root mock would call, with its fix-it.
	private static func seamInitializerMockDiagnostics(atPath path: String, seam seamName: String, module moduleName: String) -> String {
		"""
		\(path):3:5: error: `\(seamName)`’s initializer is `internal`, so the mock of `Root`, generated in module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix, or give `\(seamName)` a public mock: `generateMock: .public`, or a hand-written public `mock`: mocks build a seam's tree inline, and this mock would call the mock `\(moduleName)` generates instead.
		\(path):3:5-3:5: fixit: public\u{20}
		"""
	}

	private static func store(_ access: String, named name: String = "Store") -> String {
		"""
		@Instantiable
		\(access) struct \(name): Instantiable {
		    \(access) init() {}
		}
		"""
	}

	/// A type a module keeps to itself whose initializer alone is `public`, so that a construction of it from another
	/// module fails only at the type.
	private static let storeWithPublicInitializer = """
	@Instantiable
	struct Store: Instantiable {
	    public init() {}
	}
	"""

	private static func storeReceivingDatabase(_ access: String) -> String {
		"""
		@Instantiable
		\(access) struct Store: Instantiable {
		    \(access) init(database: Database) { self.database = database }
		    @Received let database: Database
		}
		"""
	}

	/// `name`, an `internal` type, and the `@Instantiable` extension that declares it.
	private static func storeExtension(named name: String = "Store") -> String {
		"""
		struct \(name) {
		    init() {}
		}

		@Instantiable
		extension \(name): Instantiable {
		    static func instantiate() -> \(name) {
		        \(name)()
		    }
		}
		"""
	}

	private static func fulfiller(_ name: String, of protocolName: String, access: String = "internal", claim: String? = nil) -> String {
		"""
		@Instantiable(fulfillingAdditionalTypes: [\(claim ?? "\(protocolName).self")])
		\(access) struct \(name): \(protocolName), Instantiable {
		    \(access) init() {}
		}
		"""
	}

	/// A `public` type that is no seam and instantiates `Store`, so the tree that reaches it builds `Store` itself.
	private static func inlineParent(named name: String) -> String {
		"""
		@Instantiable
		public struct \(name): Instantiable {
		    init(store: Store) { self.store = store }
		    @Instantiated let store: Store
		}
		"""
	}

	/// A `public` seam that instantiates `holding`, and `andHolding` beside it.
	private static func seam(_ name: String, holding type: String = "Store", label: String = "store", andHolding other: String? = nil, attributes: String = "generateDependencyTree: true") -> String {
		let otherLabel = other.map { String($0.prefix { $0 != ":" }) }
		let parameters = [other, "\(label): \(type)"].compactMap(\.self).joined(separator: ", ")
		let assignments = [otherLabel.map { "        self.\($0) = \($0)" }, "        self.\(label) = \(label)"].compactMap(\.self).joined(separator: "\n")
		let otherProperty = other.map { "    @Instantiated let \($0)\n" } ?? ""
		return """
		@Instantiable(\(attributes))
		public final class \(name): Instantiable {
		    init(\(parameters)) {
		\(assignments)
		    }

		\(otherProperty)    @Instantiated let \(label): \(type)
		}
		"""
	}

	private static func internalSeam(named name: String) -> String {
		"""
		@Instantiable(generateDependencyTree: true)
		final class \(name): Instantiable {
		    init() {}
		}
		"""
	}

	private static func internalRoot(named name: String) -> String {
		"""
		@Instantiable(isRoot: true)
		struct \(name): Instantiable {
		    init() {}
		}
		"""
	}

	private static func mockOnlyDeclaration(of type: String) -> String {
		"""
		@Instantiable(mockOnly: true)
		extension \(type) {
		    static func mock() -> \(type) {
		        \(type)()
		    }
		}
		"""
	}

	/// A root at `access` in a file that imports `importing`, each property of `holding` on a line of its own.
	private static func root(holding properties: [String], importing moduleNames: [String], attributes: String = "isRoot: true", access: String = "public") -> String {
		let imports = moduleNames.map { "import \($0)\n" }.joined()
		let labels = properties.map { String($0.prefix { $0 != ":" }) }
		return """
		\(imports)
		@Instantiable(\(attributes))
		\(access) struct Root: Instantiable {
		    \(access) init(\(properties.joined(separator: ", "))) {
		\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
		    }

		\(properties.map { "    @Instantiated let \($0)" }.joined(separator: "\n"))
		}
		"""
	}

	private static func path(of fileName: String, in moduleName: String, fixtures: [String: FixturePaths], integration: MultiModuleIntegration) -> String {
		switch integration {
		case .moduleInfo:
			fixtures[moduleName]![fileName]
		case .swiftPackagePlugin:
			NormalizedFilePath(fixtures[moduleName]!.compilerPath(of: fileName)).path
		}
	}
}
