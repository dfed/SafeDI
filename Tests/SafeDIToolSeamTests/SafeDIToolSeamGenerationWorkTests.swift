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

/// How the work of generating a seam grows with the paths to its places. Each step `GenerationWork` counts once did work
/// that grew with the square of a seam's places, so that a seam reached along thousands of paths took minutes to
/// generate; the work is counted, not timed, so that the check is the same on every machine and every run. Each step
/// counts its work where a scope, fill, builder or name takes what it consults, so a step that builds or scans a
/// collection again for each of them counts that work, whatever the step's own code reports.
struct SafeDIToolSeamGenerationWorkTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_growsEachCountedStepNoFasterThanThePathsToThePlaces_whenSeamReachesItsPlacesAlongManyPaths() async throws {
		// Shape E (`SafeDIToolSeamScopeByTypeTests.shapeEModules`) triples the paths to the places with each layer of screens,
		// whether the places are the models' own or in the fills of a seam each model calls. A step whose work grew with the
		// square of the places grew nine times with each layer where its names grow with the paths, as they do when every
		// path reaches screens of its own; where its names grow with the layers instead, it grew only a little faster than
		// the paths.
		// The type key lays out production roots, not seams: `SafeDIToolTypeKeyViewTests` counts its views. The search for
		// root functions runs while code is emitted, where a seam whose signature takes more than one pass starts code it
		// then discards, which records or not as tasks are scheduled; `SafeDIToolTypeKeyViewTests` counts it on production
		// roots, which take one pass, as it does the type key's checks of reads at every member.
		// A lookup in the construction memo asks the candidates its context answers alike, whatever the shape:
		// `SafeDIToolConstructionMemoTests` counts them on a tree with cycles, and the reads it files entries under on a chain.
		// The walk that collects the types a tree builds visits each generator once, and places of a seam's tree with
		// holes share none: `SafeDIToolFulfillerImportTests` counts it on a production root whose places share generators.
		// Finding the carrier a sibling requires grows with the children of one scope, which shape E does not grow: the test
		// below counts it on a seam whose own type builds many children.
		// The walk that finds the values a seam tier omits enters only a subtree that holds a call omitting a parameter or a
		// scope closing a lazy cycle, which shape E has neither of: the test of layers of screens below counts it.
		// Finding the value each receive is handed runs for `query graph` alone: `SafeDIToolQueryGraphTests` counts it on
		// layers of screens that open screens of the next layer.
		let seamSteps = Set(GenerationWork.Step.allCases).subtracting([.layingOutTypeKeyViews, .computingPlanNodeDomains, .spellingStructuralKeyFacts, .findingRootFunctions, .checkingReadsAtEveryMember, .askingMemoCandidates, .filingMemoEntryReads, .collectingTypesOfATree, .collectingDeclarationsOfACycle, .findingCarrierASiblingRequires, .findingSeamTierOmissions, .findingReceivedValueSupplies])
		var countedSteps = Set<GenerationWork.Step>()
		for shape in Shape.allCases {
			var measures = [Measure]()
			for screenCount in Self.screenCounts {
				let shapeMeasure = try await measure(screenCount: screenCount, shape: shape)
				measures.append(shapeMeasure)
			}
			for (smaller, larger) in zip(measures, measures.dropFirst()) {
				let pathGrowth = Double(larger.pathCount) / Double(smaller.pathCount)
				for step in GenerationWork.Step.allCases where seamSteps.contains(step) {
					let smallerWork = smaller.workByStep[step, default: 0]
					let largerWork = larger.workByStep[step, default: 0]
					guard smallerWork > 0 else {
						#expect(largerWork == 0, "\(shape) counts no work for \(step.rawValue) along \(smaller.pathCount) paths, and \(largerWork) along \(larger.pathCount)")
						continue
					}
					countedSteps.insert(step)
					let workGrowth = Double(largerWork) / Double(smallerWork)
					#expect(
						workGrowth <= pathGrowth * Self.maximumWorkGrowthPerPathGrowth,
						"\(shape): \(step.rawValue) does \(smallerWork) units of work along \(smaller.pathCount) paths and \(largerWork) along \(larger.pathCount): \(String(format: "%.2f", workGrowth))× the work for \(String(format: "%.2f", pathGrowth))× the paths",
					)
				}
			}
		}
		#expect(seamSteps.subtracting(countedSteps).isEmpty, "No shape counts work for \(seamSteps.subtracting(countedSteps).map(\.rawValue).sorted())")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_looksUpEachPropertyASiblingRequiresOnce_whenSeamsOwnTypeBuildsManyChildrenThatEachHoldAPlace() async throws {
		// A seam whose own type builds n children, each holding a place and receiving one value. Each child after the one
		// that leads to a site is asked, in each of the two passes over the sites, for the first carrier among its
		// siblings that it requires: scanned for, the n carriers were compared for each of them at each site, 48
		// comparisons at four children and 448 at eight; looked up, the one property each requires is, 12 lookups and 56.
		var lookups = [Int]()
		for childCount in [4, 8] {
			var fixture = [
				"public protocol Gizmo {}",
				seamFixtureType(named: "Service", declarations: []),
				seamFixtureType(named: "Entry", isSeam: true, declarations: (0..<childCount).map { "@Instantiated let child\($0): Child\($0)" }),
			]
			for child in 0..<childCount {
				fixture.append(seamFixtureType(named: "Child\(child)", declarations: ["@Received let service: Service", "@Instantiated let gizmo: any Gizmo"]))
			}
			let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
			try await GenerationWork.$observer.withValue({ continuation.yield($0) }) { [fixture] in
				_ = try await executeSafeDIToolMultiModuleTest(
					modules: [ModuleFixture(name: "Feature", packageName: "App", swiftFileContent: [fixture.joined(separator: "\n\n")], dependencies: [])],
					integration: .moduleInfo,
					compileVerification: childCount == 4 ? .recordingIssues : .skipped,
					filesToDelete: &filesToDelete,
				)
			}
			continuation.finish()
			var count = 0
			for await work in stream where work.step == .findingCarrierASiblingRequires {
				count += work.elementCount
			}
			lookups.append(count)
		}
		#expect(lookups == [12, 56])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesEachPlaceStoodForOnceInCaptureWalk_whenCallsCasesGrowWithThreePlacesEach() async throws {
		// `Home` builds n holders of a place of `Api`, a case each, beneath three parents each: the first parent's fill
		// generates code, and the second's stands for the third's. `Root` names an `Instantiator` and a
		// `SendableInstantiator`, so the walk for captured wrappers reaches the call, where each fill takes the places
		// it stands for: n places gathered once and taken once. Each of the three passes over the call also looks a
		// standing fill up for each of its 3n places and asks the one set of its case for each third place: 14n units
		// in all. Scanned for by each of the 2n fills, the n places stood for were compared 2n² times.
		var work = [Int]()
		for holderCount in [8, 16] {
			var feature = ["public protocol Api {}"]
			var homeDeclarations = [String]()
			for holder in 0..<holderCount {
				feature.append(seamFixtureType(named: "Holder\(holder)", declarations: ["@Instantiated let api: any Api"]))
				for parent in ["First", "Second", "Third"] {
					feature.append(seamFixtureType(named: "\(parent)\(holder)", declarations: ["@Instantiated let holder: Holder\(holder)"]))
					homeDeclarations.append("@Instantiated let \(parent.lowercased())\(holder): \(parent)\(holder)")
				}
			}
			feature.append(seamFixtureType(named: "Home", isSeam: true, declarations: homeDeclarations))
			let modules = SafeDIToolSeamBuilderParameterTests.modules(
				feature: feature,
				app: [
					SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: []),
					seamFixtureType(named: "Row", declarations: []),
					seamFixtureType(named: "Worker", declarations: []).replacingOccurrences(of: ": Instantiable", with: ": Instantiable, Sendable"),
					seamFixtureType(named: "Root", isRoot: true, declarations: [
						"@Instantiated let rowBuilder: Instantiator<Row>",
						"@Instantiated let workerBuilder: SendableInstantiator<Worker>",
						"@Instantiated let home: Home",
					]),
				],
			)
			let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
			try await GenerationWork.$observer.withValue({ continuation.yield($0) }) {
				_ = try await executeSafeDIToolMultiModuleTest(
					modules: modules,
					integration: .moduleInfo,
					compileVerification: holderCount == 8 ? .recordingIssues : .skipped,
					filesToDelete: &filesToDelete,
				)
			}
			continuation.finish()
			var count = 0
			for await generationWork in stream where generationWork.step == .findingFillThatStandsForPlace {
				count += generationWork.elementCount
			}
			work.append(count)
		}
		#expect(work == [112, 224])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_walksEachSeamsTreeOncePerGeneratorAndContext_whenScreensOpenScreensOfTheNextLayer() async throws {
		// Layers of four screens, each holding instantiators of three screens of the next layer, every screen of the first
		// layer a seam and every screen receiving `service`: places share generators (see `ConstructionMemo`), so the last
		// layer is reached from each seam along 3^(layers - 1) paths. The walk that collects the names of a seam's builder
		// functions visits each generator once, and the walk that finds a seam's receivers each generator once for each
		// context it is reached in, as far as its subtree reads it: here one. No call omits a parameter and no cycle closes,
		// so the walk that finds the values a tier omits enters nothing. Each of the last two walks visited every path: at
		// four and six layers, 160 and 1,456 visits each.
		let visits = try await visitsInLayersOfScreens()
		#expect(visits == [
			[.collectingBuilderFunctionNames: 96, .findingSeamReceivers: 100, .findingSeamTierOmissions: 0],
			[.collectingBuilderFunctionNames: 160, .findingSeamReceivers: 196, .findingSeamTierOmissions: 0],
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_walksNoPathOfSeamsTreeForOmissions_whenNoCallOmitsParameterAndLastLayerClosesLazyCycles() async throws {
		// The layers of screens above, each screen of the last layer holding an instantiator of itself: a lazy cycle closes
		// at the end of every path. A scope that closes a lazy cycle only records calls, which judge what a call omitting a
		// parameter reads, and no call omits one, so the walk that finds the values a tier omits enters nothing. It entered
		// every path to a cycle's closer: at four and six layers, 160 and 1,456 visits.
		let visits = try await visitsInLayersOfScreens(screenDeclarations: { layer, position, layerCount in
			layer + 1 == layerCount ? ["@Instantiated let screen\(layer)x\(position)Builder: Instantiator<Screen\(layer)x\(position)>"] : []
		})
		#expect(visits == [
			[.collectingBuilderFunctionNames: 128, .findingSeamReceivers: 116, .findingSeamTierOmissions: 0],
			[.collectingBuilderFunctionNames: 192, .findingSeamReceivers: 212, .findingSeamTierOmissions: 0],
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_walksEachSeamsTreeOncePerGeneratorAndContext_whenEveryScreenDeclaresViewModelItsViewReceives() async throws {
		// The layers of screens above, each screen declaring a view model of its own type under one label, and a view that
		// receives it. Every path declares the label again at each screen, with the type of the screens it went through, so
		// a frame that kept every declaration above a screen whose subtree reads the label was another on every path. A
		// screen's own view model is nearer its subtree than any above it, so the walk that finds a seam's receivers keys
		// no screen by those above, and visits each generator once per context. It visited every path: at four and six
		// layers, 480 and 4,368 visits.
		let visits = try await visitsInLayersOfScreens(
			screenDeclarations: { layer, position, _ in
				["@Instantiated let viewModel: Screen\(layer)x\(position)ViewModel", "@Instantiated let view: Screen\(layer)x\(position)View"]
			},
			screenTypes: { layer, position in
				[
					seamFixtureType(named: "Screen\(layer)x\(position)ViewModel", declarations: []),
					seamFixtureType(named: "Screen\(layer)x\(position)View", declarations: ["@Received let viewModel: Screen\(layer)x\(position)ViewModel"]),
				]
			},
		)
		#expect(visits == [
			[.collectingBuilderFunctionNames: 288, .findingSeamReceivers: 196, .findingSeamTierOmissions: 0],
			[.collectingBuilderFunctionNames: 480, .findingSeamReceivers: 356, .findingSeamTierOmissions: 0],
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_walksOnlyPathsToCallOmittingParameter_whenFirstLayerCallsTierThatOmitsParameter() async throws {
		// The layers of screens above, each screen of the first layer also calling `Library`'s `Panel`, whose `public` tier
		// omits the `token` its `Badge` receives only if available, since `Token` is internal. The walk that finds the
		// values a tier omits enters the call in each screen of the first layer, and none of the layers beneath, which hold
		// no such call: the same visits at four and six layers.
		let visits = try await visitsInLayersOfScreens(
			screenDeclarations: { layer, _, _ in layer == 0 ? ["@Instantiated let panel: Panel"] : [] },
			libraryModule: ModuleFixture(
				name: "Library",
				packageName: "App",
				swiftFileContent: [
					seamFixtureType(named: "Panel", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    init(token: Token?) {
					        self.token = token
					    }

					    @Received(onlyIfAvailable: true) let token: Token?
					}
					""",
					"""
					@Instantiable
					struct Token: Instantiable {
					    init() {}
					}
					""",
				],
				dependencies: [],
			),
		)
		#expect(visits == [
			[.collectingBuilderFunctionNames: 216, .findingSeamReceivers: 212, .findingSeamTierOmissions: 4],
			[.collectingBuilderFunctionNames: 344, .findingSeamReceivers: 404, .findingSeamTierOmissions: 4],
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsEachScopeOfACycleOnce_whenLayersOfScreensBetweenPlaceAndItsCycleClosingScopesShareSubtrees() async throws {
		// `Entry` builds `W`, which holds a place and builds three screens; each screen builds every screen of the next
		// layer, and each screen of the last layer builds `W` again. The paths from `W` to a `W` built again triple with
		// each layer, 9 through two layers and 81 through four, while the scopes between them grow by three.
		var generatorsRead = [Int]()
		for layerCount in [2, 4] {
			var fixture = [
				"public protocol Gizmo {}",
				seamFixtureType(named: "Entry", isSeam: true, declarations: ["@Instantiated let wBuilder: Instantiator<W>"]),
				seamFixtureType(named: "W", declarations: ["@Instantiated let gizmo: any Gizmo"] + (0..<3).map { "@Instantiated let screen0x\($0)Builder: Instantiator<Screen0x\($0)>" }),
			]
			for layer in 0..<layerCount {
				for screen in 0..<3 {
					fixture.append(seamFixtureType(
						named: "Screen\(layer)x\(screen)",
						declarations: layer == layerCount - 1
							? ["@Instantiated let wBuilder: Instantiator<W>"]
							: (0..<3).map { "@Instantiated let screen\(layer + 1)x\($0)Builder: Instantiator<Screen\(layer + 1)x\($0)>" },
					))
				}
			}
			let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
			try await GenerationWork.$observer.withValue({ continuation.yield($0) }) { [fixture] in
				_ = try await executeSafeDIToolMultiModuleTest(
					modules: [ModuleFixture(name: "Feature", packageName: "App", swiftFileContent: [fixture.joined(separator: "\n\n")], dependencies: [])],
					integration: .moduleInfo,
					compileVerification: layerCount == 2 ? .recordingIssues : .skipped,
					filesToDelete: &filesToDelete,
				)
			}
			continuation.finish()
			var count = 0
			for await work in stream where work.step == .collectingDeclarationsOfACycle {
				count += work.elementCount
			}
			generatorsRead.append(count)
		}
		// The signature is computed three times. Walked along every path, each time read the 12 and the 120 scopes on the
		// paths, 36 and 360 in all; read once per generator, the 6 and the 44 generators the construction memo makes of them.
		#expect(generatorsRead == [18, 132])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The visits each walk of a seam's tree `GenerationWork` counts makes as module `Feature` is generated, at four and at
	/// six layers of four screens, each screen holding instantiators of three screens of the next layer, every screen of
	/// the first layer a seam and every screen receiving `service`. A screen also declares `screenDeclarations` of its
	/// layer, position and the layer count, beside `screenTypes` of its layer and position, and `Feature` depends on
	/// `libraryModule`, where one is given, and imports it.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func visitsInLayersOfScreens(
		screenDeclarations: (_ layer: Int, _ position: Int, _ layerCount: Int) -> [String] = { _, _, _ in [] },
		screenTypes: (_ layer: Int, _ position: Int) -> [String] = { _, _ in [] },
		libraryModule: ModuleFixture? = nil,
	) async throws -> [[GenerationWork.Step: Int]] {
		var visitsByLayerCount = [[GenerationWork.Step: Int]]()
		for layerCount in [4, 6] {
			var fixture = [seamFixtureType(named: "Service", declarations: [])]
			for layer in 0..<layerCount {
				for position in 0..<4 {
					var declarations = ["@Received let service: Service"]
					if layer + 1 < layerCount {
						declarations += (0..<3).map { offset in "@Instantiated let screen\(layer + 1)x\((position + offset) % 4)Builder: Instantiator<Screen\(layer + 1)x\((position + offset) % 4)>" }
					}
					declarations += screenDeclarations(layer, position, layerCount)
					fixture.append(seamFixtureType(named: "Screen\(layer)x\(position)", isSeam: layer == 0, declarations: declarations))
					fixture += screenTypes(layer, position)
				}
			}
			let feature = ModuleFixture(
				name: "Feature",
				packageName: "App",
				swiftFileContent: [(libraryModule.map { "import \($0.name)\n\n" } ?? "") + fixture.joined(separator: "\n\n")],
				dependencies: libraryModule.map { [$0.name] } ?? [],
			)
			let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
			try await GenerationWork.$observer.withValue({ continuation.yield($0) }) {
				_ = try await executeSafeDIToolMultiModuleTest(
					modules: (libraryModule.map { [$0] } ?? []) + [feature],
					integration: .moduleInfo,
					compileVerification: layerCount == 4 ? .recordingIssues : .skipped,
					filesToDelete: &filesToDelete,
				)
			}
			continuation.finish()
			let countedSteps: [GenerationWork.Step] = [.collectingBuilderFunctionNames, .findingSeamReceivers, .findingSeamTierOmissions]
			var visits = Dictionary(uniqueKeysWithValues: countedSteps.map { ($0, 0) })
			for await work in stream where countedSteps.contains(work.step) {
				visits[work.step, default: 0] += work.elementCount
			}
			visitsByLayerCount.append(visits)
		}
		return visitsByLayerCount
	}

	/// A shape measured: shape E, its places in the fills of an inner seam, and both with every path's screens its own.
	private enum Shape: String, CaseIterable, CustomStringConvertible {
		case shapeE = "Shape E"
		case placesInFillsOfInnerSeam = "Shape E with its places in the fills of an inner seam"
		case placesInFillsOfInnerSeamAlongPathsOfTheirOwn = "Shape E with its places in the fills of an inner seam, every path opening screens of its own"

		var description: String {
			rawValue
		}

		var modulesHavePlacesInFillsOfInnerSeam: Bool {
			switch self {
			case .shapeE:
				false
			case .placesInFillsOfInnerSeam,
			     .placesInFillsOfInnerSeamAlongPathsOfTheirOwn:
				true
			}
		}

		var opensScreensOfItsOwn: Bool {
			switch self {
			case .shapeE,
			     .placesInFillsOfInnerSeam:
				false
			case .placesInFillsOfInnerSeamAlongPathsOfTheirOwn:
				true
			}
		}
	}

	/// The work of every counted step for a shape with `screenCount / 4` layers, and the paths to its places.
	private struct Measure {
		let pathCount: Int
		let workByStep: [GenerationWork.Step: Int]
	}

	/// The screens of each shape measured: three, four and five layers of four, whose last layers' screens are reached
	/// along 36, 108 and 324 paths.
	private static let screenCounts = [12, 16, 20]

	/// How much faster than the paths to the places a step's work may grow from one shape to the next. A step whose work
	/// grows with the places grows as fast as the paths, or slower where part of its work is the same for every shape; a
	/// step whose work grows with the square of the places grows three times as fast.
	private static let maximumWorkGrowthPerPathGrowth = 1.1

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func measure(screenCount: Int, shape: Shape) async throws -> Measure {
		let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
		try await GenerationWork.$observer.withValue({ continuation.yield($0) }) {
			_ = try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamScopeByTypeTests.shapeEModules(
					screenCount: screenCount,
					placesInFillsOfInnerSeam: shape.modulesHavePlacesInFillsOfInnerSeam,
					opensScreensOfItsOwn: shape.opensScreensOfItsOwn,
				),
				integration: .moduleInfo,
				// The smallest shape is compiled, so that the work the check measures is that of code that compiles.
				compileVerification: screenCount == Self.screenCounts.first ? .recordingIssues : .skipped,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var workByStep = [GenerationWork.Step: Int]()
		for await work in stream {
			workByStep[work.step, default: 0] += work.elementCount
		}
		// Each screen of a layer but the last opens three of the next layer's screens, and the first layer's four are `Home`'s,
		// whether the screens are shared or every path's own.
		let pathCount = 4 * Int(pow(3, Double(screenCount / 4 - 1)))
		return Measure(pathCount: pathCount, workByStep: workByStep)
	}
}
