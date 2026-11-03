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

/// How the check that every construction compiles in the module that emits it meets seams: a module that knows a seam
/// generates each construction in a world where the seam is called, so what it says about each construction – the
/// comment where `package` access is assumed, the error where no tier can be reached – is said about that world.
struct SafeDIToolSeamAccessTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: The comment where package access is assumed

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assumesPackageAccessWithComment_whenCallingModuleDeclaresSeamWithoutTargetGraph() async throws {
		// `App` declares a seam, so it generates in the world where seams are called; `Feature`'s `Service` is still
		// constructed with the comment, since without the target graph the tool cannot tell which module declares it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [Self.packageService]),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContent: [
						Self.appRoot(declarations: ["@Instantiated let service: Service", "@Instantiated let panel: Panel"]),
						seamFixtureType(named: "Panel", isSeam: true, declarations: ["@Instantiated let gauge: Gauge"]),
						seamFixtureType(named: "Gauge", declarations: []),
					],
					dependencies: ["Feature"],
				),
			],
			integration: .swiftPackagePlugin,
			writesTargetGraph: false,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"Panel+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Panel {
			    public init() {
			        let gauge = Gauge()
			        self.init(gauge: gauge)
			    }
			}

			extension Panel {
			    public enum __safeDI_Panel_CBF29CE484222325 {}
			}
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        let service = Service() // SafeDI could not verify that Service is in this package; `package` access is assumed.
			        func __safeDI_panel() -> Panel {
			            _ = Panel.__safeDI_Panel_CBF29CE484222325.self
			            return Panel()
			        }
			        let panel: Panel = __safeDI_panel()
			        self.init(service: service, panel: panel)
			    }
			}
			""",
		])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assumesPackageAccessWithComment_whenOnlyDependencyDeclaresSeamWithoutPackageNames() async throws {
		// `Feature` declares a seam no tree reaches, which `App` knows from `Feature`'s module info, so `App` generates in
		// the world where seams are called; without package names, its construction of `Service` keeps the comment.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						Self.packageService,
						seamFixtureType(named: "Widget", isSeam: true, declarations: ["@Instantiated let gauge: Gauge"]),
						seamFixtureType(named: "Gauge", declarations: []),
					],
					omitsPackageName: true,
				),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContent: [Self.appRoot(declarations: ["@Instantiated let service: Service"])],
					dependencies: ["Feature"],
					omitsPackageName: true,
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

			extension Root {
			    public convenience init() {
			        let service = Service() // SafeDI could not verify that Service is in this package; `package` access is assumed.
			        self.init(service: service)
			    }
			}
			""",
		])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assumesPackageAccessWithComment_whenCallingPackageTierOfDependencysSeamWithoutPackageNames(seam: Bool) async throws {
		// `Panel`'s own initializer is `package`, so its one tier is: `App` calls it with the comment, as inline it
		// constructs `Panel` with the comment.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						Self.packageService,
						seamFixtureType(named: "Engine", isFinalClass: true, declarations: []),
						"""
						@Instantiable\(seam ? "(generateDependencyTree: true)" : "")
						public struct Panel: Instantiable {
						    package init(service: Service, engine: Engine) {
						        self.service = service
						        self.engine = engine
						    }

						    @Received let service: Service
						    @Instantiated let engine: Engine
						}
						""",
					],
					omitsPackageName: true,
				),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContent: [Self.appRoot(declarations: ["@Instantiated let service: Service", "@Instantiated let panel: Panel"])],
					dependencies: ["Feature"],
					omitsPackageName: true,
				),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		if seam {
			#expect(output.modules["App"]?.generatedFiles == [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        let service = Service() // SafeDI could not verify that Service is in this package; `package` access is assumed.
				        func __safeDI_panel() -> Panel {
				            _ = Panel.__safeDI_Panel_F0C17F5BF000CB21.self
				            return Panel(service: service) // SafeDI could not verify that Panel is in this package; `package` access is assumed.
				        }
				        let panel: Panel = __safeDI_panel()
				        self.init(service: service, panel: panel)
				    }
				}
				""",
			])
		} else {
			#expect(output.modules["App"]?.generatedFiles == [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public convenience init() {
				        let service = Service() // SafeDI could not verify that Service is in this package; `package` access is assumed.
				        func __safeDI_panel() -> Panel {
				            let engine = Engine()
				            return Panel(service: service, engine: engine) // SafeDI could not verify that Panel is in this package; `package` access is assumed.
				        }
				        let panel: Panel = __safeDI_panel()
				        self.init(service: service, panel: panel)
				    }
				}
				""",
			])
		}
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assumesPackageAccessWithComment_whenCallerWithoutPackageNameCallsPackageTierOfSeamInNamedPackage() async throws {
		// `Feature`, in package `Shop`, generates `Service` with a `public` tier and a `package` one that passes `theme`,
		// which `Badge`'s `package` initializer receives. `App` runs with its module's name and no package name, so
		// `package` access is assumed of `Feature`'s declarations: `App` calls the `package` tier, and says so on the
		// line, as it does where it constructs a `package` declaration inline. `App` is compiled in `Shop`, so the call
		// compiles; were it not, the compiler would report the `package` initializer the comment names.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						"""
						public struct Theme {
						    public init() {}
						}
						""",
						"""
						@Instantiable
						public struct Badge: Instantiable {
						    package init(theme: Theme?) {
						        self.theme = theme
						    }

						    @Received(onlyIfAvailable: true) let theme: Theme?
						}
						""",
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
					],
				),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContent: [
						"""
						import Feature

						@Instantiable
						public struct Shell: Instantiable {
						    public init(theme: Theme, service: Service) {
						        self.theme = theme
						        self.service = service
						    }

						    @Forwarded let theme: Theme
						    @Instantiated let service: Service
						}
						""",
						Self.appRoot(declarations: ["@Instantiated let shellBuilder: Instantiator<Shell>"]),
					],
					dependencies: ["Feature"],
					omitsPackageName: true,
				),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			extension Service {
			    public init() {
			        self.init(theme: nil)
			    }

			    package init(theme: Theme? = nil) {
			        let badge = Badge(theme: theme)
			        self.init(badge: badge)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_27F6F01DC5D0EF8E {}
			}
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_shellBuilder(theme: Theme) -> Shell {
			            func __safeDI_service() -> Service {
			                _ = Service.__safeDI_Service_27F6F01DC5D0EF8E.self
			                return Service(theme: theme) // SafeDI could not verify that Service is in this package; `package` access is assumed.
			            }
			            let service: Service = __safeDI_service()
			            return Shell(theme: theme, service: service)
			        }
			        let shellBuilder = Instantiator<Shell> {
			            __safeDI_shellBuilder(theme: $0)
			        }
			        self.init(shellBuilder: shellBuilder)
			    }
			}
			""",
		])
		try expectEveryModuleCompiled(output)
	}

	// MARK: A caller that reaches no tier

	@Test(arguments: MultiModuleIntegration.allCases, [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtSeamsOwnInitializer_whenCallerReachesNoTier(integration: MultiModuleIntegration, seam: Bool) async {
		// `Screen`'s own initializer is internal, so its one tier is: `App`, in another package, reaches none, and the
		// error is at that initializer, with its fix-it, as where the tree is built inline.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let screenPath = Self.declarationPath(of: "Screen.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(screenPath):3:5: error: `Screen`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(screenPath):3:5-3:5: fixit: public\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContent: [
							"""
							@Instantiable\(seam ? "(generateDependencyTree: true)" : "")
							public struct Screen: Instantiable {
							    init(detail: Detail) {
							        self.detail = detail
							    }

							    @Instantiated let detail: Detail
							}
							""",
							seamFixtureType(named: "Detail", declarations: []),
						],
					),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [Self.appRoot(declarations: ["@Instantiated let screen: Screen"])], dependencies: ["Feature"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases, [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtEachInitializerCappingTier_whenCallerReachesNoTierOfSeamWhoseReceiverRequiresParameter(integration: MultiModuleIntegration, seam: Bool) async {
		// `Screen`'s own initializer and `Reader`'s, which requires `token`, are `package`, so the one tier is: `App`, in
		// another package, reaches none. With the seam, `Reader` alone is reported, with its fix-it: widening `Screen`'s
		// initializer alone would make the seam report an omission, while the public tier a widened `Reader` gives
		// calls `Screen`'s package initializer inside `Feature`. Inline reports both initializers, each with its fix-it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let readerPath = Self.declarationPath(of: "Reader.swift", in: "Feature", fixtures: fixtures, under: integration)
			let screenPath = Self.declarationPath(of: "Screen.swift", in: "Feature", fixtures: fixtures, under: integration)
			return seam ? """
			\(readerPath):3:5: error: `Reader`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(readerPath):3:5-3:12: fixit: public
			""" : """
			\(readerPath):3:5: error: `Reader`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(readerPath):3:5-3:12: fixit: public
			\(screenPath):3:5: error: `Screen`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(screenPath):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContent: [
							"""
							@Instantiable\(seam ? "(generateDependencyTree: true)" : "")
							public struct Screen: Instantiable {
							    package init(reader: Reader) {
							        self.reader = reader
							    }

							    @Instantiated let reader: Reader
							}
							""",
							"""
							@Instantiable
							public struct Reader: Instantiable {
							    package init(token: Token) {
							        self.token = token
							    }

							    @Received let token: Token
							}
							""",
							seamFixtureType(named: "Token", declarations: []),
						],
					),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [Self.appRoot(declarations: ["@Instantiated let token: Token", "@Instantiated let screen: Screen"])], dependencies: ["Feature"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Feature`'s `package` `Service`.
	private static let packageService = """
	@Instantiable
	package final class Service: Instantiable {
	    package init() {}
	}
	"""

	/// `App`'s internal root, which imports `Feature` and declares `declarations`.
	private static func appRoot(declarations: [String]) -> String {
		let properties = declarations.map { declaration in
			let property = declaration[declaration.range(of: " let ")!.upperBound...]
			return (label: String(property.prefix { $0 != ":" }), type: property.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces))
		}
		return """
		import Feature

		@Instantiable(isRoot: true)
		final class Root: Instantiable {
		    init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {
		\(properties.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n"))
		    }

		\(declarations.map { "    \($0)" }.joined(separator: "\n"))
		}
		"""
	}

	/// The path of `fileName` in `moduleName`, as a diagnostic spells it under `integration`.
	private static func declarationPath(of fileName: String, in moduleName: String, fixtures: [String: FixturePaths], under integration: MultiModuleIntegration) -> String {
		switch integration {
		case .moduleInfo:
			fixtures[moduleName]![fileName]
		case .swiftPackagePlugin:
			NormalizedFilePath(fixtures[moduleName]!.compilerPath(of: fileName)).path
		}
	}

	/// Expects every module to have compiled, when compile verification runs.
	private func expectEveryModuleCompiled(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 }, sourceLocation: sourceLocation)
	}
}
