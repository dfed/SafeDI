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

/// How the code a seam generates grows with the shape of its tree: what a value bound in the seam's tree costs where no
/// generated fill can read it, and how a wide seam's generated code grows when every axis of its graph grows together.
struct SafeDIToolSeamGeneratedSizeTests: ~Copyable {
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
	mutating func generate_addsOneLinePerService_whenSeamPassesUpPlacesOfInnerSeams() async throws {
		// The adopter's wide shape P1, scaled down: `Home` instantiates services, then an instantiator of each of two screens,
		// each a seam of `Screens` that holds two hole types, which `Home` passes up for `App` to fill. No generated fill reads
		// a value `Home` binds before a call, and a call's case holds the screen's enum alone, so a service costs `Home` the one
		// line that builds it, as it would inline. When each call's case of each hole type carried every service, a service
		// cost a line per screen per hole type, and the adopter's 100 services, 40 screens and three hole types generated
		// 15,159 lines where `Home` generated 459 before its enums were nested by type.
		let oneService = try await homeLineCount(serviceCount: 1)
		let threeServices = try await homeLineCount(serviceCount: 3)
		#expect(threeServices - oneService == 2)
	}

	/// The adopter's wide seam, scaled down so that its source grows linearly: seam `Home` instantiates `2n` services and
	/// then `n` screens through instantiators, each screen holding a place of two of the `n` hole types, which `Home` passes
	/// up for `App` to fill. A graph twice as large must generate at most `maximumGrowthPerDoubling` times the lines, and
	/// the characters, in every module. Before an inner seam's case stopped carrying what the calling seam binds before the
	/// call, each service cost a line per screen per hole type where the screens are inner seams, so `Home`'s lines grew
	/// with the services times the screens.
	///
	/// Three shapes are known to grow faster than the graph until 2.3.1, and are excluded by name: `Feat` where the screens
	/// are inline in the seam, whose case for each screen carries the values bound before it, which generated fills read
	/// (`knownToGrowFasterThanTheGraph`, run as a known issue, so that the check reports it once it is fixed, and held
	/// below `maximumKnownGrowthPerDoubling`, so that growth of a higher order than quadratic does not go unnoticed); a
	/// large seam whose tree reaches a type along many paths (`SafeDIToolSeamScopeByTypeTests`'s `shapeEModules`); and a
	/// large public mock on a layered graph of shared screens. This check's graph is neither of the last two, so it builds
	/// neither.
	@Test(arguments: ScreenPlacement.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_growsAtMostTwoPointTwoTimesPerDoubling_whenSeamPassesUpPlacesOfItsScreens(screenPlacement: ScreenPlacement) async throws {
		var sizesByGraphSize = [Int: [String: GeneratedSize]]()
		for graphSize in Self.graphSizes {
			sizesByGraphSize[graphSize] = try await generatedSizeByModule(
				graphSize: graphSize,
				screenPlacement: screenPlacement,
				// The smallest graph is compiled, so that the code the check measures is code that compiles.
				compileVerification: graphSize == Self.graphSizes.first ? .recordingIssues : .skipped,
			)
		}
		for moduleName in screenPlacement.generatingModuleNames {
			var excessiveGrowths = [String]()
			var growthsBeyondTheKnownCeiling = [String]()
			for (smallerGraphSize, largerGraphSize) in zip(Self.graphSizes, Self.graphSizes.dropFirst()) {
				let smaller = try #require(sizesByGraphSize[smallerGraphSize]?[moduleName])
				let larger = try #require(sizesByGraphSize[largerGraphSize]?[moduleName])
				for (measure, smallerCount, largerCount) in [("lines", smaller.lineCount, larger.lineCount), ("characters", smaller.characterCount, larger.characterCount)] {
					let growth = Double(largerCount) / Double(smallerCount)
					let description = "Module \(moduleName) generates \(smallerCount) \(measure) at size \(smallerGraphSize) and \(largerCount) at size \(largerGraphSize), \(String(format: "%.2f", growth))× the \(measure) for twice the graph"
					if growth > Self.maximumGrowthPerDoubling {
						excessiveGrowths.append(description)
					}
					if growth > Self.maximumKnownGrowthPerDoubling {
						growthsBeyondTheKnownCeiling.append(description)
					}
				}
			}
			if Self.knownToGrowFasterThanTheGraph.contains(KnownGrowth(screenPlacement: screenPlacement, moduleName: moduleName)) {
				withKnownIssue("Each screen’s case carries the values bound before it, which generated fills read: shared storage, not yet built") {
					#expect(excessiveGrowths.isEmpty, "\(excessiveGrowths.joined(separator: "\n"))")
				}
				#expect(growthsBeyondTheKnownCeiling.isEmpty, "\(growthsBeyondTheKnownCeiling.joined(separator: "\n"))")
			} else {
				#expect(excessiveGrowths.isEmpty, "\(excessiveGrowths.joined(separator: "\n"))")
			}
		}
	}

	/// Where the screens `Home` builds are declared.
	enum ScreenPlacement: CaseIterable {
		/// Each screen is a seam of module `Screens`, whose places `Home` passes up: the adopter's wide seam.
		case innerSeams
		/// Each screen is a plain type in `Home`'s module and tree: the adopter's wide seam with its screens inline.
		case inlineInTheSeam

		/// The modules whose generated code the check measures: each that generates code for the graph.
		var generatingModuleNames: [String] {
			switch self {
			case .innerSeams:
				["Screens", "Feat", "App"]
			case .inlineInTheSeam:
				["Feat", "App"]
			}
		}

		/// The attributes of each screen's declaration.
		var screenAttributes: String {
			switch self {
			case .innerSeams:
				"@Instantiable(generateDependencyTree: true)"
			case .inlineInTheSeam:
				"@Instantiable"
			}
		}
	}

	/// The size of a module's generated code.
	struct GeneratedSize {
		var lineCount: Int
		var characterCount: Int
	}

	/// A module of one placement whose generated code is known to grow faster than the graph.
	struct KnownGrowth: Hashable {
		var screenPlacement: ScreenPlacement
		var moduleName: String
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The most a module's generated lines or characters may grow when every axis of the graph doubles. The contract asks
	/// that size be linear; the margin above 2 is for the constant lines of each file.
	private static let maximumGrowthPerDoubling = 2.2

	/// The most the generated code of a module of `knownToGrowFasterThanTheGraph` may grow when every axis of the graph
	/// doubles: twice `maximumGrowthPerDoubling`, the growth of code quadratic in the graph's size, with the same margin.
	private static let maximumKnownGrowthPerDoubling = 4.4

	/// Each size is twice the one before it. With the screens as inner seams, `Feat` generates 31 + 12n lines; at these
	/// sizes a quadratic part as small as n² / 16 lines beside that grows more than `maximumGrowthPerDoubling` from 32 to
	/// 64, where at 4, 8 and 16 one of n² / 4 did not.
	private static let graphSizes = [16, 32, 64]

	/// The modules whose generated code is known to grow faster than the graph, each until its fix lands.
	private static let knownToGrowFasterThanTheGraph: Set<KnownGrowth> = [KnownGrowth(screenPlacement: .inlineInTheSeam, moduleName: "Feat")]

	/// The number of lines `Feat` generates for `Home`, which instantiates `serviceCount` services, then
	/// `screen0Builder: Instantiator<Screen0>` and `screen1Builder: Instantiator<Screen1>`, each screen a seam of module
	/// `Screens` that instantiates `widget: any Widget` and `gadget: any Gadget`, which `App` fills.
	private mutating func homeLineCount(serviceCount: Int) async throws -> Int {
		let services = (0..<serviceCount).map { Self.type(named: "Service\($0)", properties: []) }
		let screens = (0..<2).map { index in
			Self.type(named: "Screen\(index)", attributes: "@Instantiable(generateDependencyTree: true)", properties: ["@Instantiated let widget: any Widget", "@Instantiated let gadget: any Gadget"])
		}
		let homeProperties = (0..<serviceCount).map { "@Instantiated let service\($0): Service\($0)" } + (0..<2).map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" }
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: ["public protocol Widget {}", "public protocol Gadget {}"] + services),
				ModuleFixture(name: "Screens", packageName: "Shop", swiftFileContent: screens.map { "import Core\n\n" + $0 }, dependencies: ["Core"]),
				ModuleFixture(
					name: "Feat",
					packageName: "Shop",
					swiftFileContent: ["import Core\nimport Screens\n\n" + Self.type(named: "Home", attributes: "@Instantiable(generateDependencyTree: true)", properties: homeProperties)],
					dependencies: ["Core", "Screens"],
				),
				ModuleFixture(
					name: "App",
					packageName: "Other",
					swiftFileContent: [
						"@Instantiable(fulfillingAdditionalTypes: [Widget.self])\npublic final class LiveWidget: Widget, Instantiable {\n    public init() {}\n}",
						"@Instantiable(fulfillingAdditionalTypes: [Gadget.self])\npublic final class LiveGadget: Gadget, Instantiable {\n    public init() {}\n}",
						Self.type(named: "Root", attributes: "@Instantiable(isRoot: true)", properties: ["@Instantiated let home: Home"]),
					].map { "import Core\nimport Feat\nimport Screens\n\n" + $0 },
					dependencies: ["Core", "Screens", "Feat"],
				),
			],
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		let generated = try #require(output.modules["Feat"]?.generatedFiles["Feat.swift"])
		return generated.components(separatedBy: "\n").count
	}

