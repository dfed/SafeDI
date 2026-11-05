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

/// Seams under the ways a real build runs the tool that change what a seam's generated initializer is or how it is
/// called: a module run with no package name (Bazel without `package_name`, Tuist without `SWIFT_PACKAGE_NAME`), a
/// release build (Bazel's `opt` mode), and a module run with no module name (a raw `safedi_compile` without
/// `module_name`).
struct SafeDIToolSeamHarnessOptionTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Fixtures

	/// `App`'s root, which builds `Shell` through an instantiator, so that `Shell` can forward `theme: [3 of Int]`, a
	/// spelling SafeDI cannot read, which only the mentions prove.
	private static let shellForwardingTheme = """
	import Feature
	import SafeDI

	@Instantiable
	public struct Shell: Instantiable {
	    public init(theme: [3 of Int], service: Service) {
	        self.theme = theme
	        self.service = service
	    }

	    @Forwarded let theme: [3 of Int]
	    @Instantiated let service: Service
	}

	@Instantiable(isRoot: true)
	public struct Root: Instantiable {
	    public init(shellBuilder: Instantiator<Shell>) {
	        self.shellBuilder = shellBuilder
	    }

	    @Instantiated let shellBuilder: Instantiator<Shell>
	}
	"""

	// MARK: No package name

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingToPassPackages_whenCallerToldNoPackageHoldsValueTheTierItReachesOmits() async {
		// Neither module is told a package, so neither has one, and only `public` and `internal` exist: `Badge`'s
		// `internal` initializer receives `theme` only if available, so the `public` tier `App` reaches omits it, and
		// `App`'s `Shell` provides it. Built inline, `Badge` would be handed `theme`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Shell.swift"]):11:5: error: `Shell` provides `theme: [3 of Int]`, but the `public` initializer SafeDI generated for `Service` in module `Feature`, the narrowest one module `App` can call, does not take it: `Service` takes `theme` only on its `internal` initializer, so this call would pass `nil` to `Badge`, which the tree would hand `theme` were it built inline. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `internal` (`Badge.init(theme:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `Badge.init(theme:)` to `public`; mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; pass the packages of modules `App` and `Feature` to SafeDI (`package_name` on `safedi_swift_library`, `--package-name`) if they are compiled with `-package-name`; or stop providing `theme` on this path.
			\(fixtures["Feature"]!["Badge.swift"]):7:5: note: `Badge` receives `theme: [3 of Int]?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContent: [
							"""
							@Instantiable
							public struct Badge: Instantiable {
							    internal init(theme: [3 of Int]?) {
							        self.theme = theme
							    }

							    @Received(onlyIfAvailable: true) let theme: [3 of Int]?
							}
							""",
							seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
						],
						omitsPackageName: true,
					),
					ModuleFixture(
						name: "App",
						packageName: "Other",
						swiftFileContent: [Self.shellForwardingTheme],
						dependencies: ["Feature"],
						omitsPackageName: true,
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Release configuration

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesTheSameSeam_whenSeamModuleIsBuiltInReleaseConfiguration(integration: MultiModuleIntegration) async throws {
		// A `mockOnly` fake inside `#if DEBUG` is the module's only mock-only content. A release build does not
		// compile it, and the seam's generated initializer does not depend on it.
		func modules(isReleaseConfiguration: Bool) -> [ModuleFixture] {
			[
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						"""
						import SafeDI

						public protocol Analytics {}

						public struct Token {
						    public init() {}
						}

						@Instantiable(fulfillingAdditionalTypes: [Analytics.self])
						public struct ConsoleAnalytics: Analytics, Instantiable {
						    public init() {}
						}

						#if DEBUG
						@Instantiable(fulfillingAdditionalTypes: [Analytics.self], mockOnly: true)
						public struct FakeAnalytics: Analytics {
						    @Received let token: Token

						    public static func mock(token: Token) -> FakeAnalytics {
						        FakeAnalytics(token: token)
						    }
						}
						#endif
						""",
						seamFixtureType(named: "Badge", declarations: ["@Received let token: Token"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
					],
					isReleaseConfiguration: isReleaseConfiguration,
				),
				ModuleFixture(
					name: "App",
					packageName: "Other",
					swiftFileContent: [
						"""
						import Feature
						import SafeDI

						@Instantiable
						public struct Shell: Instantiable {
						    public init(token: Token, service: Service) {
						        self.token = token
						        self.service = service
						    }

						    @Forwarded let token: Token
						    @Instantiated let service: Service
						}

						@Instantiable(isRoot: true)
						public struct Root: Instantiable {
						    public init(shellBuilder: Instantiator<Shell>) {
						        self.shellBuilder = shellBuilder
						    }

						    @Instantiated let shellBuilder: Instantiator<Shell>
						}
						""",
					],
					dependencies: ["Feature"],
					isReleaseConfiguration: isReleaseConfiguration,
				),
			]
		}
		let debugOutput = try await executeSafeDIToolMultiModuleTest(modules: modules(isReleaseConfiguration: false), integration: integration, filesToDelete: &filesToDelete)
		let releaseOutput = try await executeSafeDIToolMultiModuleTest(modules: modules(isReleaseConfiguration: true), integration: integration, filesToDelete: &filesToDelete)
		let seamFile = generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Service {
		    public init(token: Token) {
		        let badge = Badge(token: token)
		        self.init(badge: badge)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_1EB503BFA23A82BA {}
		}
		"""
		switch integration {
		case .moduleInfo:
			#expect(releaseOutput.modules["Feature"]?.generatedFiles == ["Feature.swift": seamFile])
		case .swiftPackagePlugin:
			#expect(releaseOutput.modules["Feature"]?.generatedFiles["Service+SafeDI.swift"] == seamFile)
		}
		#expect(releaseOutput.modules["Feature"]?.generatedFiles == debugOutput.modules["Feature"]?.generatedFiles)
		#expect(releaseOutput.modules["App"]?.generatedFiles == debugOutput.modules["App"]?.generatedFiles)
		try expectEveryModuleCompiled(debugOutput)
		try expectEveryModuleCompiled(releaseOutput)
	}

	// MARK: No module name

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsSeamInline_whenSeamModuleRunsWithoutModuleName() async throws {
		// `Feature`'s `.safedi` names no module, so `App` cannot tell which module generated `Service`'s initializer and
		// builds `Service`'s tree itself, passing `analytics` to `Badge`, and says so where it constructs `Service`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						seamFixtureType(named: "Analytics", declarations: []),
						seamFixtureType(named: "Badge", declarations: ["@Received(onlyIfAvailable: true) let analytics: Analytics?"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
					],
					omitsModuleName: true,
				),
				ModuleFixture(
					name: "App",
					packageName: "Other",
					swiftFileContent: [
						"""
						import Feature
						import SafeDI

						@Instantiable(isRoot: true)
						public struct Root: Instantiable {
						    public init(analytics: Analytics, service: Service) {
						        self.analytics = analytics
						        self.service = service
						    }

						    @Instantiated let analytics: Analytics
						    @Instantiated let service: Service
						}
						""",
					],
					dependencies: ["Feature"],
				),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			extension Root {
			    public init() {
			        let analytics = Analytics()
			        func __safeDI_service() -> Service {
			            let badge = Badge(analytics: analytics)
			            return Service(badge: badge) // Built inline: SafeDI does not know which module declares `Service`, so this tree cannot call the initializer SafeDI generates for it.
			        }
			        let service: Service = __safeDI_service()
			        self.init(analytics: analytics, service: service)
			    }
			}
			""",
		])
		try expectEveryModuleCompiled(output)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private func expectEveryModuleCompiled(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.moduleName) == output.moduleNames, sourceLocation: sourceLocation)
		#expect(compilation.failure == nil, sourceLocation: sourceLocation)
	}
}
