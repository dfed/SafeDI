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
		// `Panel` is `package`, so its one tier is: `App` calls it with the comment, as inline it constructs `Panel` with
		// the comment.
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
						package struct Panel: Instantiable {
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
				            _ = Panel.__safeDI_Panel_F0C17F5BF000CB21.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
						package struct Theme {
						    package init() {}
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
						package struct Shell: Instantiable {
						    package init(theme: Theme, service: Service) {
						        self.theme = theme
						        self.service = service
						    }

						    @Forwarded let theme: Theme
						    @Instantiated let service: Service
						}
						""",
						Self.appRoot(declarations: ["@Instantiated let shellBuilder: Instantiator<Shell>"]).replacingOccurrences(of: "public init(", with: "package init("),
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

			    package init(theme: Theme?) {
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
			                _ = Service.__safeDI_Service_27F6F01DC5D0EF8E.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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

	// MARK: A caller of a seam whose own initializer it cannot call

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtInitializer_whenTreeBuiltInlineConstructsInitializerCallerCannotCall(integration: MultiModuleIntegration) async {
		// `Screen`'s own initializer is internal: `App`, in another package, cannot construct it inline. Declared a seam,
		// `Screen` is called through its generated `public` initializer instead
		// (`generate_callsPublicTier_whenSeamsOwnInitializerIsNarrowerThanCallerCanCall`), which the error offers.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let screenPath = Self.declarationPath(of: "Screen.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(screenPath):3:5: error: `Screen`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix, or declare `Screen` with `generateDependencyTree: true`, so that module `Feature` generates its tree and this module calls the initializer it generates.
			\(screenPath):3:5-3:5: fixit: public\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.screenModules(seam: false, screenInitializer: "init(detail: Detail)", declarations: ["@Instantiated let detail: Detail"], appDeclarations: ["@Instantiated let screen: Screen"]), integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicTier_whenSeamsOwnInitializerIsNarrowerThanCallerCanCall(integration: MultiModuleIntegration) async throws {
		// `Screen`'s own initializer is internal, but its generated initializer is at its type's access, `public`, and
		// calls the internal one inside `Feature`: `App`, in another package, calls it.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.screenModules(seam: true, screenInitializer: "init(detail: Detail)", declarations: ["@Instantiated let detail: Detail"], appDeclarations: ["@Instantiated let screen: Screen"]), integration: integration, filesToDelete: &filesToDelete)
		#expect(Self.seamFile(of: output, integration: integration) == generatedFileHeader + """
		extension Screen {
		    public init() {
		        let detail = Detail()
		        self.init(detail: detail)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_CBF29CE484222325 {}
		}
		""")
		#expect(Self.rootFile(of: output, integration: integration) == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_CBF29CE484222325.self\(Self.pluginComment(integration))
		            return Screen()
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(screen: screen)
		    }
		}
		""")
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtEachInitializer_whenTreeBuiltInlineConstructsReceiverAndTypeCallerCannotCall(integration: MultiModuleIntegration) async {
		// `Screen`'s own initializer and `Reader`'s, which requires `token`, are `package`: inline, `App`, in another
		// package, reports both initializers, each with its fix-it. Declared a seam, `Screen` is called through its
		// generated `public` initializer instead, which takes `token` and calls both inside `Feature`
		// (`generate_callsPublicTierPassingValue_whenReceiversInitializerIsNarrowerThanCallerCanCall`), which each error offers.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let readerPath = Self.declarationPath(of: "Reader.swift", in: "Feature", fixtures: fixtures, under: integration)
			let screenPath = Self.declarationPath(of: "Screen.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(readerPath):3:5: error: `Reader`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix, or declare `Screen` with `generateDependencyTree: true`, so that module `Feature` generates its tree and this module calls the initializer it generates.
			\(readerPath):3:5-3:12: fixit: public
			\(screenPath):3:5: error: `Screen`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix, or declare `Screen` with `generateDependencyTree: true`, so that module `Feature` generates its tree and this module calls the initializer it generates.
			\(screenPath):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.screenModules(seam: false, screenInitializer: "package init(reader: Reader)", declarations: ["@Instantiated let reader: Reader"], appDeclarations: ["@Instantiated let token: Token", "@Instantiated let screen: Screen"]), integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicTierPassingValue_whenReceiversInitializerIsNarrowerThanCallerCanCall(integration: MultiModuleIntegration) async throws {
		// `Reader`'s package initializer requires `token`, which `Token`'s own declaration proves `public`, so `Screen`'s
		// generated initializer takes it at `Screen`'s access, `public`, and calls `Screen`'s package initializer inside
		// `Feature`: `App`, in another package, calls it passing its `token`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.screenModules(seam: true, screenInitializer: "package init(reader: Reader)", declarations: ["@Instantiated let reader: Reader"], appDeclarations: ["@Instantiated let token: Token", "@Instantiated let screen: Screen"]), integration: integration, filesToDelete: &filesToDelete)
		#expect(Self.seamFile(of: output, integration: integration) == generatedFileHeader + """
		extension Screen {
		    public init(token: Token) {
		        let reader = Reader(token: token)
		        self.init(reader: reader)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_1EB503BFA23A82BA {}
		}
		""")
		#expect(Self.rootFile(of: output, integration: integration) == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        let token = Token()
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_1EB503BFA23A82BA.self\(Self.pluginComment(integration))
		            return Screen(token: token)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(token: token, screen: screen)
		    }
		}
		""")
		try expectEveryModuleCompiled(output)
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

	/// `Feature`, declaring the public `Screen` with `screenInitializer` and `declarations`, a seam when `seam` is set, the
	/// public `Reader`, whose package initializer requires `token`, and the public `Detail` and `Token`; and `App`, in
	/// another package, whose root declares `appDeclarations`.
	private static func screenModules(seam: Bool, screenInitializer: String, declarations: [String], appDeclarations: [String]) -> [ModuleFixture] {
		let properties = declarations.map { $0[$0.range(of: " let ")!.upperBound...].prefix { $0 != ":" } }
		return [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"""
					@Instantiable\(seam ? "(generateDependencyTree: true)" : "")
					public struct Screen: Instantiable {
					    \(screenInitializer) {
					\(properties.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
					    }

					\(declarations.map { "    \($0)" }.joined(separator: "\n"))
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
					seamFixtureType(named: "Detail", declarations: []),
					seamFixtureType(named: "Token", declarations: []),
				],
			),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [Self.appRoot(declarations: appDeclarations)], dependencies: ["Feature"]),
		]
	}

	/// `Feature`'s generated `Screen` file under `integration`.
	private static func seamFile(of output: MultiModuleTestOutput, integration: MultiModuleIntegration) -> String? {
		switch integration {
		case .moduleInfo:
			output.modules["Feature"]?.generatedFiles["Feature.swift"]
		case .swiftPackagePlugin:
			output.modules["Feature"]?.generatedFiles["Screen+SafeDI.swift"]
		}
	}

	/// `App`'s generated root file under `integration`.
	private static func rootFile(of output: MultiModuleTestOutput, integration: MultiModuleIntegration) -> String? {
		switch integration {
		case .moduleInfo:
			output.modules["App"]?.generatedFiles["App.swift"]
		case .swiftPackagePlugin:
			output.modules["App"]?.generatedFiles["Root+SafeDI.swift"]
		}
	}

	/// The comment a call of `Feature`'s seam carries under `integration`.
	private static func pluginComment(_ integration: MultiModuleIntegration) -> String {
		integration.seamCallComment(type: "Screen", declaringModule: "Feature")
	}

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
