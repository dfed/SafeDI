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

/// The layers of work a run of `generate` computes: the signatures of each declaration map's seams, the proof of each
/// declaration map's access, the tree of each root and seam, and each module's mock scopes. One driver computes each once and hands it down, so a run that writes
/// code, mocks and a DOT graph computes none of them twice, and a module whose public mocks the run calls builds its mock
/// scopes once for every plan the run asks of it. Counted, not timed, so that the checks are the same on every machine and every run.
struct SafeDIToolGenerationLayerTests: ~Copyable {
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
	mutating func generate_buildsEachRootsTreeOnce_whenRunWritesDOTTree() async throws {
		// The run writes code, a mock and the DOT graph. The graph is drawn from the trees the code is generated from, so
		// each root's tree is built once; a graph drawn from trees of its own would build each twice.
		var output: TestOutput?
		let layers = try await Self.countLayers {
			output = try await executeSafeDIToolTest(
				swiftFileContent: [
					seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service"]),
					"@Instantiable(generateMock: true)\npublic struct Service: Instantiable {\n    public init(store: Store) {\n        self.store = store\n    }\n\n    @Instantiated let store: Store\n}",
					seamFixtureType(named: "Store", declarations: []),
				],
				buildSwiftOutputDirectory: true,
				buildDOTFileOutput: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(layers == [
			"nil: tree of Root": 1,
			"nil: mock scopes of nil": 1,
		])
		// The graph is the one the trees drew before.
		let dotTree = try #require(output?.dotTree)
		#expect(dotTree == """
		graph SafeDI {
		    ranksep=2
		    Root -- "service: Service"
		    "service: Service" -- "store: Store"
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_computesEachLayerOnce_whenRunCallsForeignSeam() async throws {
		// `App` generates the seam `Screen` and calls `Feature`'s seam `Service`, writes a mock and the DOT graph. Each
		// module's run computes the signatures of its own seams once, reads `Service`'s from `Feature`'s module info
		// rather than computing it, and builds each tree it generates once. Each run proves its declarations' access
		// once, for its seam's signature and its public mock context alike.
		var output: MultiModuleTestOutput?
		let layers = try await Self.countLayers {
			output = try await executeSafeDIToolMultiModuleTest(
				modules: Self.foreignSeamModules,
				integration: .moduleInfo,
				writesDOTTrees: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(layers == [
			"Feature: seam signatures of Feature": 1,
			"Feature: access proof of Feature": 1,
			"Feature: tree of Service": 1,
			"App: seam signatures of App": 1,
			"App: access proof of App": 1,
			"App: tree of Root": 1,
			"App: tree of Screen": 1,
			"App: mock scopes of App": 1,
		])
		let appDOTTree = try #require(output?.modules["App"]?.dotTree)
		#expect(appDOTTree == """
		graph SafeDI {
		    ranksep=2
		    Root -- "service: Service"
		    Root -- "screen: Screen"

		    Screen -- "model: Model"
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_provesNoAccess_whenModuleCallsForeignSeamAndGeneratesNoSeamOrPublicMock() async throws {
		// `App`'s root calls `Feature`'s seam `Service`, whose signature `App` reads from `Feature`'s module info. `App`
		// generates no seam and declares no public mock, so nothing in its run reads a proof of its declarations' access.
		// Nothing forces `Root`'s tree or `Service`'s, so each run lays its root out from node records and builds no tree of it.
		let layers = try await Self.countLayers {
			_ = try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.foreignSeamModules[0],
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
						"import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service"]),
					], dependencies: ["Feature"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(layers == [
			"Feature: seam signatures of Feature": 1,
			"Feature: access proof of Feature": 1,
			"App: seam signatures of App": 1,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_computesOwnAndCallersViewSignaturesOnce_whenConfigurationAddsDirectory() async throws {
		// A directory the configuration adds is one the modules that call `Service` cannot see, so the run computes the
		// seam's signatures over its own declarations and over its callers', once each, while it also writes a mock and
		// the DOT graph.
		let layers = try await Self.countLayers {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [
					"#SafeDIConfiguration(\n    additionalDirectoriesToInclude: [\"$ADDITIONAL_DIRECTORY\"]\n)",
					seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
					"@Instantiable(generateMock: true)\npublic struct Badge: Instantiable {\n    public init() {}\n}",
				],
				additionalDirectorySwiftFileContent: [
					seamFixtureType(named: "Vault", declarations: []),
				],
				buildSwiftOutputDirectory: true,
				buildDOTFileOutput: true,
				filesToDelete: &filesToDelete,
				pluginTargetGraph: { inputSwiftFilePaths in
					PluginTargetGraph(
						target: PluginTargetGraph.Target(moduleName: "Feature", packageID: "shop", sourceFilePaths: inputSwiftFilePaths, dependencyModuleNames: []),
						dependencyTargets: [],
					)
				},
			)
		}
		#expect(layers == [
			"Feature: seam signatures of Feature": 1,
			"Feature: seam signatures of Feature in its callers’ view": 1,
			"Feature: access proof of Feature": 1,
			"Feature: access proof of Feature in its callers’ view": 1,
			"Feature: tree of Service": 1,
			"Feature: mock scopes of Feature": 1,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsEachModulesMockScopesOnce_whenRunCallsTwoPublicMocksOfForeignModule() async throws {
		// `Feature` declares the public mocks `Alpha` and `Beta`, whose trees build its internal `Store`, and its
		// configuration adds `Vendor`'s directory, which `Feature`'s callers cannot see. `Feature`'s run builds its mock
		// scopes once for its mocks, once for the plans of both public mocks, and once over its callers' view for each
		// public mock. `App`'s mock calls both public mocks, so its run computes `Feature`'s plans in one call, which builds
		// `Feature`'s mock scopes once for both. Each of those generators proves its declarations' access once: `Feature`'s
		// run over its own and over its callers' view for each public mock, and `App`'s run over its own and `Feature`'s.
		let layers = try await Self.countLayers {
			_ = try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Vendor", packageName: "vendor", swiftFileContent: [seamFixtureType(named: "Vault", declarations: [])], isCheckoutPackage: true),
					ModuleFixture(
						name: "Feature",
						packageName: "shop",
						swiftFileContent: [
							Self.publicMockType(named: "Alpha"),
							Self.publicMockType(named: "Beta"),
							"@Instantiable\nstruct Store: Instantiable {\n    init() {}\n}",
						],
						swiftFileContentByFilePath: ["SafeDIConfiguration.swift": "#SafeDIConfiguration(additionalDirectoriesToInclude: [\"$FIXTURE_ROOT/checkouts/vendor/Sources/Vendor\"])"],
						dependencies: ["Vendor"],
					),
					ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
						"import Feature\n\n@Instantiable(generateMock: true)\npublic struct Screen: Instantiable {\n    public init(alpha: Alpha, beta: Beta) {\n        self.alpha = alpha\n        self.beta = beta\n    }\n\n    @Instantiated let alpha: Alpha\n    @Instantiated let beta: Beta\n}",
					], dependencies: ["Feature"]),
				],
				integration: .swiftPackagePlugin,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(layers == [
			"Feature: mock scopes of Feature": 4,
			"Feature: access proof of Feature": 3,
			"App: mock scopes of App": 1,
			"App: mock scopes of Feature": 1,
			"App: access proof of App": 1,
			"App: access proof of Feature": 1,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsNoOtherModulesMockScopes_whenModuleInfosCarryPublicMockPlans() async throws {
		// `Feature` declares the public mocks `Alpha` and `Beta`, `Flow` a public mock `Step` whose tree calls both, and
		// `App` a mock whose tree calls `Step`. Each module's run builds its own mock scopes once, writes the plan of each
		// of its public mocks into its module info, and reads the plans of the public mocks it calls from the module infos
		// it is given, so no run builds another module's mock scopes, however many modules lie beneath it.
		var output: MultiModuleTestOutput?
		let layers = try await Self.countLayers {
			output = try await executeSafeDIToolMultiModuleTest(
				modules: Self.publicMockChainModules(),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(layers == [
			"Feature: mock scopes of Feature": 1,
			"Feature: access proof of Feature": 1,
			"Flow: mock scopes of Flow": 1,
			"Flow: access proof of Flow": 1,
			"App: mock scopes of App": 1,
			"App: access proof of App": 1,
		])
		#expect(try output?.modules["Feature"]?.moduleInfoFile?.publicMockPlans.decoded.map(\.mockedType.asSource) == ["Alpha", "Beta"])
		#expect(try output?.modules["Flow"]?.moduleInfoFile?.publicMockPlans.decoded.map(\.mockedType.asSource) == ["Step"])
		#expect(output?.modules["App"]?.moduleInfoFile?.publicMockPlans.isEmpty == true)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesSameCode_whenModuleInfosCarryNoPublicMockPlans() async throws {
		// The same modules, whose module infos are rewritten without the plans and signatures they carry: each run
		// computes the plan of every public mock it calls, building the mock scopes of each module beneath it, and
		// generates the code the runs that read stored plans generate.
		let stored = try await executeSafeDIToolMultiModuleTest(
			modules: Self.publicMockChainModules(),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		var computed: MultiModuleTestOutput?
		let layers = try await Self.countLayers {
			computed = try await executeSafeDIToolMultiModuleTest(
				modules: Self.publicMockChainModules(),
				integration: .moduleInfo,
				discardsStoredSeamSignatures: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(layers == [
			"Feature: mock scopes of Feature": 1,
			"Feature: access proof of Feature": 1,
			"Flow: mock scopes of Flow": 1,
			"Flow: mock scopes of Feature": 1,
			"Flow: access proof of Flow": 1,
			"Flow: access proof of Feature": 1,
			"App: mock scopes of App": 1,
			"App: mock scopes of Flow": 1,
			"App: mock scopes of Feature": 1,
			"App: access proof of App": 1,
			"App: access proof of Flow": 1,
			"App: access proof of Feature": 1,
		])
		for moduleName in stored.moduleNames {
			#expect(computed?.modules[moduleName]?.generatedFiles == stored.modules[moduleName]?.generatedFiles, "\(moduleName) generates other code from stored plans")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_computesPublicMockPlans_whenRunCompilesNoMocksAndDeclaringModulesRunCompiledThem() async throws {
		// A plan depends on whether its run compiles the mocks it generates. `Feature`'s and `Flow`'s runs do, since their
		// builds report `DEBUG`, and `App`'s, which does not, compiles none: it reads neither module's plans and computes
		// them. `Flow`, built as `Feature` is, reads `Feature`'s.
		let layers = try await Self.countLayers {
			_ = try await executeSafeDIToolMultiModuleTest(
				modules: Self.publicMockChainModules(conditionsOfModulesBeneathApp: ["DEBUG"]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(layers == [
			"Feature: mock scopes of Feature": 1,
			"Feature: access proof of Feature": 1,
			"Flow: mock scopes of Flow": 1,
			"Flow: access proof of Flow": 1,
			"App: mock scopes of App": 1,
			"App: mock scopes of Flow": 1,
			"App: mock scopes of Feature": 1,
			"App: access proof of App": 1,
			"App: access proof of Flow": 1,
			"App: access proof of Feature": 1,
		])
	}

	// MARK: Private

	/// A type named `name` with a public mock, whose tree builds `Feature`'s internal `Store`.
	private static func publicMockType(named name: String) -> String {
		"@Instantiable(generateMock: .public)\npublic struct \(name): Instantiable {\n    init(store: Store) {\n        self.store = store\n    }\n\n    @Instantiated let store: Store\n}"
	}

	private var filesToDelete: [URL]

	/// `Feature` (package `shop`), which declares the public mocks `Alpha` and `Beta`; `Flow` (package `flow`), whose public
	/// mock `Step` builds both; and `App` (package `app`), whose mock of `Screen` builds `Step`.
	private static func publicMockChainModules(conditionsOfModulesBeneathApp: [String] = []) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "shop", swiftFileContent: [
				publicMockType(named: "Alpha"),
				publicMockType(named: "Beta"),
				"@Instantiable\nstruct Store: Instantiable {\n    init() {}\n}",
			], activeCompilationConditions: conditionsOfModulesBeneathApp),
			ModuleFixture(name: "Flow", packageName: "flow", swiftFileContent: [
				"import Feature\n\n@Instantiable(generateMock: .public)\npublic struct Step: Instantiable {\n    init(alpha: Alpha, beta: Beta, log: Log) {\n        self.alpha = alpha\n        self.beta = beta\n        self.log = log\n    }\n\n    @Instantiated let alpha: Alpha\n    @Instantiated let beta: Beta\n    @Instantiated let log: Log\n}",
				"@Instantiable\nstruct Log: Instantiable {\n    init() {}\n}",
			], dependencies: ["Feature"], activeCompilationConditions: conditionsOfModulesBeneathApp),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
				"import Flow\n\n@Instantiable(generateMock: true)\npublic struct Screen: Instantiable {\n    public init(step: Step) {\n        self.step = step\n    }\n\n    @Instantiated let step: Step\n}",
			], dependencies: ["Flow"]),
		]
	}

	/// `Feature` (package `Shop`), which declares the seam `Service`, and `App` (package `Other`), whose root builds
	/// `Service` and the seam `Screen` that `App` declares, with a mock of `Model`.
	private static let foreignSeamModules = [
		ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let store: Store"]),
			seamFixtureType(named: "Store", declarations: []),
		]),
		ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service", "@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let model: Model"]),
			"@Instantiable(generateMock: true)\npublic struct Model: Instantiable {\n    public init() {}\n}",
		].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
	]

	/// How many times the runs `body` makes compute each layer, by the module of the run and the layer.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func countLayers(_ body: () async throws -> Void) async throws -> [String: Int] {
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		try await GenerationLayerObservation.$observer.withValue(TaskLocalFunction { runModuleName, layer in
			let layerDescription = switch layer {
			case let .seamSignatures(moduleName, inCallersView):
				"seam signatures of \(moduleName ?? "nil")\(inCallersView ? " in its callers’ view" : "")"
			case let .accessProof(moduleName, inCallersView):
				"access proof of \(moduleName ?? "nil")\(inCallersView ? " in its callers’ view" : "")"
			case let .dependencyTree(type):
				"tree of \(type.asSource)"
			case let .inlineTreeOfForeignSeam(type):
				"inline tree of seam \(type.asSource)"
			case let .mockScopes(moduleName):
				"mock scopes of \(moduleName ?? "nil")"
			}
			continuation.yield("\(runModuleName ?? "nil"): \(layerDescription)")
		}) {
			try await body()
		}
		continuation.finish()
		var layers = [String: Int]()
		for await layer in stream {
			layers[layer, default: 0] += 1
		}
		return layers
	}
}
