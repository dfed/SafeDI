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

/// A module that mocks several types on one cycle of builders: every mock's tree holds the same places of the cycle, so
/// what the mocks could share is each place's function. Each cell lays every mock root out from node records and holds
/// the values it builds, lap by lap around the cycle and with an override, to those the mock's walk builds
/// (`MockKindsAcceptance`), whichever of the mocks a place's function is written for.
struct SafeDIToolNodeRecordsMockSharedSlotTests: ~Copyable {
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
	mutating func mock_buildsWalksValuesFromEveryRoot_whenBothTypesOfCycleAreMocked() async throws {
		let names = ["Alpha", "Bravo"]
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(
			fixtureFiles: Self.ring(names),
			probes: Self.probes(aroundRing: names, laps: 5),
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValuesFromEveryRoot_whenEveryTypeOfCycleOfThreeIsMocked() async throws {
		let names = ["Alpha", "Bravo", "Charlie"]
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(
			fixtureFiles: Self.ring(names),
			probes: Self.probes(aroundRing: names, laps: 7),
			filesToDelete: &filesToDelete,
		)
	}

	/// Which edge of a cycle the configurations leave out follows the types' names, so each order of three names around
	/// the cycle leaves out another edge, and every mock must hold in each.
	@Test(arguments: [
		["Alpha", "Bravo", "Charlie"],
		["Alpha", "Charlie", "Bravo"],
		["Bravo", "Alpha", "Charlie"],
		["Bravo", "Charlie", "Alpha"],
		["Charlie", "Alpha", "Bravo"],
		["Charlie", "Bravo", "Alpha"],
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValuesFromEveryRoot_whenCycleOfThreeMockedTypesIsNamedInEveryOrder(names: [String]) async throws {
		// A type off the cycle enters it too, so a mock whose root is on no cycle holds the same places.
		var fixtureFiles = Self.ring(names)
		fixtureFiles["Entry.swift"] = Self.type("Entry", building: [names[1]])
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(
			fixtureFiles: fixtureFiles,
			probes: Self.probes(aroundRing: names, laps: 4)
				+ Self.probes(from: "Entry", path: [names[1]] + Self.path(aroundRing: names, from: 2, steps: 4), graph: Self.graph(ofRing: names)),
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValuesFromEveryRoot_whenTwoMockedCyclesShareAType() async throws {
		// `Hub` builds `Left`, which builds `Hub`, and `Right`, which builds `Hub`: two cycles through one type.
		let fixtureFiles = [
			"Marked.swift": Self.markedFile,
			"Hub.swift": Self.type("Hub", building: ["Left", "Right"]),
			"Left.swift": Self.type("Left", building: ["Hub"]),
			"Right.swift": Self.type("Right", building: ["Hub"]),
		]
		let paths = [
			["Left", "Hub", "Right", "Hub", "Left", "Hub"],
			["Right", "Hub", "Left", "Hub", "Right", "Hub"],
		]
		let graph = ["Hub": ["Left", "Right"], "Left": ["Hub"], "Right": ["Hub"]]
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(
			fixtureFiles: fixtureFiles,
			probes: paths.flatMap { Self.probes(from: "Hub", path: $0, graph: graph) }
				+ Self.probes(from: "Left", path: ["Hub", "Right", "Hub", "Left", "Hub"], graph: graph)
				+ Self.probes(from: "Right", path: ["Hub", "Left", "Hub", "Right", "Hub"], graph: graph),
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValuesFromEveryRoot_whenRootOffCycleEntersItAtTwoMockedTypes() async throws {
		let names = ["Alpha", "Bravo", "Charlie"]
		var fixtureFiles = Self.ring(names)
		fixtureFiles["Entry.swift"] = Self.type("Entry", building: ["Alpha", "Charlie"])
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(
			fixtureFiles: fixtureFiles,
			probes: Self.probes(aroundRing: names, laps: 4)
				+ Self.probes(from: "Entry", path: ["Alpha"] + Self.path(aroundRing: names, from: 1, steps: 5), graph: Self.graph(ofRing: names))
				+ Self.probes(from: "Entry", path: ["Charlie"] + Self.path(aroundRing: names, from: 0, steps: 5), graph: Self.graph(ofRing: names)),
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValuesFromEveryRoot_whenEveryTypeOfSendableCycleIsMocked() async throws {
		let names = ["Alpha", "Bravo", "Charlie"]
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(
			fixtureFiles: Self.ring(names, wrapper: "SendableInstantiator"),
			probes: names.indices.flatMap { index in
				Self.probes(from: names[index], path: Self.path(aroundRing: names, from: index + 1, steps: 7))
			},
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValuesFromEveryRoot_whenMockedCycleMemberReceivesValueInstantiatedAboveCycle() async throws {
		// `Top` builds `token` and enters the cycle; `Bravo`, on the cycle, receives `token`. From `Top`'s mock every lap's
		// `Bravo` holds `Top`'s token; a mock whose root is on the cycle promotes one token for every lap.
		let fixtureFiles = [
			"Marked.swift": Self.markedFile,
			"Token.swift": """
			@Instantiable
			public final class Token: Instantiable {
			    public init() {}
			}
			""",
			"Top.swift": """
			@Instantiable(generateMock: true)
			public final class Top: Instantiable {
			    public init(token: Token, alphaBuilder: Instantiator<Alpha>) {
			        self.token = token
			        self.alphaBuilder = alphaBuilder
			    }

			    @Instantiated let token: Token
			    @Instantiated let alphaBuilder: Instantiator<Alpha>
			}
			""",
			"Alpha.swift": Self.type("Alpha", building: ["Bravo"]),
			"Bravo.swift": """
			@Instantiable(generateMock: true)
			public final class Bravo: Instantiable {
			    public init(token: Token, alphaBuilder: Instantiator<Alpha>) {
			        self.token = token
			        self.alphaBuilder = alphaBuilder
			    }

			    @Received let token: Token
			    @Instantiated let alphaBuilder: Instantiator<Alpha>
			}
			""",
		]
		let graph = ["Alpha": ["Bravo"]]
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(
			fixtureFiles: fixtureFiles,
			probes: Self.probes(from: "Top", path: ["Alpha", "Bravo", "Alpha", "Bravo", "Alpha"], graph: graph)
				+ Self.probes(from: "Alpha", path: ["Bravo", "Alpha", "Bravo", "Alpha", "Bravo"])
				+ Self.probes(from: "Bravo", path: ["Alpha", "Bravo", "Alpha", "Bravo", "Alpha"], graph: graph),
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValuesFromEveryRoot_whenMockedCycleMemberReceivesValueTheMockTakesAsParameter() async throws {
		// Nothing builds a `String`, so every mock takes `name` as a parameter, which each lap's `Bravo` reads from
		// `mock()`'s own scope.
		let fixtureFiles = [
			"Marked.swift": Self.markedFile,
			"Alpha.swift": Self.type("Alpha", building: ["Bravo"]),
			"Bravo.swift": """
			@Instantiable(generateMock: true)
			public final class Bravo: Instantiable {
			    public init(name: String, charlieBuilder: Instantiator<Charlie>) {
			        self.name = name
			        self.charlieBuilder = charlieBuilder
			    }

			    @Received let name: String
			    @Instantiated let charlieBuilder: Instantiator<Charlie>
			}
			""",
			"Charlie.swift": Self.type("Charlie", building: ["Alpha"]),
		]
		let names = ["Alpha", "Bravo", "Charlie"]
		let graph = ["Alpha": ["Bravo"], "Charlie": ["Alpha"]]
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(
			fixtureFiles: fixtureFiles,
			probes: Self.probes(from: "Alpha", path: Self.path(aroundRing: names, from: 1, steps: 7), arguments: "name: \"given\"")
				+ Self.probes(from: "Bravo", path: Self.path(aroundRing: names, from: 2, steps: 7), graph: graph, arguments: "name: \"given\"")
				+ Self.probes(from: "Charlie", path: Self.path(aroundRing: names, from: 0, steps: 7), graph: graph, arguments: "name: \"given\""),
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValuesFromEveryRoot_whenMockedCycleHoldsMainActorTypeAndNonisolatedType() async throws {
		// A function that builds `Alpha` is the main actor's, and one that builds `Bravo` is not: a function shared by
		// every mock of the module would be declared outside both. `Entry` is a main actor type off the cycle.
		let fixtureFiles = [
			"Unchecked.swift": Self.uncheckedFile,
			"Entry.swift": Self.type("Entry", building: ["Alpha"], attribute: "@MainActor"),
			"Alpha.swift": Self.type("Alpha", building: ["Bravo"], attribute: "@MainActor"),
			"Bravo.swift": Self.type("Bravo", building: ["Alpha"], mockAttributes: "@MainActor"),
		]
		let onMainActor: (String) -> String = { "MainActor.assumeIsolated { Unchecked(\($0)) }.value" }
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(
			fixtureFiles: fixtureFiles,
			probes: Self.probes(from: "Entry", path: ["Alpha", "Bravo", "Alpha", "Bravo", "Alpha"], wrapping: onMainActor)
				+ Self.probes(from: "Alpha", path: ["Bravo", "Alpha", "Bravo", "Alpha", "Bravo"], wrapping: onMainActor)
				+ Self.probes(from: "Bravo", path: ["Alpha", "Bravo", "Alpha", "Bravo", "Alpha"], wrapping: onMainActor),
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compiles_whenEveryTypeOfCycleIsMockedInModuleDefaultingToMainActor() async throws {
		let names = ["Alpha", "Bravo", "Charlie"]
		let fixtureFiles = Self.ring(names)
		let (_, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [],
				swiftFileContentByFilePath: fixtureFiles,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: "MainActor"),
			)
		}

		#expect(reports.filter(\.isMockRoot).map(\.root) == names)
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true, true, true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compilesAndEqualsWalks_whenMockedCycleHoldsActor() async throws {
		// Node records refuse a mock that sends an actor a value a cycle's function builds, so the walk writes it: with
		// every type of the cycle mocked, what the other mocks share must leave it compiling.
		let fixtureFiles = [
			"Alpha.swift": Self.type("Alpha", building: ["Bravo"], wrapper: "SendableInstantiator"),
			"Bravo.swift": Self.type("Bravo", building: ["Charlie"], wrapper: "SendableInstantiator", kind: "actor"),
			"Charlie.swift": Self.type("Charlie", building: ["Alpha"], wrapper: "SendableInstantiator"),
		]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.root) == ["Alpha", "Bravo", "Charlie"])
		#expect(output.generatedFiles == walkOutput.generatedFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_releasesWhatOverrideCaptures_whenValuesBuiltAroundMockedCycleAreReleased() async throws {
		// The places a mock's functions enter hold the configurations, whose overrides capture what the caller's closures
		// capture. Once every value the mock built is released, nothing may keep a place alive.
		let names = ["Alpha", "Bravo", "Charlie"]
		let fixtureFiles = Self.ring(names)
		let (laidOut, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true, true, true])
		let printed = try await DifferentialValueOracle.output(
			of: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(laidOut.generatedFiles)),
			running: """
			final class Captured {}

			func build(_ root: String, _ make: (Captured) -> Void) {
			    weak var weakCaptured: Captured?
			    do {
			        let captured = Captured()
			        weakCaptured = captured
			        make(captured)
			    }
			    print(root, weakCaptured == nil ? "released" : "retained")
			}

			build("Alpha") { captured in
			    let alpha = Alpha.mock(safeDIOverrides: .init(bravoBuilder: .init({ _ = captured; return Bravo(charlieBuilder: $0) })))
			    _ = alpha.bravoBuilder.instantiate().charlieBuilder.instantiate().alphaBuilder.instantiate().bravoBuilder.instantiate()
			}
			build("Bravo") { captured in
			    let bravo = Bravo.mock(safeDIOverrides: .init(charlieBuilder: .init({ _ = captured; return Charlie(alphaBuilder: $0) })))
			    _ = bravo.charlieBuilder.instantiate().alphaBuilder.instantiate().bravoBuilder.instantiate().charlieBuilder.instantiate()
			}
			build("Charlie") { captured in
			    let charlie = Charlie.mock(safeDIOverrides: .init(alphaBuilder: .init({ _ = captured; return Alpha(bravoBuilder: $0) })))
			    _ = charlie.alphaBuilder.instantiate().bravoBuilder.instantiate().charlieBuilder.instantiate().alphaBuilder.instantiate()
			}
			""",
			filesToDelete: &filesToDelete,
		)

		// Nothing is printed where compile verification is disabled.
		#expect(printed ?? "Alpha released\nBravo released\nCharlie released\n" == "Alpha released\nBravo released\nCharlie released\n")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValuesFromEveryRoot_whenMockedCycleMemberCallsAnotherModulesPublicMock() async throws {
		// `Bravo`, on the cycle, holds `Feed`'s `Screen`, which `App` cannot build, so each lap's function of `Bravo` calls
		// `Screen`'s public mock, in whichever mock of `App` the function is written.
		let modules = [
			ModuleFixture(name: "Feed", packageName: "feedpkg", swiftFileContentByFilePath: [
				"Screen.swift": """
				import SafeDI

				@Instantiable
				public final class Analytics: Instantiable {
				    public init() {}
				}

				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    init(analytics: Analytics) {
				        self.analytics = analytics
				    }

				    @Instantiated let analytics: Analytics
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "apppkg", swiftFileContentByFilePath: [
				"Marked.swift": Self.markedFile,
				"Alpha.swift": "import SafeDI\n\n" + Self.type("Alpha", building: ["Bravo"]),
				"Bravo.swift": """
				import Feed
				import SafeDI

				@Instantiable(generateMock: true)
				public final class Bravo: Instantiable, Marked {
				    public init(screen: Screen, charlieBuilder: Instantiator<Charlie>) {
				        self.screen = screen
				        self.charlieBuilder = charlieBuilder
				    }

				    @Instantiated let screen: Screen
				    @Instantiated let charlieBuilder: Instantiator<Charlie>
				    public var marker = ""
				}
				""",
				"Charlie.swift": "import SafeDI\n\n" + Self.type("Charlie", building: ["Alpha"]),
			], dependencies: ["Feed"]),
		]
		let walkOutput = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let (output, _) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		let names = ["Alpha", "Bravo", "Charlie"]
		let graph = ["Alpha": ["Bravo"], "Charlie": ["Alpha"]]
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: walkOutput, modules: modules),
			probes: Self.probes(from: "Alpha", path: Self.path(aroundRing: names, from: 1, steps: 7))
				+ Self.probes(from: "Bravo", path: Self.path(aroundRing: names, from: 2, steps: 7), graph: graph)
				+ Self.probes(from: "Charlie", path: Self.path(aroundRing: names, from: 0, steps: 7), graph: graph),
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The label of the builder of the type named `name`.
	private static func label(_ name: String) -> String {
		name.prefix(1).lowercased() + name.dropFirst() + "Builder"
	}

	/// A mocked type that builds each of `built` through a builder. A type built through an `Instantiator` carries a
	/// marker an override's closure sets; one built through a `Sendable` wrapper holds only constants.
	private static func type(
		_ name: String,
		building built: [String],
		wrapper: String = "Instantiator",
		attribute: String? = nil,
		mockAttributes: String? = nil,
		kind: String = "final class",
	) -> String {
		let isSendable = wrapper != "Instantiator"
		let isMarked = !isSendable && kind == "final class" && attribute == nil && mockAttributes == nil
		let parameters = built.map { "\(label($0)): \(wrapper)<\($0)>" }.joined(separator: ", ")
		let assignments = built.map { "        self.\(label($0)) = \(label($0))" }.joined(separator: "\n")
		let properties = built.map { "    @Instantiated let \(label($0)): \(wrapper)<\($0)>" }.joined(separator: "\n")
		return """
		\(attribute.map { $0 + "\n" } ?? "")@Instantiable(\(mockAttributes.map { "mockAttributes: \"\($0)\", " } ?? "")generateMock: true)
		public \(kind) \(name): Instantiable\(isMarked ? ", Marked" : isSendable ? ", Sendable" : "") {
		    public init(\(parameters)) {
		\(assignments)
		    }

		\(properties)
		\(isMarked ? "    public var marker = \"\"" : "")
		}
		"""
	}

	/// A cycle of builders through the types named `names`, each of which builds the next and the last the first, every
	/// one of them mocked.
	private static func ring(_ names: [String], wrapper: String = "Instantiator") -> [String: String] {
		var files = ["Marked.swift": markedFile]
		for (index, name) in names.enumerated() {
			files["\(name).swift"] = type(name, building: [names[(index + 1) % names.count]], wrapper: wrapper)
		}
		return files
	}

	/// The types `steps` builders around the cycle of `names` build in turn, the first of them the one at `start`.
	private static func path(aroundRing names: [String], from start: Int, steps: Int) -> [String] {
		(0..<steps).map { names[(start + $0) % names.count] }
	}

	/// For each prefix of `path`, the types the builders from the mock of `root` build in turn, the value at its end: from
	/// the mock as it is, and, where `graph` says what each type builds, from the mock whose override of the first builder
	/// marks what it builds.
	private static func probes(
		from root: String,
		path: [String],
		graph: [String: [String]]? = nil,
		arguments mockArguments: String = "",
		wrapping wrap: (String) -> String = { $0 },
	) -> [DifferentialValueProbe] {
		var probes = [DifferentialValueProbe]()
		var expression = ""
		for (step, name) in path.enumerated() {
			expression += ".\(label(name)).instantiate()"
			probes.append(DifferentialValueProbe(name: "\(root) step \(step) to \(name)", expression: wrap("\(root).mock(\(mockArguments))\(expression)")))
			if let built = graph?[path[0]] {
				let arguments = built.enumerated().map { "\(label($1)): $\($0)" }.joined(separator: ", ")
				probes.append(DifferentialValueProbe(
					name: "\(root) overriding \(path[0]) step \(step) to \(name)",
					expression: "\(root).mock(\(mockArguments.isEmpty ? "" : mockArguments + ", ")safeDIOverrides: .init(\(label(path[0])): .init({ marked(\(path[0])(\(arguments)), \"\(root).\(path[0])\") })))\(expression)",
				))
			}
		}
		return probes
	}

	/// The probes from the mock of each type on the cycle of `names`, `laps` builders around it.
	private static func probes(aroundRing names: [String], laps: Int) -> [DifferentialValueProbe] {
		names.indices.flatMap { index in
			probes(from: names[index], path: path(aroundRing: names, from: index + 1, steps: laps), graph: graph(ofRing: names))
		}
	}

	/// What each type on the cycle of `names` builds: the next.
	private static func graph(ofRing names: [String]) -> [String: [String]] {
		var graph = [String: [String]]()
		for (index, name) in names.enumerated() {
			graph[name] = [names[(index + 1) % names.count]]
		}
		return graph
	}

	/// Runs `body` with mock roots laid out from their worlds' node records, and returns what it returns with the report of
	/// each root, sorted by root.
	private static func layingOutMockRoots<Output>(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> Output,
	) async throws -> (Output, [NodeRecordsReport]) {
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		let output = try await NodeRecordsObservation.$laysOutMockRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
				try await body(&filesMade)
			}
		}
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream {
			reports.append(report)
		}
		return (output, reports.sorted { $0.root < $1.root })
	}

	/// A box that carries a probe's value out of the main actor, which the probes' program runs on.
	private static let uncheckedFile = """
	public struct Unchecked: @unchecked Sendable {
	    public init(_ value: Any) {
	        self.value = value
	    }

	    public let value: Any
	}
	"""

	private static let markedFile = """
	public protocol Marked: AnyObject {
	    var marker: String { get set }
	}

	func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
	    value.marker = marker
	    return value
	}
	"""
}
