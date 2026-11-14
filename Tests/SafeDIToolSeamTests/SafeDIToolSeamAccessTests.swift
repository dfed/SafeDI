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

/// How the check that every construction compiles in the module that emits it meets seams: a module that knows a seam
/// generates each construction in a world where the seam is called, so what it decides about each construction –
/// where it assumes `package` access reaches, the error where no tier can be reached – is decided about that world.
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

	// MARK: Modules SafeDI is not told the package of

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assumesPackageAccess_whenCallingModuleDeclaresSeamWithoutTargetGraph() async throws {
		// `App` declares a seam, so it generates in the world where seams are called; `Feature`'s `package` `Service` is
		// still constructed, since without the target graph the tool cannot tell which module declares it, and the line
		// says nothing about it.
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
			    /// Code you write and code SafeDI generates can both call this initializer.
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
			        let service = Service()
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
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingToPassPackages_whenOnlyDependencyDeclaresSeamAndNeitherModuleIsToldItsPackage() async {
		// `Feature` declares a seam no tree reaches, which `App` knows from `Feature`'s module info, so `App` generates in
		// the world where seams are called; neither run is told a package, so its construction of `Service` needs `public`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = fixtures["Feature"]!["Service.swift"]
			return """
			\(servicePath):2:1: error: `Service` is `package`, so module `App`, which SafeDI is not told is in the same package, cannot construct it in the code SafeDI generates. Give modules `App` and `Feature` the same package name (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if they are in one package, or make `Service` `public` to fix.
			\(servicePath):2:1-2:8: fixit: public
			\(servicePath):3:5: error: `Service`’s initializer is `package`, so module `App`, which SafeDI is not told is in the same package, cannot call it in the code SafeDI generates. Give modules `App` and `Feature` the same package name (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if they are in one package, or make the initializer `public` to fix.
			\(servicePath):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
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
		}
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtSeamType_whenCallerReachesNoTierOfDependencysPackageSeamAndNeitherModuleIsToldItsPackage(seam: Bool) async {
		// `Panel` is `package`, so its one tier is, which `App`, told no package, cannot call: the check of every
		// construction reports `Panel` itself – its type alone, since the call reaches no tier of it – as it reports
		// `Panel` and its initializer where `App` builds `Panel`'s tree inline.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let panelPath = fixtures["Feature"]!["Panel.swift"]
			let servicePath = fixtures["Feature"]!["Service.swift"]
			return seam
				? """
				\(panelPath):2:1: error: `Panel` is `package`, so module `App`, which SafeDI is not told is in the same package, cannot construct it in the code SafeDI generates. Give modules `App` and `Feature` the same package name (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if they are in one package, or make `Panel` `public` to fix.
				\(panelPath):2:1-2:8: fixit: public
				\(servicePath):2:1: error: `Service` is `package`, so module `App`, which SafeDI is not told is in the same package, cannot construct it in the code SafeDI generates. Give modules `App` and `Feature` the same package name (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if they are in one package, or make `Service` `public` to fix.
				\(servicePath):2:1-2:8: fixit: public
				\(servicePath):3:5: error: `Service`’s initializer is `package`, so module `App`, which SafeDI is not told is in the same package, cannot call it in the code SafeDI generates. Give modules `App` and `Feature` the same package name (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if they are in one package, or make the initializer `public` to fix.
				\(servicePath):3:5-3:12: fixit: public
				"""
				: """
				\(panelPath):2:1: error: `Panel` is `package`, so module `App`, which SafeDI is not told is in the same package, cannot construct it in the code SafeDI generates. Give modules `App` and `Feature` the same package name (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if they are in one package, or make `Panel` `public` to fix.
				\(panelPath):2:1-2:8: fixit: public
				\(panelPath):3:5: error: `Panel`’s initializer is `package`, so module `App`, which SafeDI is not told is in the same package, cannot call it in the code SafeDI generates. Give modules `App` and `Feature` the same package name (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if they are in one package, or make the initializer `public` to fix, or declare `Panel` with `generateDependencyTree: true`, so that module `Feature` generates its tree and this module calls the initializer it generates.
				\(panelPath):3:5-3:12: fixit: public
				\(servicePath):2:1: error: `Service` is `package`, so module `App`, which SafeDI is not told is in the same package, cannot construct it in the code SafeDI generates. Give modules `App` and `Feature` the same package name (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if they are in one package, or make `Service` `public` to fix.
				\(servicePath):2:1-2:8: fixit: public
				\(servicePath):3:5: error: `Service`’s initializer is `package`, so module `App`, which SafeDI is not told is in the same package, cannot call it in the code SafeDI generates. Give modules `App` and `Feature` the same package name (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if they are in one package, or make the initializer `public` to fix.
				\(servicePath):3:5-3:12: fixit: public
				"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingToPassPackage_whenCallerToldNoPackageReachesOnlyPublicTierOfSeamThatOmitsItsValue() async {
		// `Feature`, in package `Shop`, generates `Service` with a `public` tier and a `package` one that passes `theme`,
		// which `Badge`'s `package` initializer receives. `App` runs with its module's name and no package name, so it has
		// no package: it calls the `public` tier, which would drop the `theme` `Shell` holds. `App` is compiled in `Shop`
		// here, so the error says how to tell SafeDI so.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let themePath = fixtures["Feature"]!["Theme.swift"]
			return """
			\(fixtures["App"]!["Shell.swift"]):10:5: error: `Shell` provides `theme: Theme`, but the `public` initializer SafeDI generated for `Service` in module `Feature`, the narrowest one module `App` can call, does not take it: `Service` takes `theme` only on its `package` initializer, so this call would pass `nil` to `Badge`, which the tree would hand `theme` were it built inline. `Theme` is declared `package`. Give module `App` the package name of module `Feature` (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if the two are in one package; declare `Theme` `public`; or stop providing `theme` on this path.
			\(themePath):1:1: note: `Theme` is declared `package` here.
			\(themePath):1:1-1:8: fixit: public
			\(fixtures["Feature"]!["Badge.swift"]):7:5: note: `Badge` receives `theme: Theme?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
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
		}
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
		    /// Code you write and code SafeDI generates can both call this initializer.
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
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_token: @autoclosure @escaping () -> Token) {
		        let token = LazilyInstantiated<Token>(__safeDI_token)
		        let reader = Reader(token: token.instance)
		        self.init(reader: reader)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_F2F345803C710CE2 {}
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
		            _ = Screen.__safeDI_Screen_F2F345803C710CE2.self\(Self.pluginComment(integration))
		            return Screen(__safeDI_token: token)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(token: token, screen: screen)
		    }
		}
		""")
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
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.featureModuleWithScreenSeam),
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
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public init(__safeDI_logger: @autoclosure @escaping () -> Logger?) {
				        let logger = LazilyInstantiated<Logger?>(__safeDI_logger)
				        let detail = Detail(logger: logger.instance)
				        self.init(detail: detail)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_20C0E63A654A9D89 {}
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
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public init(__safeDI_logger: @autoclosure @escaping () -> Logger?) {
				        let logger = LazilyInstantiated<Logger?>(__safeDI_logger)
				        let detail = Detail(logger: logger.instance)
				        self.init(detail: detail)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_20C0E63A654A9D89 {}
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
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Feature`'s public `Logger`; the public `Detail`, which receives `logger` only if available; and the seam `Screen`,
	/// which instantiates `Detail`.
	private static let featureModuleWithScreenSeam = [
		seamFixtureType(named: "Logger", declarations: []),
		"""
		@Instantiable
		public struct Detail: Instantiable {
		    public init(logger: Logger?) {
		        self.logger = logger
		    }

		    @Received(onlyIfAvailable: true) let logger: Logger?
		}
		""",
		seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let detail: Detail"]),
	]

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
}
