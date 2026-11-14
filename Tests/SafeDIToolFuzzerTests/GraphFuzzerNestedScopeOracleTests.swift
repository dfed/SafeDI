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
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The graph fuzzer's oracles of a hole's scope nested by type: the facts of the places a seam's tree builds, read by
/// type (`GraphFuzzerPlaceFacts`), and the scope enums the generator nests by type (`GraphFuzzerScopeDeclarations`),
/// against which they are judged in every graph whose scopes the generator nests by type
/// (`GraphFuzzerToolRuns.nestsEveryScopeByType`).
struct GraphFuzzerNestedScopeOracleTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests of the places' facts

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func placeFacts_produceOneCasePerPropertyOfEachType_whenTwoScreensShareATypeThatHoldsAPlace() async throws {
		let facts = try await placeFacts(of: Self.sharedTypeFiles(screenBDeclarations: ["@Instantiated let service: any Service", "@Instantiated let shared: Shared"]))

		// `Shared` is built on two paths and produces its one case on both; `ScreenB`'s level before `shared` holds its own
		// place, which it binds first, and `Home`'s before `screenB` holds `screenA`.
		#expect(facts.producedCases.sorted() == [
			Self.producedCase(of: "Home", isSeamRoot: true, "screenA"),
			Self.producedCase(of: "Home", isSeamRoot: true, "screenB"),
			Self.producedCase(of: "ScreenA", "shared"),
			Self.producedCase(of: "ScreenB", "service"),
			Self.producedCase(of: "ScreenB", "shared"),
			Self.producedCase(of: "Shared", "service"),
		])
		#expect(facts.levelFields == [
			Self.levelKey(of: "Home", isSeamRoot: true, "screenA: ScreenA"): [],
			Self.levelKey(of: "Home", isSeamRoot: true, "screenB: ScreenB"): ["screenA: ScreenA"],
			Self.levelKey(of: "ScreenA", "shared: Shared"): [],
			Self.levelKey(of: "ScreenB", "service: any Service"): [],
			Self.levelKey(of: "ScreenB", "shared: Shared"): ["service: any Service"],
			Self.levelKey(of: "Shared", "service: any Service"): [],
		])
		#expect(facts.chainRepeats == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func placeFacts_repeatNoDeclarationOnAnyPath_whenTwoInstantiatorsCloseEachOthersCycle() async throws {
		let facts = try await placeFacts(of: [
			"public protocol Api {}",
			seamFixtureType(named: "Mark", isFinalClass: true, declarations: []),
			seamFixtureType(named: "T", isFinalClass: true, declarations: ["@Instantiated let cBuilder: Instantiator<C>", "@Instantiated let api: any Api"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let mark: Mark", "@Instantiated let tBuilder: Instantiator<T>"]),
			seamFixtureType(named: "Hub", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let tBuilder: Instantiator<T>", "@Instantiated let cBuilder: Instantiator<C>"]),
		])

		// Each path stops where its declaration is already being built above: `tBuilder.cBuilder` closes on `tBuilder`, and
		// `cBuilder.tBuilder.cBuilder` on `cBuilder`, so the two places' paths repeat nothing.
		#expect(facts.chainRepeats == [])
		// `T`'s `cBuilder` reaches a place only through `T` itself, so no path produces its case: a tangle of cycles no type
		// always encloses keeps a case no run produces, which the design accepts.
		#expect(facts.producedCases.sorted() == [
			Self.producedCase(of: "C", inTreeOf: "Hub", "tBuilder"),
			Self.producedCase(of: "Hub", inTreeOf: "Hub", isSeamRoot: true, "cBuilder"),
			Self.producedCase(of: "Hub", inTreeOf: "Hub", isSeamRoot: true, "tBuilder"),
			Self.producedCase(of: "T", inTreeOf: "Hub", "api"),
		])
		// `T` binds its `cBuilder` before `api` on both paths, the one where it closes the cycle included.
		#expect(facts.levelFields[Self.levelKey(of: "T", inTreeOf: "Hub", "api: any Api")] == ["cBuilder: Instantiator<C>"])
		#expect(facts.levelFields[Self.levelKey(of: "C", inTreeOf: "Hub", "tBuilder: Instantiator<T>")] == ["mark: Mark"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func secondPathLevelChanges_isEmpty_whenTheSecondPathIsTheLastPropertyOfATypeThatHoldsAPlace() async throws {
		let facts = try await placeFacts(of: Self.sharedTypeFiles(screenBDeclarations: ["@Instantiated let service: any Service", "@Instantiated let shared: Shared"]))
		let factsWithoutPath = try await placeFacts(of: Self.sharedTypeFiles(screenBDeclarations: ["@Instantiated let service: any Service"]))

		#expect(facts.secondPathLevelChanges(comparedWith: factsWithoutPath, typeName: "ScreenB", label: "shared") == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func secondPathLevelChanges_reportsLevel_whenTheSecondPathIsBoundBeforeAPlaceOfItsType() async throws {
		let facts = try await placeFacts(of: Self.sharedTypeFiles(screenBDeclarations: ["@Instantiated let shared: Shared", "@Instantiated let service: any Service"]))
		let factsWithoutPath = try await placeFacts(of: Self.sharedTypeFiles(screenBDeclarations: ["@Instantiated let service: any Service"]))

		// `ScreenB` binds `shared` before its own place, whose level gains the field.
		#expect(facts.secondPathLevelChanges(comparedWith: factsWithoutPath, typeName: "ScreenB", label: "shared") == [
			"The level of `ScreenB` before `service: any Service` holds [] without the second path and [shared: Shared] with it.",
		])
	}

	@Test
	func placeChainFailure_reportsEachRepeat_whenAPlacesPathRepeatsADeclaration() {
		let fixture = GraphFuzzerFixture(seed: 8, swiftFileContent: ["// module: FuzzFeature\n"])
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: [:], warnings: [])
		let chainRepeat = "The place `tBuilder.cBuilder.tBuilder.api` of `Hub` repeats the declaration `tBuilder: Instantiator<T>` building `T` on its path."

		let runs = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome, placeFacts: GraphFuzzerPlaceFacts(chainRepeats: [chainRepeat]))

		#expect(runs.placeChainFailure?.kind == .placeChainRepeatsDeclaration)
		#expect(runs.placeChainFailure?.details.prefix { $0 != "\n" } == Substring(chainRepeat))
	}

	@Test
	func secondPathFailure_reportsLevelChange_whenTheGraphWithoutItsSecondPathBindsOtherValues() {
		let fixture = GraphFuzzerFixture(seed: 8, swiftFileContent: ["// module: FuzzFeature\n"])
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: [:], warnings: [])
		let key = Self.levelKey(of: "ScreenB", "service: any Service")
		let withoutSecondPath = GraphFuzzerSecondPathRun(typeName: "ScreenB", label: "shared", outcome: outcome, placeFacts: GraphFuzzerPlaceFacts(levelFields: [key: []]))

		let runs = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome, placeFacts: GraphFuzzerPlaceFacts(levelFields: [key: ["shared: Shared"]]), withoutSecondPath: withoutSecondPath)

		#expect(runs.secondPathFailure?.kind == .secondPathChangesScope)
		#expect(runs.secondPathFailure?.details.split(separator: "\n").prefix(2) == [
			"The second path `ScreenB.shared`:",
			"The level of `ScreenB` before `service: any Service` holds [] without the second path and [shared: Shared] with it.",
		])
	}

	// MARK: Tests of the scope enums

	@Test
	func scopeDeclarations_readEveryNestedEnumCaseAndField_whenTheGeneratedFileNestsByType() {
		let declarations = GraphFuzzerScopeDeclarations(generatedFiles: ["Home+SafeDI.swift": Self.nestedHomeScope(screenBHoldsShared: true)])

		#expect(declarations.entries == [
			"enum Home.SafeDIScope_Service",
			"case Home.SafeDIScope_Service.screenA(screenA_Values, SafeDIScope_Service.ScreenA_Scope)",
			"case Home.SafeDIScope_Service.screenB(screenB_Values, SafeDIScope_Service.ScreenB_Scope)",
			"case Home.SafeDIScope_Service.inner(inner_Values, Inner.SafeDIScope_Service)",
			"struct Home.SafeDIScope_Service.screenA_Values",
			"struct Home.SafeDIScope_Service.screenB_Values",
			"field Home.SafeDIScope_Service.screenB_Values: public screenA: ScreenA",
			"struct Home.SafeDIScope_Service.inner_Values",
			"enum Home.SafeDIScope_Service.ScreenA_Scope",
			"case Home.SafeDIScope_Service.ScreenA_Scope.shared(shared_Values, SafeDIScope_Service.Shared_Scope)",
			"struct Home.SafeDIScope_Service.ScreenA_Scope.shared_Values",
			"enum Home.SafeDIScope_Service.ScreenB_Scope",
			"case Home.SafeDIScope_Service.ScreenB_Scope.service(service_Values)",
			"case Home.SafeDIScope_Service.ScreenB_Scope.shared(shared_Values, SafeDIScope_Service.Shared_Scope)",
			"struct Home.SafeDIScope_Service.ScreenB_Scope.service_Values",
			"struct Home.SafeDIScope_Service.ScreenB_Scope.shared_Values",
			"field Home.SafeDIScope_Service.ScreenB_Scope.shared_Values: internal service: any Service",
			"enum Home.SafeDIScope_Service.Shared_Scope",
			"case Home.SafeDIScope_Service.Shared_Scope.service(service_Values)",
			"struct Home.SafeDIScope_Service.Shared_Scope.service_Values",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func scopeDeclarations_readBothFamiliesAndAgreeWithTheFacts_whenThePlainRootIsANamespaceOfTheToolsOutput() async throws {
		// `Shell` builds `Panel` in a `@Sendable` function, and `Panel` holds the place: the tool's plain root enum declares no
		// case, only `Panel`'s enum, which the `@Sendable` enum's case holds.
		var filesToDelete = filesToDelete
		let (output, facts) = try await collectingPlaceFacts {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"public protocol Widget {}",
					seamFixtureType(named: "Panel", declarations: ["@Forwarded public let name: String", "@Instantiated public let widget: any Widget"]),
					seamFixtureType(named: "Shell", declarations: ["@Instantiated public let panelBuilder: SendableInstantiator<Panel>"]),
					seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated public let shell: Shell"]),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				moduleMembershipArguments: ["--module-name", "Feature"],
			)
		}
		self.filesToDelete = filesToDelete
		let declarations = try GraphFuzzerScopeDeclarations(generatedFiles: #require(output.generatedFiles))

		#expect(declarations.entries == [
			"enum Host.SafeDIScope_Widget",
			"enum Host.SafeDIScope_Widget.Panel_Scope",
			"case Host.SafeDIScope_Widget.Panel_Scope.widget(widget_Values)",
			"struct Host.SafeDIScope_Widget.Panel_Scope.widget_Values",
			"field Host.SafeDIScope_Widget.Panel_Scope.widget_Values: public name: String",
			"enum Host.SafeDISendableScope_Widget",
			"case Host.SafeDISendableScope_Widget.shell_Sendable(SafeDISendableScope_Widget.Shell_Scope)",
			"enum Host.SafeDISendableScope_Widget.Shell_Scope",
			"case Host.SafeDISendableScope_Widget.Shell_Scope.panelBuilder(SafeDIScope_Widget.Panel_Scope)",
		])
		#expect(declarations.undeclaredProducedCases(of: facts) == [])
		#expect(declarations.unproducedDeclaredCases(of: facts) == [])
		#expect(declarations.casesNamingNoPropertyOfTheirType(of: facts) == [])
	}

	@Test
	func secondPathChanges_isEmpty_whenOnlyTheSecondPathsOwnCaseIsAdded() {
		let declarations = GraphFuzzerScopeDeclarations(generatedFiles: ["Home+SafeDI.swift": Self.nestedHomeScope(screenBHoldsShared: true)])
		let declarationsWithoutPath = GraphFuzzerScopeDeclarations(generatedFiles: ["Home+SafeDI.swift": Self.nestedHomeScope(screenBHoldsShared: false)])

		#expect(declarations.secondPathChanges(comparedWith: declarationsWithoutPath, typeName: "ScreenB", label: "shared") == [])
	}

	@Test
	func secondPathChanges_reportsEachCaseAndStruct_whenTheScopeHasOneCasePerPath() {
		// An enum with a case per path, as 2.2.0 generates, adds a case for each new path to the shared type's place.
		let declarations = GraphFuzzerScopeDeclarations(generatedFiles: ["Home+SafeDI.swift": Self.flatHomeScope(screenBHoldsShared: true)])
		let declarationsWithoutPath = GraphFuzzerScopeDeclarations(generatedFiles: ["Home+SafeDI.swift": Self.flatHomeScope(screenBHoldsShared: false)])

		#expect(declarations.secondPathChanges(comparedWith: declarationsWithoutPath, typeName: "ScreenB", label: "shared") == [
			"The second path adds `case Home.SafeDIScope_Service.screenB_shared_service(screenB_shared_service_Values)`.",
			"The second path adds `struct Home.SafeDIScope_Service.screenB_shared_service_Values`.",
		])
	}

	@Test
	func undeclaredProducedCases_isEmpty_whenEveryProducedCaseIsDeclaredInItsTypesEnum() {
		let declarations = GraphFuzzerScopeDeclarations(generatedFiles: ["Home+SafeDI.swift": Self.nestedHomeScope(screenBHoldsShared: true)])

		#expect(declarations.undeclaredProducedCases(of: Self.sharedTypeFacts) == [])
	}

	@Test
	func undeclaredProducedCases_reportsCase_whenTheTypesEnumLacksIt() {
		let declarations = GraphFuzzerScopeDeclarations(generatedFiles: ["Home+SafeDI.swift": Self.nestedHomeScope(screenBHoldsShared: false)])

		#expect(declarations.undeclaredProducedCases(of: Self.sharedTypeFacts) == [
			"A place's path produces the case `shared` of `ScreenB` in the tree of `Home`, which no scope enum declares.",
		])
	}

	@Test
	func unproducedDeclaredCases_isEmpty_whenEveryCaseOfItsOwnIsProduced() {
		// `inner` wraps another seam's enum, whose places the facts do not hold.
		let declarations = GraphFuzzerScopeDeclarations(generatedFiles: ["Home+SafeDI.swift": Self.nestedHomeScope(screenBHoldsShared: true)])

		#expect(declarations.unproducedDeclaredCases(of: Self.sharedTypeFacts) == [])
	}

	@Test
	func unproducedDeclaredCases_reportsEachEnumAndCase_whenNoPathProducesThemOrNoCaseHoldsThem() {
		let generatedFile = Self.nestedHomeScope(screenBHoldsShared: true)
			.replacingOccurrences(of: "            case service(service_Values)\n\n            public struct service_Values {}\n        }\n    }", with: "            case service(service_Values)\n            case extra(extra_Values)\n\n            public struct service_Values {}\n\n            public struct extra_Values {}\n        }\n\n        @frozen public enum Ghost_Scope {\n            case service(service_Values)\n\n            public struct service_Values {}\n        }\n\n        @frozen public enum Phantom_Scope {\n            case service(service_Values)\n\n            public struct service_Values {}\n        }\n    }")
			.replacingOccurrences(of: "        case inner(inner_Values, Inner.SafeDIScope_Service)\n", with: "        case inner(inner_Values, Inner.SafeDIScope_Service)\n        case phantom(phantom_Values, SafeDIScope_Service.Phantom_Scope)\n")
		let declarations = GraphFuzzerScopeDeclarations(generatedFiles: ["Home+SafeDI.swift": generatedFile])

		// `Ghost_Scope` is held by no case; `Phantom_Scope`, held by `phantom`, describes no type a path builds.
		#expect(declarations.unproducedDeclaredCases(of: Self.sharedTypeFacts) == [
			"`Home.SafeDIScope_Service` declares the case `phantom`, which no place's path produces.",
			"`Home.SafeDIScope_Service.Shared_Scope` declares the case `extra`, which no place's path produces.",
			"No case holds `Home.SafeDIScope_Service.Ghost_Scope`.",
			"`Home.SafeDIScope_Service.Phantom_Scope` is the scope enum of no type a place's path builds.",
		])
	}

	@Test
	func unproducedDeclaredCases_judgesNoEnumOfAFillsTree_whenOnlyAPlaceInsideAFillReachesIt() {
		// `Home`'s fill of `Inner`'s hole builds `DefaultGadget`, whose own place of `Service` is a case of `Home`'s enum
		// holding `Inner`'s enum: the fill's tree has no levels, so its type's enum is not judged.
		let generatedFile = Self.nestedHomeScope(screenBHoldsShared: true)
			.replacingOccurrences(of: "        case inner(inner_Values, Inner.SafeDIScope_Service)\n", with: "        case inner(inner_Values, Inner.SafeDIScope_Service)\n        case inner_gadgetBuilder(inner_gadgetBuilder_Values, Inner.SafeDIScope_Gadget, SafeDIScope_Service.DefaultGadget_Scope)\n")
			.replacingOccurrences(of: "        @frozen public enum Shared_Scope {", with: "        @frozen public enum DefaultGadget_Scope {\n            case service(service_Values)\n\n            public struct service_Values {}\n        }\n\n        @frozen public enum Shared_Scope {")
		let declarations = GraphFuzzerScopeDeclarations(generatedFiles: ["Home+SafeDI.swift": generatedFile])

		#expect(declarations.enums.map(\.qualifiedName).contains("Home.SafeDIScope_Service.DefaultGadget_Scope"))
		#expect(declarations.unproducedDeclaredCases(of: Self.sharedTypeFacts) == [])
		#expect(declarations.casesNamingNoPropertyOfTheirType(of: Self.sharedTypeFacts) == [])
	}

	@Test
	func casesNamingNoPropertyOfTheirType_isEmpty_whenEachCaseNamesAPropertyOfItsType() {
		let declarations = GraphFuzzerScopeDeclarations(generatedFiles: ["Home+SafeDI.swift": Self.nestedHomeScope(screenBHoldsShared: true)])

		#expect(declarations.casesNamingNoPropertyOfTheirType(of: Self.sharedTypeFacts) == [])
	}

	@Test
	func casesNamingNoPropertyOfTheirType_reportsEachCase_whenTheScopeHasOneCasePerPath() {
		let declarations = GraphFuzzerScopeDeclarations(generatedFiles: ["Home+SafeDI.swift": Self.flatHomeScope(screenBHoldsShared: true)])

		#expect(declarations.casesNamingNoPropertyOfTheirType(of: Self.sharedTypeFacts) == [
			"`Home.SafeDIScope_Service` declares the case `screenA_shared_service`, which names no property of the seam `Home`.",
			"`Home.SafeDIScope_Service` declares the case `screenB_service`, which names no property of the seam `Home`.",
			"`Home.SafeDIScope_Service` declares the case `screenB_shared_service`, which names no property of the seam `Home`.",
		])
	}

	// MARK: Tests of the draws

	@Test
	func fixtureWithoutSecondPath_leavesOutScreenBsSharedProperty_whenSeamCorpusGraphDrawsSharedTypes() {
		// The second-path oracle runs every graph that draws types shared under a hole without `HoleScreenB`'s
		// `holeShared`, and no other graph with a hole. A graph without a hole records no second path: `addingHoleShapes`
		// records it, and draws nothing in such a graph.
		var mismatchedSeeds = [UInt64]()
		var drawingSeeds = [UInt64]()
		let fixtures = (0..<UInt64(SafeDIToolGraphFuzzerTests.seamCorpusSeedCount)).lazy.map { GraphFuzzerGenerator.fixture(forSeed: $0, features: [.generateDependencyTree]) }
		for fixture in fixtures where fixture.drawsHole {
			let seed = fixture.seed
			let drawsSharedTypes = GraphFuzzerFeature.seamDrawFeatures(of: fixture).contains(.holeSharedTypes)
			let withoutPath = GraphFuzzerGenerator.fixtureWithoutSecondPath(forSeed: seed, features: [.generateDependencyTree])
			let leavesOutTheProperty = withoutPath.map { withoutPath in
				withoutPath.typeName == fixture.typeNamePrefix + "HoleScreenB"
					&& withoutPath.label == "holeShared"
					&& !GraphFuzzerFeature.seamDrawFeatures(of: withoutPath.fixture).contains(.holeSharedTypes)
			}
			if drawsSharedTypes {
				drawingSeeds.append(seed)
			}
			if leavesOutTheProperty != (drawsSharedTypes ? true : nil) {
				mismatchedSeeds.append(seed)
			}
		}
		#expect(mismatchedSeeds == [])
		#expect(drawingSeeds.count >= 10)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The facts of the places the tool computes for `files`, a module named `Feature`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func placeFacts(of files: [String]) async throws -> GraphFuzzerPlaceFacts {
		var filesToDelete = filesToDelete
		let (_, facts) = try await collectingPlaceFacts {
			try await executeSafeDIToolTest(
				swiftFileContent: files,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				moduleMembershipArguments: ["--module-name", "Feature"],
			)
		}
		self.filesToDelete = filesToDelete
		return facts
	}

	/// A seam, `Home`, building `ScreenA` and `ScreenB`, which both instantiate `Shared`, which holds a place of `Service`:
	/// the design's shape E, `ScreenB` declaring `screenBDeclarations`.
	private static func sharedTypeFiles(screenBDeclarations: [String]) -> [String] {
		[
			"public protocol Service {}",
			seamFixtureType(named: "Shared", isFinalClass: true, declarations: ["@Instantiated let service: any Service"]),
			seamFixtureType(named: "ScreenA", isFinalClass: true, declarations: ["@Instantiated let shared: Shared"]),
			seamFixtureType(named: "ScreenB", isFinalClass: true, declarations: screenBDeclarations),
			seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let screenA: ScreenA", "@Instantiated let screenB: ScreenB"]),
		]
	}

	/// The facts of `sharedTypeFiles` with `ScreenB`'s second path, as the tool computes them.
	private static let sharedTypeFacts = GraphFuzzerPlaceFacts(
		producedCases: [
			producedCase(of: "Home", isSeamRoot: true, "screenA"),
			producedCase(of: "Home", isSeamRoot: true, "screenB"),
			producedCase(of: "ScreenA", "shared"),
			producedCase(of: "ScreenB", "service"),
			producedCase(of: "ScreenB", "shared"),
			producedCase(of: "Shared", "service"),
		],
		declaredLabels: [
			holder(of: "Home", isSeamRoot: true): ["screenA", "screenB", "inner"],
			holder(of: "ScreenA"): ["shared"],
			holder(of: "ScreenB"): ["service", "shared"],
			holder(of: "Shared"): ["service"],
		],
	)

	/// `Home`'s scope of `Service` nested by type, as the design's contract spells it, with `ScreenB`'s case for its second
	/// path to `Shared` when `screenBHoldsShared`, and an inner seam's wrapping case.
	private static func nestedHomeScope(screenBHoldsShared: Bool) -> String {
		"""
		extension Home {
		    @frozen public enum SafeDIScope_Service {
		        case screenA(screenA_Values, SafeDIScope_Service.ScreenA_Scope)
		        case screenB(screenB_Values, SafeDIScope_Service.ScreenB_Scope)
		        case inner(inner_Values, Inner.SafeDIScope_Service)

		        public struct screenA_Values {}

		        public struct screenB_Values {
		            public let screenA: ScreenA
		        }

		        public struct inner_Values {}

		        @frozen public enum ScreenA_Scope {
		            case shared(shared_Values, SafeDIScope_Service.Shared_Scope)

		            public struct shared_Values {}
		        }

		        @frozen public enum ScreenB_Scope {
		            case service(service_Values)
		\(screenBHoldsShared ? "            case shared(shared_Values, SafeDIScope_Service.Shared_Scope)\n" : "")
		            public struct service_Values {}
		\(screenBHoldsShared ? "\n            public struct shared_Values {\n                let service: any Service\n            }\n" : "")
		        }

		        @frozen public enum Shared_Scope {
		            case service(service_Values)

		            public struct service_Values {}
		        }
		    }
		}

		"""
	}

	/// `Home`'s scope of `Service` with one case per path, as 2.2.0 generates it.
	private static func flatHomeScope(screenBHoldsShared: Bool) -> String {
		"""
		extension Home {
		    @frozen public enum SafeDIScope_Service {
		        case screenA_shared_service(screenA_shared_service_Values)
		        case screenB_service(screenB_service_Values)
		\(screenBHoldsShared ? "        case screenB_shared_service(screenB_shared_service_Values)\n" : "")
		        public struct screenA_shared_service_Values {}

		        public struct screenB_service_Values {}
		\(screenBHoldsShared ? "\n        public struct screenB_shared_service_Values {}\n" : "")
		    }
		}

		"""
	}

	/// The holder `typeName` in the tree of `seamType`, or the seam's root.
	private static func holder(of typeName: String, inTreeOf seamType: String = "Home", isSeamRoot: Bool = false) -> GraphFuzzerPlaceFacts.Holder {
		GraphFuzzerPlaceFacts.Holder(seamType: seamType, typeName: typeName, isSeamRoot: isSeamRoot)
	}

	private static func producedCase(of typeName: String, inTreeOf seamType: String = "Home", isSeamRoot: Bool = false, _ label: String) -> GraphFuzzerPlaceFacts.ProducedCase {
		GraphFuzzerPlaceFacts.ProducedCase(holder: holder(of: typeName, inTreeOf: seamType, isSeamRoot: isSeamRoot), label: label)
	}

	private static func levelKey(of typeName: String, inTreeOf seamType: String = "Home", isSeamRoot: Bool = false, _ nextProperty: String) -> GraphFuzzerPlaceFacts.LevelKey {
		GraphFuzzerPlaceFacts.LevelKey(holder: holder(of: typeName, inTreeOf: seamType, isSeamRoot: isSeamRoot), nextProperty: nextProperty)
	}
}