	/// The size of the code each module generates for the wide graph at `graphSize` with its screens placed by
	/// `screenPlacement`, by module name.
	private mutating func generatedSizeByModule(graphSize: Int, screenPlacement: ScreenPlacement, compileVerification: MultiModuleCompileVerification) async throws -> [String: GeneratedSize] {
		let serviceCount = 2 * graphSize
		let screenCount = graphSize
		let holeTypeCount = graphSize
		let configuration = ["SafeDIConfiguration.swift": "import SafeDI\n\n#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)"]
		let services = (0..<serviceCount).map { Self.type(named: "Service\($0)", properties: []) }
		let holeTypes = (0..<holeTypeCount).map { "public protocol Hole\($0) {}" }
		let screens = (0..<screenCount).map { index in
			Self.type(
				named: "Screen\(index)",
				attributes: screenPlacement.screenAttributes,
				properties: Self.holeTypeIndices(ofScreen: index, holeTypeCount: holeTypeCount).map { "@Instantiated let hole\($0): any Hole\($0)" },
			)
		}
		let homeProperties = (0..<serviceCount).map { "@Instantiated let service\($0): Service\($0)" } + (0..<screenCount).map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" }
		let home = Self.type(named: "Home", attributes: "@Instantiable(generateDependencyTree: true)", properties: homeProperties)
		let liveTypes = (0..<holeTypeCount).map { index in
			"@Instantiable(fulfillingAdditionalTypes: [Hole\(index).self])\npublic final class Live\(index): Hole\(index), Instantiable {\n    public init() {}\n}"
		}
		let app = "import Core\nimport Feat\n\n" + (liveTypes + [Self.type(named: "Root", attributes: "@Instantiable(isRoot: true)", properties: ["@Instantiated let home: Home"])]).joined(separator: "\n\n")
		let core = ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: [(holeTypes + services).joined(separator: "\n\n")])
		let modules: [ModuleFixture] = switch screenPlacement {
		case .innerSeams:
			[
				core,
				ModuleFixture(
					name: "Screens",
					packageName: "Shop",
					swiftFileContent: ["import Core\n\n" + screens.joined(separator: "\n\n")],
					swiftFileContentByFilePath: configuration,
					dependencies: ["Core"],
				),
				ModuleFixture(
					name: "Feat",
					packageName: "Shop",
					swiftFileContent: ["import Core\nimport Screens\n\n" + home],
					swiftFileContentByFilePath: configuration,
					dependencies: ["Core", "Screens"],
				),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [app], dependencies: ["Core", "Screens", "Feat"]),
			]
		case .inlineInTheSeam:
			[
				core,
				ModuleFixture(
					name: "Feat",
					packageName: "Shop",
					swiftFileContent: ["import Core\n\n" + (screens + [home]).joined(separator: "\n\n")],
					swiftFileContentByFilePath: configuration,
					dependencies: ["Core"],
				),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [app], dependencies: ["Core", "Feat"]),
			]
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules,
			integration: .moduleInfo,
			compileVerification: compileVerification,
			filesToDelete: &filesToDelete,
		)
		var sizeByModule = [String: GeneratedSize]()
		for moduleName in screenPlacement.generatingModuleNames {
			let generated = try #require(output.modules[moduleName]?.generatedFiles["\(moduleName).swift"])
			sizeByModule[moduleName] = GeneratedSize(lineCount: generated.components(separatedBy: "\n").count, characterCount: generated.count)
		}
		return sizeByModule
	}

	/// The hole types screen `index` holds a place of: its own and the next, so that each hole type has a place in two
	/// screens and the graph's source grows linearly with its size.
	private static func holeTypeIndices(ofScreen index: Int, holeTypeCount: Int) -> [Int] {
		[index, (index + 1) % holeTypeCount]
	}

	/// A `public final class` named `name` whose initializer takes `properties`, each of `@Attribute let label: Type`.
	private static func type(named name: String, attributes: String = "@Instantiable", properties: [String]) -> String {
		let parameters = properties.map { property in
			property.components(separatedBy: " let ").last ?? ""
		}
		let labels = parameters.map { String($0.prefix { $0 != ":" }) }
		return """
		\(attributes)
		public final class \(name): Instantiable {
		    public init(\(parameters.joined(separator: ", "))) {
		\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
		    }
		\(properties.map { "    \($0)" }.joined(separator: "\n"))
		}
		"""
	}
}
