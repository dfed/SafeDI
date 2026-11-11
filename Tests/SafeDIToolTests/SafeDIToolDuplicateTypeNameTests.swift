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

/// SafeDI tells `@Instantiable` types apart by name across every module a run reads, so two unrelated types of one name
/// in two modules are an error whose remedy is to tell them apart. Keeping one is the only remedy offered for declarations
/// known to be in one module, which holds one type of a name.
struct SafeDIToolDuplicateTypeNameTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Types of one name in several modules

	@Test(arguments: MultiModuleIntegration.allCases, ["package", "public"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesBothModulesAndOffersRename_whenTwoModulesDeclareTypeOfOneName(integration: MultiModuleIntegration, accessLevel: String) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = "error: `Store` is declared in modules `App` and `Core`. SafeDI tells apart by name the @Instantiable types a module can name. Rename one."
			return """
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(message)
			\(Self.path(of: "Store.swift", in: "Core", fixtures: fixtures, integration: integration)):1:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: accessLevel)]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: accessLevel), "Root.swift": Self.root], dependencies: ["Core"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_listsThreeModulesAndAsksToRenameAllButOne_whenThreeModulesDeclareTypeOfOneName(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = "error: `Store` is declared in modules `App`, `Core`, and `Feature`. SafeDI tells apart by name the @Instantiable types a module can name. Rename all but one."
			return """
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(message)
			\(Self.path(of: "Store.swift", in: "Core", fixtures: fixtures, integration: integration)):1:1: \(message)
			\(Self.path(of: "Store.swift", in: "Feature", fixtures: fixtures, integration: integration)):1:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public")]),
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public")]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public"), "Root.swift": Self.root], dependencies: ["Feature", "Core"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_listsModulesInSortedOrder_whenTwentyFourModulesDeclareTypeOfOneName() async {
		// The names are listed neither sorted nor reversed, so an order taken from a set, from the order the modules were
		// read in, or from the order they are listed in fails on nearly every run.
		let moduleNames = (0..<24).map { index in
			"Module\(String(format: "%02d", (index * 7) % 24))"
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let sortedModuleNames = moduleNames.sorted()
			let leadingModules = sortedModuleNames.dropLast().map { "`\($0)`" }.joined(separator: ", ")
			let message = "error: `Store` is declared in modules \(leadingModules), and `\(sortedModuleNames[23])`. SafeDI tells apart by name the @Instantiable types a module can name. Rename all but one."
			return moduleNames
				.map { "\(fixtures[$0]!["Store.swift"]):1:1: \(message)" }
				.sorted()
				.joined(separator: "\n")
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: moduleNames.map { moduleName in
					ModuleFixture(name: moduleName, packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public")])
				} + [
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Root.swift": Self.root], dependencies: moduleNames),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersOneDeclarationAndRename_whenTwoModulesDeclareTypeOfOneNameInsidePlatformBlocks(integration: MultiModuleIntegration) async {
		// SafeDI cannot tell one type split by platform from two types that have nothing to do with each other, so the
		// message gives the remedy for each.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = "error: `Store` is declared in modules `App` and `Core`. SafeDI tells apart by name the @Instantiable types a module can name, and reads every clause of an `#if` that only the compiler decides, such as `#if os(iOS)`. If they are one type that differs by platform, declare it with one @Instantiable declaration, in one of these modules and outside the `#if`, and put the platform difference inside its body or its `instantiate(…)` method. If they are different types, rename one."
			return """
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):2:1: \(message)
			\(Self.path(of: "Store.swift", in: "Core", fixtures: fixtures, integration: integration)):2:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(inBlockOf: "os(iOS)")]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(inBlockOf: "!os(iOS)"), "Root.swift": Self.root], dependencies: ["Core"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – A module that declares a type more than once

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesRepeatingModuleAndAsksToDeclareOnceThenRename_whenOneOfTwoModulesDeclaresTypeInEachClause(integration: MultiModuleIntegration) async {
		// Renaming one of three declarations would leave two of one name.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = "error: `Store` is declared in modules `App` and `Core`, and more than once in `App`. SafeDI tells apart by name the @Instantiable types a module can name. Declare it once in `App`, with any platform difference inside its body or its `instantiate(…)` method, then rename one."
			return """
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):2:1: \(message)
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):7:1: \(message)
			\(Self.path(of: "Store.swift", in: "Core", fixtures: fixtures, integration: integration)):1:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public")]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.storeInEachClause, "Root.swift": Self.root], dependencies: ["Core"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersOneDeclarationOrDeclaringOnceThenRename_whenRepeatingDeclarationsAreAllInsidePlatformBlocks(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = "error: `Store` is declared in modules `App` and `Core`, and more than once in `App`. SafeDI tells apart by name the @Instantiable types a module can name, and reads every clause of an `#if` that only the compiler decides, such as `#if os(iOS)`. If they are one type that differs by platform, declare it with one @Instantiable declaration, in one of these modules and outside the `#if`, and put the platform difference inside its body or its `instantiate(…)` method. If they are different types, declare it once in `App`, with any platform difference inside its body or its `instantiate(…)` method, then rename one."
			return """
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):2:1: \(message)
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):7:1: \(message)
			\(Self.path(of: "Store.swift", in: "Core", fixtures: fixtures, integration: integration)):2:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(inBlockOf: "os(iOS)")]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.storeInEachClause, "Root.swift": Self.root], dependencies: ["Core"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – Types whose modules are not all known

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersRenameAndKeepingOne_whenNoModuleNameIsKnown() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Store.swift"]):1:1: \(Self.unknownModulesMessage(for: "Store", rename: "rename one"))
				\(fixtures["Store_2.swift"]):1:1: \(Self.unknownModulesMessage(for: "Store", rename: "rename one"))
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.store(accessLevel: "public"), Self.store(accessLevel: "public")],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_asksToRenameAllButOneOrKeepOne_whenNoModuleNameIsKnownAndThreeFilesDeclareType() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				let message = Self.unknownModulesMessage(for: "Store", rename: "rename all but one")
				return """
				\(fixtures["Store.swift"]):1:1: \(message)
				\(fixtures["Store_2.swift"]):1:1: \(message)
				\(fixtures["Store_3.swift"]):1:1: \(message)
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.store(accessLevel: "public"), Self.store(accessLevel: "public"), Self.store(accessLevel: "public")],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersRenameAndKeepingOne_whenOnlyOneOfTwoModulesHasAKnownName() async {
		// A hand-written `generate` call can read `.safedi` files without being given `--module-name`, so it knows the
		// modules of the module info it reads, and cannot say which module declares a type in its own files.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Store.swift"]):1:1: \(Self.unknownModulesMessage(for: "Store", rename: "rename one"))
			\(fixtures["Core"]!["Store.swift"]):1:1: \(Self.unknownModulesMessage(for: "Store", rename: "rename one"))
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public")]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public"), "Root.swift": Self.root], dependencies: ["Core"], omitsModuleName: true),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersRenameAndKeepingOne_whenOneDeclarationIsReadThroughAdditionalDirectory(integration: MultiModuleIntegration) async {
		// The run knows its own module, but not the module of a file `additionalDirectoriesToInclude` finds.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = Self.unknownModulesMessage(for: "Store", rename: "rename one")
			return """
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(message)
			\(NormalizedFilePath(fixtures["Vendor"]!["Store.swift"]).path):1:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Vendor", packageName: "Vendor", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public")], isCheckoutPackage: true, runsSafeDI: false),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: [
						"SafeDIConfiguration.swift": "#SafeDIConfiguration(additionalDirectoriesToInclude: [\"$FIXTURE_ROOT/checkouts/Vendor/Sources/Vendor\"])",
						"Store.swift": Self.store(accessLevel: "public"),
						"Root.swift": Self.root,
					], dependencies: ["Vendor"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersRenameAndKeepingOne_whenClaimIsBesideTypeOfOneNameReadThroughAdditionalDirectory(integration: MultiModuleIntegration) async {
		// `App`'s protocol and `Vendor`'s type have nothing to do with each other, and renaming the protocol resolves the error.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = Self.claimsMessage(modules: nil, rename: "rename one")
			return """
			\(Self.path(of: "Replacement.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(message)
			\(NormalizedFilePath(fixtures["Vendor"]!["Store.swift"]).path):1:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Vendor", packageName: "Vendor", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public")], isCheckoutPackage: true, runsSafeDI: false),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: [
						"SafeDIConfiguration.swift": "#SafeDIConfiguration(additionalDirectoriesToInclude: [\"$FIXTURE_ROOT/checkouts/Vendor/Sources/Vendor\"])",
						"StoreProtocol.swift": "public protocol Store {}",
						"Replacement.swift": Self.replacementClaimingStore,
						"Root.swift": Self.root,
					], dependencies: ["Vendor"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersRenameAndKeepingOne_whenExtensionIsBesideTypeOfOneNameAndNoModuleNameIsKnown() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				let message = Self.claimsMessage(modules: nil, rename: "rename one")
				return """
				\(fixtures["Store+Instantiable.swift"]):1:1: \(message)
				\(fixtures["Store.swift"]):1:1: \(message)
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [],
				swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public"), "Store+Instantiable.swift": Self.storeExtension],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – One declaration that fulfills a type twice

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_asksToRemoveRepeat_whenDeclarationClaimsItsOwnTypeAndNoModuleNameIsKnown() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"\(fixtures["Store.swift"]):1:1: \(Self.repeatedClaimMessage(for: "Store"))"
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [],
				swiftFileContentByFilePath: ["Store.swift": Self.storeClaimingItself],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_asksToRemoveRepeat_whenDeclarationClaimsItsOwnTypeInKnownModule(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(Self.repeatedClaimMessage(for: "Store"))"
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.storeClaimingItself, "Root.swift": Self.root]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_asksToRemoveRepeat_whenDeclarationClaimsOneProtocolTwice() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"\(fixtures["Store.swift"]):1:1: \(Self.repeatedClaimMessage(for: "Storing"))"
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [],
				swiftFileContentByFilePath: [
					"Store.swift": """
					@Instantiable(fulfillingAdditionalTypes: [Storing.self, Storing.self])
					public struct Store: Instantiable, Storing {
					    public init() {}
					}
					""",
					"Storing.swift": "public protocol Storing {}",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – Declarations in one module

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsMessageOfDuplicateType_whenOneModuleDeclaresTypeTwice(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateMessage(for: "Store"))
			\(Self.path(of: "StoreAgain.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateMessage(for: "Store"))
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public"), "StoreAgain.swift": Self.store(accessLevel: "public"), "Root.swift": Self.root]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsMessageOfDuplicateType_whenOneModuleDeclaresTypeAndExtendsIt(integration: MultiModuleIntegration) async {
		// One module holds one type of a name, so the extension is of that type.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Store+Instantiable.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateMessage(for: "Store"))
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(Self.duplicateMessage(for: "Store"))
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public"), "Store+Instantiable.swift": Self.storeExtension, "Root.swift": Self.root]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersOneDeclarationAndKeepingOne_whenOneModuleDeclaresTypeInEachClauseOfPlatformBlock(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = "error: Found multiple @Instantiable types or extensions that fulfill `Store`. Each is declared inside an `#if` that only the compiler decides, such as `#if os(iOS)`, and SafeDI reads every clause. If no build compiles more than one of them, fulfill `Store` with one @Instantiable declaration outside the `#if`, and put the platform difference inside its body or its `instantiate(…)` method. Otherwise, keep one, and remove `Store` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable."
			return """
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):2:1: \(message)
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):7:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.storeInEachClause, "Root.swift": Self.root]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – Extensions and claims of one name in several modules

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersRenameAndKeepingOne_whenTwoModulesClaimTheirOwnProtocolsOfOneName(integration: MultiModuleIntegration) async {
		// Each module builds alone, and SafeDI cannot tell one `Storing` from two.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = Self.claimsMessage(modules: "`App` and `Core`", rename: "rename one", for: "Storing")
			return """
			\(Self.path(of: "Fulfiller.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(message)
			\(Self.path(of: "Fulfiller.swift", in: "Core", fixtures: fixtures, integration: integration)):1:1: \(message)
			"""
		}) {
			func fulfiller(named name: String) -> String {
				"""
				@Instantiable(fulfillingAdditionalTypes: [Storing.self])
				public struct \(name): Instantiable, Storing {
				    public init() {}
				}
				"""
			}
			return try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Storing.swift": "public protocol Storing {}", "Fulfiller.swift": fulfiller(named: "DiskStore")]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Storing.swift": "public protocol Storing {}", "Fulfiller.swift": fulfiller(named: "MemoryStore"), "Root.swift": Self.root], dependencies: ["Core"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersRenameAndKeepingOne_whenTwoModulesExtendTheirOwnTypesOfOneName(integration: MultiModuleIntegration) async {
		// Each module builds alone, and renaming one module's type and its extension resolves the error.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = Self.claimsMessage(modules: "`App` and `Core`", rename: "rename one")
			return """
			\(Self.path(of: "Store+Instantiable.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(message)
			\(Self.path(of: "Store+Instantiable.swift", in: "Core", fixtures: fixtures, integration: integration)):1:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.plainStore, "Store+Instantiable.swift": Self.storeExtension]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.plainStore, "Store+Instantiable.swift": Self.storeExtension, "Root.swift": Self.root], dependencies: ["Core"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersRenameAndKeepingOne_whenOneModuleExtendsTypeOfOneNameAndAnotherClaimsIt(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = Self.claimsMessage(modules: "`App` and `Core`", rename: "rename one")
			return """
			\(Self.path(of: "Replacement.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(message)
			\(Self.path(of: "Store+Instantiable.swift", in: "Core", fixtures: fixtures, integration: integration)):1:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store+Instantiable.swift": Self.storeExtension]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Replacement.swift": Self.replacementClaimingStore, "Root.swift": Self.root], dependencies: ["Core"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – A type of one name beside an extension or a claim

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersRenameAndKeepingOne_whenOneModuleDeclaresTypeAndAnotherExtendsTypeOfOneName(integration: MultiModuleIntegration) async {
		// `App` may be extending `Core`'s `Store`, or a `Store` of its own that has nothing to do with it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = Self.claimsMessage(modules: "`App` and `Core`", rename: "rename one")
			return """
			\(Self.path(of: "Store+Instantiable.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(message)
			\(Self.path(of: "Store.swift", in: "Core", fixtures: fixtures, integration: integration)):1:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public")]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store+Instantiable.swift": Self.storeExtension, "Root.swift": Self.root], dependencies: ["Core"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersRenameAndKeepingOne_whenOneModuleDeclaresTypeAndAnotherClaimsTypeOfOneName(integration: MultiModuleIntegration) async {
		// `Replacement` may be claiming `Core`'s `Store`, or a `Store` of `App`'s own that has nothing to do with it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = Self.claimsMessage(modules: "`App` and `Core`", rename: "rename one")
			return """
			\(Self.path(of: "Replacement.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(message)
			\(Self.path(of: "Store.swift", in: "Core", fixtures: fixtures, integration: integration)):1:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public")]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Replacement.swift": Self.replacementClaimingStore, "Root.swift": Self.root], dependencies: ["Core"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesRepeatingModuleAndAsksToFulfillOnceThenRename_whenOneModuleDeclaresAndClaimsTypeBesideDeclarationInAnother(integration: MultiModuleIntegration) async {
		// `App` fails on its own pair whichever type is renamed.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = Self.claimsMessage(modules: "`App` and `Core`, and more than once in `App`", rename: "\(Self.fulfillOnceInApp), then rename one")
			return """
			\(Self.path(of: "Replacement.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(message)
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(message)
			\(Self.path(of: "Store.swift", in: "Core", fixtures: fixtures, integration: integration)):1:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public")]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public"), "Replacement.swift": Self.replacementClaimingStore, "Root.swift": Self.root], dependencies: ["Core"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesRepeatingModuleAndAsksToFulfillOnceThenRename_whenOneModuleDeclaresTypeInEachClauseBesideExtensionInAnother(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = Self.claimsMessage(modules: "`App` and `Core`, and more than once in `App`", rename: "\(Self.fulfillOnceInApp), then rename one")
			return """
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):2:1: \(message)
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):7:1: \(message)
			\(Self.path(of: "Store+Instantiable.swift", in: "Core", fixtures: fixtures, integration: integration)):1:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.plainStore, "Store+Instantiable.swift": Self.storeExtension]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.storeInEachClause, "Root.swift": Self.root], dependencies: ["Core"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersOneDeclarationOrFulfillingOnceThenRename_whenRepeatingDeclarationsAndExtensionAreAllInsidePlatformBlocks(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = "error: Found multiple @Instantiable types or extensions that fulfill `Store`, in modules `App` and `Core`, and more than once in `App`. Each is declared inside an `#if` that only the compiler decides, such as `#if os(iOS)`, and SafeDI reads every clause. If `Store` names one type that differs by platform, fulfill `Store` with one @Instantiable declaration outside the `#if`, and put the platform difference inside its body or its `instantiate(…)` method. If it names different types, \(Self.fulfillOnceInApp), then rename one. Otherwise, keep one, and remove `Store` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable."
			return """
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):2:1: \(message)
			\(Self.path(of: "Store.swift", in: "App", fixtures: fixtures, integration: integration)):7:1: \(message)
			\(Self.path(of: "Store+Instantiable.swift", in: "Core", fixtures: fixtures, integration: integration)):2:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store+Instantiable.swift": "#if os(iOS)\n\(Self.storeExtension)\n#endif"]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.storeInEachClause, "Root.swift": Self.root], dependencies: ["Core"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_asksToRenameAllButOneOrKeepOne_whenTwoModulesDeclareTypeBesideExtensionInAThird(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = Self.claimsMessage(modules: "`App`, `Core`, and `Feature`", rename: "rename all but one")
			return """
			\(Self.path(of: "Store+Instantiable.swift", in: "App", fixtures: fixtures, integration: integration)):1:1: \(message)
			\(Self.path(of: "Store.swift", in: "Core", fixtures: fixtures, integration: integration)):1:1: \(message)
			\(Self.path(of: "Store.swift", in: "Feature", fixtures: fixtures, integration: integration)):1:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public")]),
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(accessLevel: "public")]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store+Instantiable.swift": Self.storeExtension, "Root.swift": Self.root], dependencies: ["Feature", "Core"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersOneDeclarationRenameAndKeepingOne_whenTypeAndExtensionInTwoModulesAreInsidePlatformBlocks(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let message = "error: Found multiple @Instantiable types or extensions that fulfill `Store`, in modules `App` and `Core`. Each is declared inside an `#if` that only the compiler decides, such as `#if os(iOS)`, and SafeDI reads every clause. If `Store` names one type that differs by platform, fulfill `Store` with one @Instantiable declaration outside the `#if`, and put the platform difference inside its body or its `instantiate(…)` method. If it names different types, rename one. Otherwise, keep one, and remove `Store` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable."
			return """
			\(Self.path(of: "Store+Instantiable.swift", in: "App", fixtures: fixtures, integration: integration)):2:1: \(message)
			\(Self.path(of: "Store.swift", in: "Core", fixtures: fixtures, integration: integration)):2:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": Self.store(inBlockOf: "os(iOS)")]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Store+Instantiable.swift": "#if !os(iOS)\n\(Self.storeExtension)\n#endif", "Root.swift": Self.root], dependencies: ["Core"]),
				],
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_listsModulesInSortedOrder_whenTwentyThreeModulesExtendTypeOfOneNameAnotherDeclares() async {
		// The names are listed neither sorted nor reversed, so an order taken from a set, from the order the modules were
		// read in, or from the order they are listed in fails on nearly every run.
		let moduleNames = (0..<24).map { index in
			"Module\(String(format: "%02d", (index * 7) % 24))"
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let sortedModuleNames = moduleNames.sorted()
			let leadingModules = sortedModuleNames.dropLast().map { "`\($0)`" }.joined(separator: ", ")
			let message = Self.claimsMessage(modules: "\(leadingModules), and `\(sortedModuleNames[23])`", rename: "rename all but one")
			return moduleNames
				.map { "\(fixtures[$0]!["Store.swift"]):1:1: \(message)" }
				.sorted()
				.joined(separator: "\n")
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: moduleNames.enumerated().map { index, moduleName in
					ModuleFixture(name: moduleName, packageName: "Shop", swiftFileContentByFilePath: ["Store.swift": index == 0 ? Self.store(accessLevel: "public") : Self.storeExtension])
				} + [
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Root.swift": Self.root], dependencies: moduleNames),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let root = """
	@Instantiable(isRoot: true)
	public struct Root: Instantiable {
	    public init() {}
	}
	"""

	private static let plainStore = """
	public struct Store {
	    public init() {}
	}
	"""

	private static let storeClaimingItself = """
	@Instantiable(fulfillingAdditionalTypes: [Store.self])
	public struct Store: Instantiable {
	    public init() {}
	}
	"""

	private static let fulfillOnceInApp = "fulfill it once in `App`, with any platform difference inside its body or its `instantiate(…)` method"

	private static let storeExtension = """
	@Instantiable
	extension Store: Instantiable {
	    public static func instantiate() -> Store {
	        Store()
	    }
	}
	"""

	private static let replacementClaimingStore = """
	@Instantiable(fulfillingAdditionalTypes: [Store.self])
	public struct Replacement: Instantiable {
	    public init() {}
	}
	"""

	private static var storeInEachClause: String {
		"""
		#if os(iOS)
		\(store(accessLevel: "public"))
		#else
		\(store(accessLevel: "public"))
		#endif
		"""
	}

	private static func store(accessLevel: String) -> String {
		"""
		@Instantiable
		\(accessLevel) struct Store: Instantiable {
		    \(accessLevel) init() {}
		}
		"""
	}

	private static func store(inBlockOf condition: String) -> String {
		"#if \(condition)\n\(store(accessLevel: "public"))\n#endif"
	}

	private static func unknownModulesMessage(for typeName: String, rename: String) -> String {
		"error: Found multiple @Instantiable types or extensions that fulfill `\(typeName)`. Each type can be fulfilled by only one @Instantiable declaration, across all modules. If they are different types, \(rename). If they are one type, keep one, and remove the others’ @Instantiable."
	}

	private static func duplicateMessage(for typeName: String) -> String {
		"error: Found multiple @Instantiable types or extensions that fulfill `\(typeName)`. Each type can be fulfilled by only one @Instantiable declaration, across all modules. Keep one, and remove `\(typeName)` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable."
	}

	private static func claimsMessage(modules: String?, rename: String, for typeName: String = "Store") -> String {
		"error: Found multiple @Instantiable types or extensions that fulfill `\(typeName)`\(modules.map { ", in modules \($0)" } ?? ""). Each type can be fulfilled by only one @Instantiable declaration\(modules == nil ? ", across all modules" : " a module can name"). If `\(typeName)` names different types, \(rename). If it names one type, keep one, and remove `\(typeName)` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable."
	}

	private static func repeatedClaimMessage(for typeName: String) -> String {
		"error: `fulfillingAdditionalTypes` repeats `\(typeName)`, which this @Instantiable declaration already fulfills. Remove the repeat."
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
