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
@testable import SafeDITool

/// A module whose build reads another module's files generates a root that module declares only when the root's tree
/// constructs `public` and `open` declarations alone and calls no initializer SafeDI generates for a seam: each module
/// calls the tier of a seam it can reach, so a copy generated outside the root's module could pass a receiver `nil`
/// where the root's module passes a value. A seam SafeDI cannot name is built inline, and is judged as any other tree.
struct SafeDIToolSeamForeignRootTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: A dependency's root whose tree calls a seam

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_leavesDependencysRootWithoutCode_whenItsTreeCallsSeamWhoseReceiversInitializerIsInternal(seam: Bool) async throws {
		// `Detail`'s internal initializer receives `logger` only if available. `Logger` is `public`, so `Screen`'s one
		// tier takes it, but `App` still leaves the root to `Feature`, which declares it: its tree calls the initializer
		// `Feature` generates. Inline, the root's tree constructs the internal initializer, so `App` withholds it for
		// that.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.featureModule(seam: seam, detailInitializerIsPublic: false)),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [Self.appRoot], dependencies: ["Feature"]),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		if seam {
			#expect(output.modules["Feature"]?.generatedFiles == [
				"FeatureRoot+SafeDI.swift": generatedFileHeader + """
				extension FeatureRoot {
				    public init() {
				        let logger = Logger()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_5F3FDE2D827DABB3.self
				            return Screen(logger: logger)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(logger: logger, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public init(logger: Logger? = nil) {
				        let detail = Detail(logger: logger)
				        self.init(detail: detail)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_5F3FDE2D827DABB3 {}
				}
				""",
			])
			#expect(output.modules["App"]?.generatedFiles == [
				"FeatureRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				// SafeDI generates the dependency tree of FeatureRoot only in the module that declares it, because the tree calls the initializer SafeDI generates for Screen.
				""",
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif


				""",
			])
		} else {
			#expect(output.modules["Feature"]?.generatedFiles == [
				"FeatureRoot+SafeDI.swift": generatedFileHeader + """
				extension FeatureRoot {
				    public init() {
				        let logger = Logger()
				        func __safeDI_screen() -> Screen {
				            let detail = Detail(logger: logger)
				            return Screen(detail: detail)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(logger: logger, screen: screen)
				    }
				}
				""",
			])
			#expect(output.modules["App"]?.generatedFiles == [
				"FeatureRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				// SafeDI generates the dependency tree of FeatureRoot only in the module that declares it, because the tree constructs a declaration that is neither `public` nor `open`.
				""",
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif


				""",
			])
		}
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_leavesDependencysRootWithoutCode_whenItsTreeCallsSeamWithOnePublicTier(seam: Bool) async throws {
		// Every declaration is public, so `Screen` has one tier, which `App` could call as `Feature` does; the root is
		// still left to `Feature`. Inline, `App` regenerates it, constructing public declarations alone.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.featureModule(seam: seam, detailInitializerIsPublic: true)),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [Self.appRoot], dependencies: ["Feature"]),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		if seam {
			#expect(output.modules["Feature"]?.generatedFiles == [
				"FeatureRoot+SafeDI.swift": generatedFileHeader + """
				extension FeatureRoot {
				    public init() {
				        let logger = Logger()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_5F3FDE2D827DABB3.self
				            return Screen(logger: logger)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(logger: logger, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public init(logger: Logger? = nil) {
				        let detail = Detail(logger: logger)
				        self.init(detail: detail)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_5F3FDE2D827DABB3 {}
				}
				""",
			])
			#expect(output.modules["App"]?.generatedFiles == [
				"FeatureRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				// SafeDI generates the dependency tree of FeatureRoot only in the module that declares it, because the tree calls the initializer SafeDI generates for Screen.
				""",
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif


				""",
			])
		} else {
			#expect(output.modules["Feature"]?.generatedFiles == [
				"FeatureRoot+SafeDI.swift": generatedFileHeader + """
				extension FeatureRoot {
				    public init() {
				        let logger = Logger()
				        func __safeDI_screen() -> Screen {
				            let detail = Detail(logger: logger)
				            return Screen(detail: detail)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(logger: logger, screen: screen)
				    }
				}
				""",
			])
			#expect(output.modules["App"]?.generatedFiles == [
				"FeatureRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension FeatureRoot {
				    public init() {
				        let logger = Logger()
				        func __safeDI_screen() -> Screen {
				            let detail = Detail(logger: logger)
				            return Screen(detail: detail)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(logger: logger, screen: screen)
				    }
				}
				""",
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif


				""",
			])
		}
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_leavesDependencysRootWithoutCode_whenItsTreeCallsThirdModulesSeam(seam: Bool) async throws {
		// `Core`'s `Screen` takes the public `logger` on its one tier, which `Detail`'s package initializer receives
		// only if available, and `Feature` calls it; `App`, of another package, leaves `Feature`'s root to `Feature`.
		let core = Self.featureModule(seam: seam, detailInitializerIsPublic: false)
			.filter { !$0.contains("struct FeatureRoot") }
			.map { $0.replacingOccurrences(of: "    init(logger: Logger?)", with: "    package init(logger: Logger?)") }
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: core),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: ["import Core\n\n" + Self.featureRoot(declarations: ["@Instantiated let logger: Logger", "@Instantiated let screen: Screen"])], dependencies: ["Core"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [Self.appRoot], dependencies: ["Feature"]),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		if seam {
			#expect(output.modules["Core"]?.generatedFiles == [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public init(logger: Logger? = nil) {
				        let detail = Detail(logger: logger)
				        self.init(detail: detail)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_5F3FDE2D827DABB3 {}
				}
				""",
			])
			#expect(output.modules["Feature"]?.generatedFiles == [
				"FeatureRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif

				extension FeatureRoot {
				    public init() {
				        let logger = Logger()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_5F3FDE2D827DABB3.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(logger: logger)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(logger: logger, screen: screen)
				    }
				}
				""",
			])
			#expect(output.modules["App"]?.generatedFiles == [
				"FeatureRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif
				#if canImport(Feature)
				import Feature
				#endif

				// SafeDI generates the dependency tree of FeatureRoot only in the module that declares it, because the tree calls the initializer SafeDI generates for Screen.
				""",
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif
				#if canImport(Feature)
				import Feature
				#endif


				""",
			])
		} else {
			#expect(output.modules["Core"]?.generatedFiles == [:])
			#expect(output.modules["Feature"]?.generatedFiles == [
				"FeatureRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif

				extension FeatureRoot {
				    public init() {
				        let logger = Logger()
				        func __safeDI_screen() -> Screen {
				            let detail = Detail(logger: logger)
				            return Screen(detail: detail)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(logger: logger, screen: screen)
				    }
				}
				""",
			])
			#expect(output.modules["App"]?.generatedFiles == [
				"FeatureRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif
				#if canImport(Feature)
				import Feature
				#endif

				// SafeDI generates the dependency tree of FeatureRoot only in the module that declares it, because the tree constructs a declaration that is neither `public` nor `open`.
				""",
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif
				#if canImport(Feature)
				import Feature
				#endif


				""",
			])
		}
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: [
		["@Instantiated let logger: Logger", "@Instantiated let screenBuilder: Instantiator<Screen>"],
		["@Instantiated let logger: Logger", "@Instantiated let panel: Panel"],
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_leavesDependencysRootWithoutCode_whenSeamIsCalledInsideBuilderOrBeneathChild(rootDeclarations: [String]) async throws {
		// The walk that finds a seam call follows every instantiated property, a wrapper's included, down the tree.
		let feature = Self.featureModule(seam: true, detailInitializerIsPublic: true).filter { !$0.contains("struct FeatureRoot") }
			+ [Self.featureRoot(declarations: rootDeclarations), seamFixtureType(named: "Panel", declarations: ["@Instantiated let screen: Screen"])]
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [Self.appRoot], dependencies: ["Feature"]),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles["FeatureRoot+SafeDI.swift"] == generatedFileHeader + Self.importBlock("Feature") + "\n\n" + """
		// SafeDI generates the dependency tree of FeatureRoot only in the module that declares it, because the tree calls the initializer SafeDI generates for Screen.
		""")
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesFirstSeamTreeCalls_whenDependencysRootCallsSixSeamsUnderAnyTypeNames() async throws {
		// The root instantiates a plain `Hub` first, whose tree calls one seam, then five seams as siblings: the comment
		// names the seam met first in a declaration-order depth-first walk – the one beneath `Hub`, declared after its
		// siblings in type-name order on most permutations – never the first by name, by file, or breadth first.
		let names = ["Bravo", "Echo", "Alpha", "Foxtrot", "Delta", "Charlie"]
		for rotation in 0..<12 {
			let rotated = Array(names[(rotation % 6)...] + names[..<(rotation % 6)])
			let permutation = rotation < 6 ? rotated : rotated.reversed()
			let (nested, first, second, third, fourth, fifth) = (permutation[0], permutation[1], permutation[2], permutation[3], permutation[4], permutation[5])
			let seams = permutation.map { seamFixtureType(named: $0, isSeam: true, declarations: ["@Instantiated let detail: Detail"]) }
			let feature = Self.featureModule(seam: false, detailInitializerIsPublic: true).filter { !$0.contains("struct FeatureRoot") && !$0.contains("struct Screen") }
				+ [
					Self.featureRoot(declarations: ["@Instantiated let logger: Logger", "@Instantiated let hub: Hub"] + [first, second, third, fourth, fifth].map { "@Instantiated let \($0.lowercased()): \($0)" }),
					seamFixtureType(named: "Hub", declarations: ["@Instantiated let \(nested.lowercased()): \(nested)"]),
				] + seams
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [Self.appRoot], dependencies: ["Feature"]),
				],
				integration: .swiftPackagePlugin,
				filesToDelete: &filesToDelete,
			)
			#expect(output.modules["App"]?.generatedFiles["FeatureRoot+SafeDI.swift"] == generatedFileHeader + Self.importBlock("Feature") + "\n\n" + """
			// SafeDI generates the dependency tree of FeatureRoot only in the module that declares it, because the tree calls the initializer SafeDI generates for \(nested).
			""")
			try expectEveryModuleCompiled(output)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_regeneratesDependencysRoot_whenItsTreeCallsNoSeamOfModuleThatDeclaresOne() async throws {
		// `Feature` declares a seam `FeatureRoot`'s tree does not reach, and every declaration is public, so `App`
		// regenerates the root as `Feature` does.
		let feature = Self.featureModule(seam: false, detailInitializerIsPublic: true)
			+ [seamFixtureType(named: "Widget", isSeam: true, declarations: ["@Instantiated let gauge: Gauge"]), seamFixtureType(named: "Gauge", declarations: [])]
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [Self.appRoot], dependencies: ["Feature"]),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles["FeatureRoot+SafeDI.swift"] == generatedFileHeader + Self.importBlock("Feature") + "\n\n" + """
		extension FeatureRoot {
		    public init() {
		        let logger = Logger()
		        func __safeDI_screen() -> Screen {
		            let detail = Detail(logger: logger)
		            return Screen(detail: detail)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(logger: logger, screen: screen)
		    }
		}
		""")
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesNoDependencysRoot_whenModulesAreReadFromModuleInfo() async throws {
		// A `.safedi` file carries no root to regenerate: `App`'s combined output holds its own root alone.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.featureModule(seam: true, detailInitializerIsPublic: false)),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [Self.appRoot], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif


			""",
		])
		try expectEveryModuleCompiled(output)
	}

	// MARK: A seam SafeDI cannot name

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_judgesRootThroughSeamOfAdditionalDirectoryAsInline_whenModuleNamesNoSeamModule(detailInitializerIsPublic: Bool) async throws {
		// `Feature`'s files are in a directory `App`'s configuration adds, so no module generates `Screen`'s initializer
		// and `App` builds its tree inline, saying so where it constructs `Screen`: `FeatureRoot` is regenerated when
		// every construction is public, and left with the non-public comment otherwise, as without the seam.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				#SafeDIConfiguration(
				    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
				)
				""",
				Self.appRoot.replacingOccurrences(of: "import Feature\n\n", with: ""),
			],
			additionalDirectorySwiftFileContent: Self.featureModule(seam: true, detailInitializerIsPublic: detailInitializerIsPublic),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "App"],
		)
		if detailInitializerIsPublic {
			#expect(output.dependencyTreeFiles == [
				"FeatureRoot+SafeDI.swift": generatedFileHeader + """
				extension FeatureRoot {
				    public init() {
				        let logger = Logger()
				        func __safeDI_screen() -> Screen {
				            let detail = Detail(logger: logger)
				            return Screen(detail: detail) // Built inline: SafeDI does not know which module declares `Screen`, so this tree cannot call the initializer SafeDI generates for it.
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(logger: logger, screen: screen)
				    }
				}
				""",
				"Root+SafeDI.swift": generatedFileHeader,
			])
		} else {
			#expect(output.dependencyTreeFiles == [
				"FeatureRoot+SafeDI.swift": generatedFileHeader + """
				// SafeDI generates the dependency tree of FeatureRoot only in the module that declares it, because the tree constructs a declaration that is neither `public` nor `open`.
				""",
				"Root+SafeDI.swift": generatedFileHeader,
			])
		}
	}

	// MARK: A seam of a module no module name or target graph names

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsDependencysSeamInline_whenOwnFilesAreMockScopedWithoutTargetGraph(scansDuringGenerate: Bool) async throws {
		// `App`'s CSV lists `Feature`'s files, and the module's own files are the mock-scoped ones alone, as `scan` plans
		// a seam's output for a mock-scoped file alone: `Feature`'s seam is no seam `App` generates, and with no module
		// name or target graph its module is unknown, so `App` builds its tree inline, saying so where it constructs
		// `Screen`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.featureModule(seam: true, detailInitializerIsPublic: true).filter { !$0.contains("struct FeatureRoot") }),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let logger: Logger", "@Instantiated let screen: Screen"])],
					dependencies: ["Feature"],
				),
			],
			integration: .swiftPackagePlugin,
			writesTargetGraph: false,
			scansDuringGenerate: scansDuringGenerate,
			filesToDelete: &filesToDelete,
		)
		if scansDuringGenerate {
			#expect(output.modules["Feature"]?.generatedFiles == [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public init(logger: Logger? = nil) {
				        let detail = Detail(logger: logger)
				        self.init(detail: detail)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_5F3FDE2D827DABB3 {}
				}
				""",
			])
			#expect(output.modules["App"]?.generatedFiles == [
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public init() {
				        let logger = Logger()
				        func __safeDI_screen() -> Screen {
				            let detail = Detail(logger: logger)
				            return Screen(detail: detail) // Built inline: SafeDI does not know which module declares `Screen`, so this tree cannot call the initializer SafeDI generates for it.
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(logger: logger, screen: screen)
				    }
				}
				""",
			])
		} else {
			#expect(output.modules["Feature"]?.generatedFiles == [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public init(logger: Logger? = nil) {
				        let detail = Detail(logger: logger)
				        self.init(detail: detail)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_5F3FDE2D827DABB3 {}
				}
				""",
			])
			#expect(output.modules["App"]?.generatedFiles == [
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public init() {
				        let logger = Logger()
				        func __safeDI_screen() -> Screen {
				            let detail = Detail(logger: logger)
				            return Screen(detail: detail) // Built inline: SafeDI does not know which module declares `Screen`, so this tree cannot call the initializer SafeDI generates for it.
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(logger: logger, screen: screen)
				    }
				}
				""",
			])
		}
		try expectEveryModuleCompiled(output)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `App`'s root, which instantiates nothing of `Feature`.
	private static let appRoot = """
	import Feature

	@Instantiable(isRoot: true)
	final class Root: Instantiable {
	    init() {}
	}
	"""

	/// `Feature`'s public `Logger`; `Detail`, whose initializer is internal unless `detailInitializerIsPublic`, which
	/// receives `logger` only if available; `Screen`, a seam when `seam`, which instantiates `Detail`; and the root
	/// `FeatureRoot`, which instantiates `logger` and `Screen`.
	private static func featureModule(seam: Bool, detailInitializerIsPublic: Bool) -> [String] {
		[
			seamFixtureType(named: "Logger", declarations: []),
			"""
			@Instantiable
			public struct Detail: Instantiable {
			    \(detailInitializerIsPublic ? "public " : "")init(logger: Logger?) {
			        self.logger = logger
			    }

			    @Received(onlyIfAvailable: true) let logger: Logger?
			}
			""",
			seamFixtureType(named: "Screen", isSeam: seam, declarations: ["@Instantiated let detail: Detail"]),
			featureRoot(declarations: ["@Instantiated let logger: Logger", "@Instantiated let screen: Screen"]),
		]
	}

	/// The public root `FeatureRoot` with `declarations`.
	private static func featureRoot(declarations: [String]) -> String {
		seamFixtureType(named: "FeatureRoot", isRoot: true, declarations: declarations)
	}

	private static func importBlock(_ moduleName: String) -> String {
		"""
		#if canImport(\(moduleName))
		import \(moduleName)
		#endif
		"""
	}

	/// Expects every module to have compiled, when compile verification runs.
	private func expectEveryModuleCompiled(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 }, sourceLocation: sourceLocation)
	}
}
