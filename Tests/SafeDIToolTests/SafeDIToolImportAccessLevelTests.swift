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

/// How the imports of generated files spell access levels (SE-0409). Without `InternalImportsByDefault`, the compiler
/// rejects an import that spells no level when another file of the module imports the same module with a level below
/// `public`; with it, an import that spells none is `internal`, too narrow for a `public` declaration that names the
/// module's types. Each generated file therefore decides each import's level from the levels the module's own files
/// spell and from what its own declarations name (`GeneratedImportAccess`). Every cell's fixture spells its own import
/// of SafeDI, and every cell compiles its module, without and with `InternalImportsByDefault`, failing on a warning
/// in generated code. A cell whose public mock needs a `public` import also compiles in a release build, where the mock
/// condition is inactive and an import only the mock needs would be unused.
struct SafeDIToolImportAccessLevelTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Every kind of generated file of a module whose files spell an import's level

	@Test(arguments: WrittenImport.allCases, ImportCompileMode.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsInternalOrNoLevel_inEveryKindOfGeneratedFile_whenOwnFileSpellsLevel(
		writtenImport: WrittenImport,
		compileMode: ImportCompileMode,
	) async throws {
		for integration in MultiModuleIntegration.allCases {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [
							Self.root,
							writtenImport.child,
							Self.panelSeam,
							Self.gaugePublicMock,
						],
						compilerSettings: compileMode.settings,
					),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			let imports = Self.importBlock([
				Self.importLine(module: "Foundation", spelled: writtenImport.generatedImport),
				Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
			])
			let expectedFiles: [String: String] = switch integration {
			case .moduleInfo:
				[
					"App.swift": Self.file(importing: imports, bodies: [
						Self.panelTree,
						Self.rootTree,
						writtenImport.childMock,
						Self.gaugeMock,
						writtenImport.rootMock,
						Self.panelConfiguration,
					]),
				]
			case .swiftPackagePlugin:
				[
					"Child+SafeDIMock.swift": Self.file(importing: imports, bodies: [writtenImport.childMock]),
					"Gauge+SafeDIMock.swift": Self.file(importing: imports, bodies: [Self.gaugeMock]),
					"Panel+SafeDI.swift": Self.file(importing: imports, bodies: [Self.panelTree]),
					"Root+SafeDI.swift": Self.file(importing: imports, bodies: [Self.rootTree]),
					"Root+SafeDIMock.swift": Self.file(importing: imports, bodies: [writtenImport.rootMock]),
					"SafeDIMockConfiguration.swift": Self.file(importing: imports, bodies: [Self.panelConfiguration]),
				]
			}
			#expect(output.modules["App"]?.generatedFiles == expectedFiles, "\(integration)")
		}
	}

	// MARK: Public and package declarations

	@Test(arguments: ImportCompileMode.allCases, [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsLevelEachFileDeclarationsNeed_whenPublicMockAndSeamsNameImportedTypes(compileMode: ImportCompileMode, isReleaseConfiguration: Bool) async throws {
		// `Feature` imports Foundation `public` where a `public` initializer names `URL` or `Date`, and `package` where a
		// `package` one names `URL`: the public mock and the `public` seam name `Date` and `URL` in `public` declarations,
		// the `package` seam names `URL` in a `package` one, and the empty mock configuration names nothing, so it
		// imports Foundation `internal`, as every import of a module the module's files import below `public` must spell
		// a level without `InternalImportsByDefault`. SafeDI is imported `public` everywhere, which the conformances
		// need, but no generated declaration names a SafeDI type, so no generated file imports it `public`. The public
		// mock is compiled only under `DEBUG`, so its file imports Foundation `public` only there, and `internal`
		// elsewhere, where nothing it compiles names Foundation; the module's single file, whose seam names `URL`
		// `public` outside the condition, imports it `public` everywhere.
		for integration in MultiModuleIntegration.allCases {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContent: [
							"""
							public import SafeDI
							public import Foundation

							@Instantiable(generateMock: .public)
							public final class Child: Instantiable {
							    public init(date: Date = Date()) {
							        self.date = date
							    }

							    public let date: Date
							}
							""",
							"""
							public import SafeDI

							@Instantiable(generateDependencyTree: true)
							public struct Feed: Instantiable {
							    public init(loader: Loader) {
							        self.loader = loader
							    }

							    @Instantiated let loader: Loader
							}
							""",
							"""
							public import SafeDI
							public import Foundation

							@Instantiable
							public struct Loader: Instantiable {
							    public init(url: URL) {
							        self.url = url
							    }

							    @Received let url: URL
							}
							""",
							"""
							public import SafeDI

							@Instantiable(generateDependencyTree: true)
							package struct Shelf: Instantiable {
							    package init(cache: Cache) {
							        self.cache = cache
							    }

							    @Instantiated let cache: Cache
							}
							""",
							"""
							public import SafeDI
							package import Foundation

							@Instantiable
							package struct Cache: Instantiable {
							    package init(directory: URL) {
							        self.directory = directory
							    }

							    @Received let directory: URL
							}
							""",
						],
						isReleaseConfiguration: isReleaseConfiguration,
						compilerSettings: compileMode.settings,
					),
					ModuleFixture(
						name: "App",
						packageName: "Store",
						swiftFileContent: [
							"""
							public import SafeDI
							import Feature

							@Instantiable(isRoot: true, generateMock: true)
							final class Root: Instantiable {
							    init(child: Child) {
							        self.child = child
							    }

							    @Instantiated let child: Child
							}
							""",
						],
						dependencies: ["Feature"],
						isReleaseConfiguration: isReleaseConfiguration,
						compilerSettings: compileMode.settings,
					),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			func featureImports(foundation: String) -> String {
				Self.importBlock([
					Self.importLine(module: "Foundation", spelled: foundation),
					Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
				])
			}
			let expectedFeatureFiles: [String: String] = switch integration {
			case .moduleInfo:
				[
					"Feature.swift": Self.file(importing: featureImports(foundation: "public import Foundation"), bodies: [Self.feedTree, Self.shelfTree, Self.childPublicMock]),
				]
			case .swiftPackagePlugin:
				[
					"Child+SafeDIMock.swift": Self.file(importing: Self.importBlock([
						Self.importLine(module: "Foundation", spelled: "public import Foundation", where: "DEBUG", otherwise: "internal import Foundation"),
						Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
					]), bodies: [Self.childPublicMock]),
					"Feed+SafeDI.swift": Self.file(importing: featureImports(foundation: "public import Foundation"), bodies: [Self.feedTree]),
					"SafeDIMockConfiguration.swift": Self.file(importing: featureImports(foundation: "internal import Foundation"), bodies: [""]),
					"Shelf+SafeDI.swift": Self.file(importing: featureImports(foundation: "package import Foundation"), bodies: [Self.shelfTree]),
				]
			}
			#expect(output.modules["Feature"]?.generatedFiles == expectedFeatureFiles, "\(integration)")
			// `App`'s own files spell a level on SafeDI alone, so the imports of Feature and of Foundation, which only
			// `Feature`'s files import, spell none: its declarations are `internal`.
			let appImports = Self.importBlock([
				Self.importLine(module: "Feature", spelled: "import Feature"),
				Self.importLine(module: "Foundation", spelled: "import Foundation"),
				Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
			])
			let expectedAppFiles: [String: String] = switch integration {
			case .moduleInfo:
				["App.swift": Self.file(importing: appImports, bodies: [Self.appRootTree, Self.appRootMock, Self.childConfiguration])]
			case .swiftPackagePlugin:
				[
					"Root+SafeDI.swift": Self.file(importing: appImports, bodies: [Self.appRootTree]),
					"Root+SafeDIMock.swift": Self.file(importing: appImports, bodies: [Self.appRootMock]),
					"SafeDIMockConfiguration.swift": Self.file(importing: appImports, bodies: [Self.childConfiguration]),
				]
			}
			#expect(output.modules["App"]?.generatedFiles == expectedAppFiles, "\(integration)")
		}
	}

	@Test(arguments: ImportCompileMode.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsPackageOnlyUnderInternalImportsByDefault_whenPackageSeamNamesTypeOfModuleImportedPublic(compileMode: ImportCompileMode) async throws {
		// The module's files import Foundation `public` and never below it, so another of its files may import it with no
		// level, which without `InternalImportsByDefault` is `public` and makes a `package` import ambiguous, while with it
		// an import with no level is too narrow for the `package` initializer: the import asks the compiler.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Storage",
					packageName: "Shop",
					swiftFileContent: [
						"""
						public import SafeDI

						@Instantiable(generateDependencyTree: true)
						package struct Shelf: Instantiable {
						    package init(cache: Cache) {
						        self.cache = cache
						    }

						    @Instantiated let cache: Cache
						}
						""",
						"""
						public import SafeDI
						public import Foundation

						@Instantiable
						package struct Cache: Instantiable {
						    package init(directory: URL) {
						        self.directory = directory
						    }

						    @Received let directory: URL
						}

						public struct Endpoint {
						    public init(url: URL) {}
						}
						""",
					],
					compilerSettings: compileMode.settings,
				),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Storage"]?.generatedFiles == [
			"Shelf+SafeDI.swift": Self.file(importing: Self.importBlock([
				"""
				#if canImport(Foundation)
				#if hasFeature(InternalImportsByDefault)
				package import Foundation
				#else
				import Foundation
				#endif
				#endif
				""",
				Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
			]), bodies: [Self.shelfTree]),
		])
	}

	@Test(arguments: ImportCompileMode.allCases, [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsPublicUnderMockCondition_whenPublicMockNamesSafeDIWrapperOfModuleImportedPublic(compileMode: ImportCompileMode, isReleaseConfiguration: Bool) async throws {
		// The public mock's signature names `Instantiator`, a SafeDI type, so its file imports SafeDI `public` where the
		// mock compiles, under `DEBUG`, and with no level elsewhere; the mock configuration's file names none, so it
		// imports SafeDI with no level.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						"""
						public import SafeDI

						@Instantiable(generateMock: .public)
						public struct Service: Instantiable {
						    public init(gaugeBuilder: Instantiator<Gauge>) {
						        self.gaugeBuilder = gaugeBuilder
						    }

						    @Received let gaugeBuilder: Instantiator<Gauge>
						}
						""",
						"""
						public import SafeDI

						@Instantiable
						public struct Gauge: Instantiable {
						    public init() {}
						}
						""",
					],
					isReleaseConfiguration: isReleaseConfiguration,
					compilerSettings: compileMode.settings,
				),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"SafeDIMockConfiguration.swift": Self.file(importing: Self.importBlock([Self.importLine(module: "SafeDI", spelled: "import SafeDI")]), bodies: [""]),
			"Service+SafeDIMock.swift": Self.file(importing: Self.importBlock([Self.importLine(module: "SafeDI", spelled: "public import SafeDI", where: "DEBUG", otherwise: "import SafeDI")]), bodies: [
				"""
				#if DEBUG
				extension Service {
				    /// Overrides for the mock dependency tree.
				    public struct SafeDIOverrides {
				        public init(
				            gaugeBuilder: (() -> Gauge)? = nil
				        ) {
				            self.gaugeBuilder = gaugeBuilder
				        }

				        public let gaugeBuilder: (() -> Gauge)?
				    }

				    public static func mock(
				        gaugeBuilder: Instantiator<Gauge>? = nil,
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Service {
				        func __safeDI_gaugeBuilder() -> Gauge {
				            if let safeDIBuilder = safeDIOverrides.gaugeBuilder { safeDIBuilder() } else { Gauge() }
				        }
				        let gaugeBuilder = if let gaugeBuilder { gaugeBuilder } else { Instantiator<Gauge>(__safeDI_gaugeBuilder) }
				        return Service(gaugeBuilder: gaugeBuilder)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_mock_0063D5E24694C830 {}
				}
				#endif
				""",
			]),
		])
	}

	@Test(arguments: ImportCompileMode.allCases, [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsPublicUnderMockCondition_whenPublicMockNamesTypeSafeDIReadsNoDeclarationOfFromModuleImportedPublic(compileMode: ImportCompileMode, isReleaseConfiguration: Bool) async throws {
		// SafeDI reads no declaration of Dispatch's types, so `DispatchQoS` may come from any module the module's files
		// import `public`: Dispatch, but neither SafeDI, whose types SafeDI knows, nor Foundation, which they import only
		// `internal`. `Dispatch.DispatchQoS` names its module, `String` names none, and the `@usableFromInline` provider
		// of the optional default names `DispatchQoS` in its result. The mock compiles only under `DEBUG`, so the file
		// imports Dispatch `public` only there.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						"""
						public import SafeDI
						public import Dispatch
						internal import Foundation

						@Instantiable(generateMock: .public)
						public struct Worker: Instantiable {
						    public init(qos: Dispatch.DispatchQoS = .default, qosClass: DispatchQoS.QoSClass? = .utility, label: String = "worker") {
						        self.qos = qos
						        self.qosClass = qosClass
						        self.label = label
						    }

						    public let qos: Dispatch.DispatchQoS
						    public let qosClass: DispatchQoS.QoSClass?
						    public let label: String
						}
						""",
					],
					isReleaseConfiguration: isReleaseConfiguration,
					compilerSettings: compileMode.settings,
				),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"SafeDIMockConfiguration.swift": Self.file(importing: Self.importBlock([
				Self.importLine(module: "Dispatch", spelled: "import Dispatch"),
				Self.importLine(module: "Foundation", spelled: "internal import Foundation"),
				Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
			]), bodies: [""]),
			"Worker+SafeDIMock.swift": Self.file(importing: Self.importBlock([
				Self.importLine(module: "Dispatch", spelled: "public import Dispatch", where: "DEBUG", otherwise: "import Dispatch"),
				Self.importLine(module: "Foundation", spelled: "internal import Foundation"),
				Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
			]), bodies: [
				"""
				#if DEBUG
				extension Worker {
				    // These providers evaluate `Worker`'s own defaults outside any actor, since SafeDI sees no isolation on it. If one
				    // reads the state of an actor `Worker` takes from a conformance or a superclass and does not compile, give its
				    // `@Instantiable` `mockAttributes: "@MainActor"` (or that actor).
				    @usableFromInline nonisolated static func __safeDI_publicMockDefault_qosClass() -> DispatchQoS.QoSClass? { .utility }

				    public static func mock(
				        qos: Dispatch.DispatchQoS? = nil,
				        qosClass: DispatchQoS.QoSClass? = Worker.__safeDI_publicMockDefault_qosClass(),
				        label: String? = nil
				    ) -> Worker {
				        let qos = qos ?? (.default)
				        let label = label ?? ("worker")
				        return Worker(qos: qos, qosClass: qosClass, label: label)
				    }
				}

				extension Worker {
				    public enum __safeDI_Worker_mock_1966B654AF5BFCA0 {}
				}
				#endif
				""",
			]),
		])
	}

	@Test(arguments: ImportCompileMode.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsPublic_whenSeamNamesTypeDependencyDeclaresAndOwnFilesImportWithNoLevel(compileMode: ImportCompileMode) async throws {
		// SafeDI reads `Core`'s declaration of `Token`, which the seam's `public` initializer names, so the seam's file
		// imports Core `public` although `App`'s own files import it with no level, which with `InternalImportsByDefault`
		// is `internal`: their own declarations name no type of Core publicly.
		for integration in MultiModuleIntegration.allCases {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Core",
						packageName: "Shop",
						swiftFileContent: [
							"""
							public import SafeDI

							@Instantiable
							public struct Vault: Instantiable {
							    public init(token: Token) {
							        self.token = token
							    }

							    @Received let token: Token
							}

							public struct Token {
							    public init() {}
							}
							""",
						],
						compilerSettings: compileMode.settings,
					),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [
							"""
							public import SafeDI
							import Core

							@Instantiable(generateDependencyTree: true)
							public struct Session: Instantiable {
							    init(vault: Vault) {
							        self.vault = vault
							    }

							    @Instantiated let vault: Vault
							}
							""",
						],
						dependencies: ["Core"],
						compilerSettings: compileMode.settings,
					),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			let fileName = switch integration {
			case .moduleInfo:
				"App.swift"
			case .swiftPackagePlugin:
				"Session+SafeDI.swift"
			}
			#expect(output.modules["App"]?.generatedFiles == [
				fileName: Self.file(importing: Self.importBlock([
					Self.importLine(module: "Core", spelled: "public import Core"),
					Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
				]), bodies: [
					"""
					extension Session {
					    public init(token __safeDI_token: @autoclosure @escaping () -> Token) {
					        let token = LazilyInstantiated<Token>(__safeDI_token)
					        let vault = Vault(token: token.instance)
					        self.init(vault: vault)
					    }
					}

					extension Session {
					    public enum __safeDI_Session_F2F345803C710CE2 {}
					}
					""",
				]),
			], "\(integration)")
		}
	}

	@Test(arguments: MockConditionCase.allCases, ImportCompileMode.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsPublicUnderMockCondition_whenOnlyMockDeclarationsNameImportedType(
		mockCondition: MockConditionCase,
		compileMode: ImportCompileMode,
	) async throws {
		// The public mock names `Date` in its own default-valued parameter, and the public configuration of `Child`, which
		// its tree builds, in `Child`'s; the seam names no Foundation type. A build in which the mock condition is
		// inactive compiles neither the mock nor the configuration, where a `public` import of Foundation would be unused,
		// so each mock file imports Foundation `public` under the condition and with no level, as `Feature`'s files
		// import it nowhere below `public`, elsewhere. The module's single file guards the import as its mock files do,
		// since its dependency-tree code names no Foundation type. Mocks generated without a condition compile in every
		// build, so they import Foundation `public` everywhere. Each integration's output compiles in a debug build and in
		// a release build, which defines no mock condition.
		for integration in MultiModuleIntegration.allCases {
			for isReleaseConfiguration in [false, true] {
				let output = try await executeSafeDIToolMultiModuleTest(
					modules: [
						ModuleFixture(
							name: "Feature",
							packageName: "Shop",
							swiftFileContent: [
								"""
								public import SafeDI
								public import Foundation

								@Instantiable(generateMock: .public)
								public final class Holder: Instantiable {
								    public init(child: Child, started: Date = Date()) {
								        self.child = child
								        self.started = started
								    }

								    @Instantiated let child: Child
								    public let started: Date
								}
								""",
								"""
								public import SafeDI
								public import Foundation

								@Instantiable
								public final class Child: Instantiable {
								    public init(date: Date = Date()) {
								        self.date = date
								    }

								    public let date: Date
								}
								""",
								"""
								public import SafeDI

								@Instantiable(generateDependencyTree: true)
								public struct Feed: Instantiable {
								    public init(gauge: Gauge) {
								        self.gauge = gauge
								    }

								    @Instantiated let gauge: Gauge
								}
								""",
								"""
								public import SafeDI

								@Instantiable
								public struct Gauge: Instantiable {
								    public init() {}
								}
								""",
							],
							swiftFileContentByFilePath: mockCondition.configurationFiles,
							mockConditionalCompilation: mockCondition.fixtureCondition,
							isReleaseConfiguration: isReleaseConfiguration,
							compilerSettings: compileMode.settings,
						),
					],
					integration: integration,
					filesToDelete: &filesToDelete,
				)
				let treeImports = Self.importBlock([
					Self.importLine(module: "Foundation", spelled: "import Foundation"),
					Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
				])
				let mockFoundationImport = if let condition = mockCondition.condition {
					Self.importLine(module: "Foundation", spelled: "public import Foundation", where: condition, otherwise: "import Foundation")
				} else {
					Self.importLine(module: "Foundation", spelled: "public import Foundation")
				}
				let mockImports = Self.importBlock([
					mockFoundationImport,
					Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
				])
				let expectedFiles: [String: String] = switch integration {
				case .moduleInfo:
					["Feature.swift": Self.file(importing: mockImports, bodies: [Self.feedGaugeTree, mockCondition.holderPublicMock, mockCondition.childPublicConfiguration])]
				case .swiftPackagePlugin:
					[
						"Feed+SafeDI.swift": Self.file(importing: treeImports, bodies: [Self.feedGaugeTree]),
						"Holder+SafeDIMock.swift": Self.file(importing: mockImports, bodies: [mockCondition.holderPublicMock]),
						"SafeDIMockConfiguration.swift": Self.file(importing: mockImports, bodies: [mockCondition.childPublicConfiguration]),
					]
				}
				#expect(output.modules["Feature"]?.generatedFiles == expectedFiles, "\(integration), \(isReleaseConfiguration ? "release" : "debug")")
			}
		}
	}

	@Test(arguments: ImportCompileMode.allCases, [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsPackageOutsideMockCondition_whenPackageSeamAndPublicMockNameTypeOfModuleImportedPublic(compileMode: ImportCompileMode, isReleaseConfiguration: Bool) async throws {
		// The `package` seam names `URL` and the public mock names `Date`, and `Storage`'s files import Foundation `public`
		// and never below it. The module's single file imports Foundation `public` where the mock condition is active, and
		// elsewhere as the seam alone needs: `package` only where `InternalImportsByDefault` is on.
		for integration in MultiModuleIntegration.allCases {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Storage",
						packageName: "Shop",
						swiftFileContent: [
							"""
							public import SafeDI

							@Instantiable(generateDependencyTree: true)
							package struct Shelf: Instantiable {
							    package init(cache: Cache) {
							        self.cache = cache
							    }

							    @Instantiated let cache: Cache
							}
							""",
							"""
							public import SafeDI
							public import Foundation

							@Instantiable
							package struct Cache: Instantiable {
							    package init(directory: URL) {
							        self.directory = directory
							    }

							    @Received let directory: URL
							}
							""",
							"""
							public import SafeDI
							public import Foundation

							@Instantiable(generateMock: .public)
							public final class Child: Instantiable {
							    public init(date: Date = Date()) {
							        self.date = date
							    }

							    public let date: Date
							}
							""",
						],
						isReleaseConfiguration: isReleaseConfiguration,
						compilerSettings: compileMode.settings,
					),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			let packageFoundationImport = """
			#if hasFeature(InternalImportsByDefault)
			package import Foundation
			#else
			import Foundation
			#endif
			"""
			let safeDIImport = Self.importLine(module: "SafeDI", spelled: "import SafeDI")
			let expectedFiles: [String: String] = switch integration {
			case .moduleInfo:
				[
					"Storage.swift": Self.file(importing: Self.importBlock([
						Self.importLine(module: "Foundation", spelled: "public import Foundation", where: "DEBUG", otherwise: packageFoundationImport),
						safeDIImport,
					]), bodies: [Self.shelfTree, Self.childPublicMock]),
				]
			case .swiftPackagePlugin:
				[
					"Child+SafeDIMock.swift": Self.file(importing: Self.importBlock([
						Self.importLine(module: "Foundation", spelled: "public import Foundation", where: "DEBUG", otherwise: "import Foundation"),
						safeDIImport,
					]), bodies: [Self.childPublicMock]),
					"SafeDIMockConfiguration.swift": Self.file(importing: Self.importBlock([
						Self.importLine(module: "Foundation", spelled: "import Foundation"),
						safeDIImport,
					]), bodies: [""]),
					"Shelf+SafeDI.swift": Self.file(importing: Self.importBlock([
						Self.importLine(module: "Foundation", spelled: packageFoundationImport),
						safeDIImport,
					]), bodies: [Self.shelfTree]),
				]
			}
			#expect(output.modules["Storage"]?.generatedFiles == expectedFiles, "\(integration)")
		}
	}

	// MARK: A type only a dependency's file imports the module of

	@Test(arguments: ImportCompileMode.allCases, ["public", "package"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsPublic_whenSeamNamesUnreadTypeADependencyFileNamingItImportsAtPackageOrWider(compileMode: ImportCompileMode, kitImportLevel: String) async throws {
		// The seam's `public` initializer names `Window`, which `Kit` declares and SafeDI does not read, and `URL`. `App`'s
		// own files import neither `Kit` nor Foundation: `Core`'s do, and the file whose `Vault` names `Window` imports
		// `Kit` at `kitImportLevel`, through which `Vault`'s initializer of that level names it, so the seam's file imports
		// Kit `public`, which with `InternalImportsByDefault` an import with no level is too narrow for. The file whose
		// `Loader` names `URL` also imports Dispatch `public`, which declares no type the seam names: Foundation declares
		// `URL`, so that file's imports are not consulted for it, and the seam's file imports Dispatch with no level, where
		// `public` would draw a warning that it is unused.
		for integration in MultiModuleIntegration.allCases {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Kit",
						packageName: "Toolkit",
						swiftFileContentByFilePath: ["Window.swift": "public struct Window {\n    public init() {}\n}"],
						isCheckoutPackage: true,
						runsSafeDI: false,
						compilerSettings: compileMode.settings,
					),
					ModuleFixture(
						name: "Core",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"Vault.swift": """
							public import SafeDI
							\(kitImportLevel) import Kit

							@Instantiable
							public struct Vault: Instantiable {
							    \(kitImportLevel) init(window: Window) {
							        self.window = window
							    }

							    @Received let window: Window
							}
							""",
							"Loader.swift": """
							public import SafeDI
							public import Foundation
							public import Dispatch

							@Instantiable
							public struct Loader: Instantiable {
							    public init(url: URL) {
							        self.url = url
							    }

							    @Received let url: URL
							}

							@Instantiable
							public struct Worker: Instantiable {
							    public init(qos: DispatchQoS) {
							        self.qos = qos
							    }

							    @Received let qos: DispatchQoS
							}
							""",
						],
						dependencies: ["Kit"],
						compilerSettings: compileMode.settings,
					),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [
							"""
							public import SafeDI
							import Core

							@Instantiable(generateDependencyTree: true)
							public struct Session: Instantiable {
							    init(vault: Vault, loader: Loader) {
							        self.vault = vault
							        self.loader = loader
							    }

							    @Instantiated let vault: Vault
							    @Instantiated let loader: Loader
							}
							""",
						],
						dependencies: ["Core"],
						compilerSettings: compileMode.settings,
					),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			let fileName = switch integration {
			case .moduleInfo:
				"App.swift"
			case .swiftPackagePlugin:
				"Session+SafeDI.swift"
			}
			#expect(output.modules["App"]?.generatedFiles == [
				fileName: Self.file(importing: Self.importBlock([
					Self.importLine(module: "Core", spelled: "import Core"),
					Self.importLine(module: "Dispatch", spelled: "import Dispatch"),
					Self.importLine(module: "Foundation", spelled: "public import Foundation"),
					Self.importLine(module: "Kit", spelled: "public import Kit"),
					Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
				]), bodies: [Self.sessionTree(integration: integration)]),
			], "\(integration)")
		}
	}

	@Test(arguments: ImportCompileMode.allCases, ["public", "package"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsPublic_whenSeamOfImportedModuleNamesUnreadTypeAFileItCarriesInItsViewImports(compileMode: ImportCompileMode, kitImportLevel: String) async throws {
		// Cell 23a: `Mid` declares the seam `Session`, and `App`, whose seam `Screen` builds it, lists `Mid` alone: `Mid`'s
		// `.safedi` carries `Core`'s declarations and imports, so `Screen`'s generated `public` initializer, which takes
		// `Session`'s `window: Window`, imports `Kit` `public`, attributed through `Core`'s file as when `App` listed `Core`.
		for integration in MultiModuleIntegration.allCases {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Kit",
						packageName: "Toolkit",
						swiftFileContentByFilePath: ["Window.swift": "public struct Window {\n    public init() {}\n}"],
						isCheckoutPackage: true,
						runsSafeDI: false,
						compilerSettings: compileMode.settings,
					),
					ModuleFixture(
						name: "Core",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"Vault.swift": """
							public import SafeDI
							\(kitImportLevel) import Kit

							@Instantiable
							public struct Vault: Instantiable {
							    \(kitImportLevel) init(window: Window) {
							        self.window = window
							    }

							    @Received let window: Window
							}
							""",
						],
						dependencies: ["Kit"],
						compilerSettings: compileMode.settings,
					),
					ModuleFixture(
						name: "Mid",
						packageName: "Shop",
						swiftFileContent: [
							"""
							public import SafeDI
							import Core

							@Instantiable(generateDependencyTree: true)
							public struct Session: Instantiable {
							    init(vault: Vault) {
							        self.vault = vault
							    }

							    @Instantiated let vault: Vault
							}
							""",
						],
						dependencies: ["Core"],
						compilerSettings: compileMode.settings,
					),
					ModuleFixture(
						name: "App",
						packageName: "Outlet",
						swiftFileContent: [
							"""
							public import SafeDI
							import Mid

							@Instantiable(generateDependencyTree: true)
							public struct Screen: Instantiable {
							    init(session: Session) {
							        self.session = session
							    }

							    @Instantiated let session: Session
							}
							""",
						],
						dependencies: ["Mid"],
						compilerSettings: compileMode.settings,
					),
				],
				integration: integration,
				compileVerification: .recordingIssues,
				filesToDelete: &filesToDelete,
			)
			let fileName = switch integration {
			case .moduleInfo:
				"App.swift"
			case .swiftPackagePlugin:
				"Screen+SafeDI.swift"
			}
			#expect(output.modules["App"]?.generatedFiles == [
				fileName: Self.file(importing: Self.importBlock([
					Self.importLine(module: "Core", spelled: "import Core"),
					Self.importLine(module: "Kit", spelled: "public import Kit"),
					Self.importLine(module: "Mid", spelled: "import Mid"),
					Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
				]), bodies: [Self.screenTreeCallingMidsSession(integration: integration)]),
			], "\(integration)")
		}
	}

	@Test(arguments: ImportCompileMode.allCases, ["public", "package"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsPublicUnderMockCondition_whenPublicMockOfImportedModuleTakesUnreadTypeAFileItCarriesInItsViewImports(compileMode: ImportCompileMode, kitImportLevel: String) async throws {
		// Cell 23b: `Mid` declares the public mock `Service`, whose tree builds `Core`'s `Vault`, which receives `Window`:
		// `Service.mock()` takes `window` as a parameter. `App`, whose public mock of `Screen` builds a `Service`, lists `Mid`
		// alone: `Mid`'s `.safedi` carries `Core`'s declarations and imports, so `Screen`'s public mock, which takes `window`
		// too, imports `Kit` `public` under the mock condition, attributed through `Core`'s file as when `App` listed `Core`.
		for integration in MultiModuleIntegration.allCases {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Kit",
						packageName: "Toolkit",
						swiftFileContentByFilePath: ["Window.swift": "public struct Window {\n    public init() {}\n}"],
						isCheckoutPackage: true,
						runsSafeDI: false,
						compilerSettings: compileMode.settings,
					),
					ModuleFixture(
						name: "Core",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"Vault.swift": """
							public import SafeDI
							\(kitImportLevel) import Kit

							@Instantiable
							public struct Vault: Instantiable {
							    \(kitImportLevel) init(window: Window) {
							        self.window = window
							    }

							    @Received let window: Window
							}
							""",
						],
						dependencies: ["Kit"],
						compilerSettings: compileMode.settings,
					),
					ModuleFixture(
						name: "Mid",
						packageName: "Shop",
						swiftFileContent: [
							"""
							public import SafeDI
							import Core

							@Instantiable(generateMock: .public)
							public final class Service: Instantiable {
							    init(vault: Vault) {
							        self.vault = vault
							    }

							    @Instantiated private let vault: Vault
							}
							""",
						],
						dependencies: ["Core"],
						compilerSettings: compileMode.settings,
					),
					ModuleFixture(
						name: "App",
						packageName: "Outlet",
						swiftFileContent: [
							"""
							public import SafeDI
							import Mid

							@Instantiable(generateMock: .public)
							public final class Screen: Instantiable {
							    init(service: Service) {
							        self.service = service
							    }

							    @Instantiated private let service: Service
							}
							""",
						],
						dependencies: ["Mid"],
						compilerSettings: compileMode.settings,
					),
				],
				integration: integration,
				compileVerification: .recordingIssues,
				filesToDelete: &filesToDelete,
			)
			let mockImports = Self.importBlock([
				Self.importLine(module: "Core", spelled: "import Core"),
				Self.importLine(module: "Kit", spelled: "public import Kit", where: "DEBUG", otherwise: "import Kit"),
				Self.importLine(module: "Mid", spelled: "public import Mid", where: "DEBUG", otherwise: "import Mid"),
				Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
			])
			let expectedFiles: [String: String] = switch integration {
			case .moduleInfo:
				["App.swift": Self.file(importing: mockImports, bodies: [Self.screenMockCallingMidsService(integration: integration)])]
			case .swiftPackagePlugin:
				[
					"SafeDIMockConfiguration.swift": Self.file(importing: Self.importBlock([
						Self.importLine(module: "Core", spelled: "import Core"),
						Self.importLine(module: "Kit", spelled: "import Kit"),
						Self.importLine(module: "Mid", spelled: "import Mid"),
						Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
					]), bodies: [""]),
					"Screen+SafeDIMock.swift": Self.file(importing: mockImports, bodies: [Self.screenMockCallingMidsService(integration: integration)]),
				]
			}
			#expect(output.modules["App"]?.generatedFiles == expectedFiles, "\(integration)")
		}
	}

	// MARK: Attributes beside a level

	@Test(arguments: ImportCompileMode.withoutInternalImportsByDefault)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTestableAndDropsPreconcurrency_whenImportSpellsLevelBesideAttribute(compileMode: ImportCompileMode) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@testable internal import SafeDI
				@preconcurrency internal import Foundation

				@Instantiable(isRoot: true)
				final class Root: Instantiable {
				    init(clock: Clock) {
				        self.clock = clock
				    }

				    @Instantiated let clock: Clock
				}
				""",
				"""
				@testable internal import SafeDI
				@preconcurrency internal import Foundation

				@Instantiable(generateMock: true)
				final class Clock: Instantiable {
				    init(start: Date = Date()) {
				        self.start = start
				    }

				    let start: Date
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: compileMode.settings,
		)
		let imports = Self.importBlock([
			Self.importLine(module: "Foundation", spelled: "internal import Foundation"),
			Self.importLine(module: "SafeDI", spelled: "@testable internal import SafeDI"),
		])
		#expect(output.generatedFiles == [
			"Clock+SafeDIMock.swift": Self.file(importing: imports, bodies: [Self.clockMock]),
			"Root+SafeDI.swift": Self.file(importing: imports, bodies: [Self.clockRootTree]),
			"SafeDIMockConfiguration.swift": Self.file(importing: imports, bodies: [""]),
		])
	}

	@Test(arguments: ImportCompileMode.allCases, [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsPublicOutsideMockCondition_whenOnlyImportOfModuleIsExported(compileMode: ImportCompileMode, isReleaseConfiguration: Bool) async throws {
		// An `@_exported` import must be `public`, so a generated file that copies it imports the module `public`, and
		// everywhere: the compiler does not warn at an `@_exported` import that nothing names, so a mock file needs no
		// other spelling where its mock does not compile.
		for integration in MultiModuleIntegration.allCases {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [
							"""
							internal import SafeDI
							@_exported public import Foundation

							@Instantiable(isRoot: true)
							final class Root: Instantiable {
							    init(clock: Clock) {
							        self.clock = clock
							    }

							    @Instantiated let clock: Clock
							}
							""",
							"""
							internal import SafeDI

							@Instantiable(generateMock: true)
							final class Clock: Instantiable {
							    init(start: Date = Date()) {
							        self.start = start
							    }

							    let start: Date
							}
							""",
						],
						isReleaseConfiguration: isReleaseConfiguration,
						compilerSettings: compileMode.settings,
					),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
			let imports = Self.importBlock([
				Self.importLine(module: "Foundation", spelled: "@_exported public import Foundation"),
				Self.importLine(module: "SafeDI", spelled: "internal import SafeDI"),
			])
			let expectedFiles: [String: String] = switch integration {
			case .moduleInfo:
				["App.swift": Self.file(importing: imports, bodies: [Self.clockRootTree, Self.clockMock])]
			case .swiftPackagePlugin:
				Self.clockFiles(importing: imports)
			}
			#expect(output.modules["App"]?.generatedFiles == expectedFiles, "\(integration)")
		}
	}

	// MARK: One module imported with different levels

	@Test(arguments: ImportCompileMode.withoutInternalImportsByDefault)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsInternal_whenTwoFilesImportModuleAtPublicAndInternal(compileMode: ImportCompileMode) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.clockFixture(rootImports: "import SafeDI\npublic import Foundation", clockImports: "import SafeDI\ninternal import Foundation"),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: compileMode.settings,
		)
		let imports = Self.importBlock([
			Self.importLine(module: "Foundation", spelled: "internal import Foundation"),
			Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
		])
		#expect(output.generatedFiles == Self.clockFiles(importing: imports))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsNoLevel_whenFilesImportModuleWithNoLevelAndPublicUnderInternalImportsByDefault() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.clockFixture(rootImports: "import SafeDI\nimport Foundation", clockImports: "import SafeDI\npublic import Foundation"),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: ImportCompileMode.swift6WithInternalImportsByDefault.settings,
		)
		let imports = Self.importBlock([
			Self.importLine(module: "Foundation", spelled: "import Foundation"),
			Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
		])
		#expect(output.generatedFiles == Self.clockFiles(importing: imports))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsInternal_whenFilesImportModuleWithNoLevelAndInternalUnderInternalImportsByDefault() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.clockFixture(rootImports: "import SafeDI\nimport Foundation", clockImports: "import SafeDI\ninternal import Foundation"),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: ImportCompileMode.swift6WithInternalImportsByDefault.settings,
		)
		let imports = Self.importBlock([
			Self.importLine(module: "Foundation", spelled: "internal import Foundation"),
			Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
		])
		#expect(output.generatedFiles == Self.clockFiles(importing: imports))
	}

	// MARK: Imports inside `#if`

	@Test(arguments: ImportCompileMode.allCases, [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsInternal_whenLevelIsSpelledOnImportInsideIfConfig(compileMode: ImportCompileMode, scanSeesCondition: Bool) async throws {
		// A block that guards only imports consults `FEATURE`, so scan's cache keeps it as source. When the build settings
		// give `generate` another value for `FEATURE` than scan had, `generate` evaluates the block again: the level it
		// spells is still the file's own.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.clockFixture(
				rootImports: "import SafeDI",
				clockImports: "import SafeDI\n#if FEATURE\ninternal import Foundation\n#endif",
			),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: scanSeesCondition ? ["FEATURE"] : [],
			buildSettingArguments: scanSeesCondition ? [] : ["--build-setting-active-compilation-conditions=[FEATURE]", "--build-setting-other-swift-flags=[]"],
			verificationCompilationConditions: ["FEATURE"],
			verificationCompilerSettings: compileMode.settings,
		)
		let imports = Self.importBlock([
			Self.importLine(module: "Foundation", spelled: "internal import Foundation"),
			Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
		])
		#expect(output.generatedFiles == Self.clockFiles(importing: imports))
	}

	@Test(arguments: ImportCompileMode.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsInternal_whenLevelIsSpelledOnImportInsideIfConfigGuardingDeclaration(compileMode: ImportCompileMode) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.clockFixture(
				rootImports: "import SafeDI",
				clockImports: "import SafeDI",
				clockDeclarationPrefix: "#if FEATURE\ninternal import Foundation\n",
				clockDeclarationSuffix: "\n#endif",
			),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["FEATURE"],
			verificationCompilerSettings: compileMode.settings,
		)
		let imports = Self.importBlock([
			Self.importLine(module: "Foundation", spelled: "internal import Foundation"),
			Self.importLine(module: "SafeDI", spelled: "import SafeDI"),
		])
		let assertion = """
		#if !(FEATURE)
		#error("SafeDI scanned this module assuming `#if FEATURE` was active, but it is inactive in this compilation. Report the conditions this target compiles with to SafeDITool, as the \\"Reporting active conditions\\" section of the SafeDI manual describes for your build system.")
		#endif
		"""
		#expect(output.generatedFiles == [
			"Clock+SafeDIMock.swift": Self.file(importing: imports, bodies: [assertion, Self.clockMock]),
			"Root+SafeDI.swift": Self.file(importing: imports, bodies: [assertion, Self.clockRootTree]),
			"SafeDIMockConfiguration.swift": Self.file(importing: imports, bodies: [assertion, ""]),
		])
	}

	// MARK: The module's own files decide

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_ignoresLevelDependencyFileSpells_whenPluginReadsDependencyFiles(writesTargetGraph: Bool) async throws {
		// The plugin's CSV lists `Core`'s files too. `Core` imports Foundation `internal`, which says nothing of `App`,
		// whose files import Foundation with no level: `App`'s generated files must too, or `App`'s own import becomes
		// ambiguous. `App` spells a level on SafeDI, so its generated files decide every import's level.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Core",
					packageName: "Shop",
					swiftFileContent: [
						"""
						public import SafeDI
						internal import Foundation

						@Instantiable
						public final class Clock: Instantiable {
						    public init() {
						        start = Date()
						    }

						    let start: Date
						}
						""",
					],
					compilerSettings: ImportCompileMode.swift6.settings,
				),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContent: [
						"""
						internal import SafeDI
						import Foundation
						import Core

						@Instantiable(isRoot: true)
						final class Root: Instantiable {
						    init(clock: Clock, start: Date = Date()) {
						        self.clock = clock
						        self.start = start
						    }

						    @Instantiated let clock: Clock
						    let start: Date
						}
						""",
					],
					dependencies: ["Core"],
					compilerSettings: ImportCompileMode.swift6.settings,
				),
			],
			integration: .swiftPackagePlugin,
			writesTargetGraph: writesTargetGraph,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"Root+SafeDI.swift": Self.file(importing: Self.importBlock([
				Self.importLine(module: "Core", spelled: "import Core"),
				Self.importLine(module: "Foundation", spelled: "import Foundation"),
				Self.importLine(module: "SafeDI", spelled: "internal import SafeDI"),
			]), bodies: [
				"""
				extension Root {
				    public convenience init() {
				        let clock = Clock()
				        self.init(clock: clock)
				    }
				}
				""",
			]),
		])
	}

	// MARK: Module info

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_recordsImportLevelAndItsFileInModuleInfo_whenFileSpellsLevel() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.clockFixture(rootImports: "import SafeDI\npublic import Foundation", clockImports: "import SafeDI\ninternal import Foundation"),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "Example", "--package-name", "Example"],
			verificationCompilerSettings: ImportCompileMode.swift6.settings,
		)
		let rootFilePath = output.fixtures["Root.swift"]
		let clockFilePath = output.fixtures["Clock.swift"]
		let expectedImports = [
			ImportStatement(moduleName: "Foundation", accessLevel: .internal, sourceFilePath: clockFilePath),
			ImportStatement(moduleName: "Foundation", accessLevel: .public, sourceFilePath: rootFilePath),
			ImportStatement(moduleName: "SafeDI"),
		]
		#expect(try output.writtenModuleInfo.imports == expectedImports)
		#expect(try output.writtenModuleInfo.mockImports == expectedImports)
		// What `generate` wrote reads back the same.
		let readModuleInfo = try ModuleInfoFile(moduleInfoData: Data(contentsOf: URL(fileURLWithPath: output.writtenModuleInfoOutputPath)))
		#expect(readModuleInfo.imports == expectedImports)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// How a cell's module is compiled: the language mode, and whether `InternalImportsByDefault` is on.
	struct ImportCompileMode: CustomTestStringConvertible, Sendable {
		static let swift6 = ImportCompileMode(swiftLanguageMode: "6", enablesInternalImportsByDefault: false)
		static let swift5 = ImportCompileMode(swiftLanguageMode: "5", enablesInternalImportsByDefault: false)
		static let swift6WithInternalImportsByDefault = ImportCompileMode(swiftLanguageMode: "6", enablesInternalImportsByDefault: true)
		static let allCases = [swift6, swift5, swift6WithInternalImportsByDefault]
		static let withoutInternalImportsByDefault = [swift6, swift5]

		let swiftLanguageMode: String
		let enablesInternalImportsByDefault: Bool

		var settings: VerificationCompilerSettings {
			VerificationCompilerSettings(
				swiftLanguageMode: swiftLanguageMode,
				upcomingFeatures: enablesInternalImportsByDefault ? ["InternalImportsByDefault"] : [],
				prependsSafeDIImport: false,
			)
		}

		var testDescription: String {
			"Swift \(swiftLanguageMode)\(enablesInternalImportsByDefault ? " with InternalImportsByDefault" : "")"
		}
	}

	/// The condition a module's mocks are generated under, as its `#SafeDIConfiguration` sets it.
	struct MockConditionCase: CustomTestStringConvertible, Sendable {
		static let allCases = [
			MockConditionCase(configurationArgument: nil, condition: "DEBUG"),
			MockConditionCase(configurationArgument: "\"MOCKS\"", condition: "MOCKS"),
			MockConditionCase(configurationArgument: "nil", condition: nil),
		]

		/// The `mockConditionalCompilation` argument the module's configuration spells, or `nil` for a module that
		/// declares no configuration, whose mocks are generated under `DEBUG`.
		let configurationArgument: String?
		/// The condition the generated mocks are wrapped in, or `nil` for none.
		let condition: String?

		var testDescription: String {
			configurationArgument.map { "mockConditionalCompilation: \($0)" } ?? "no configuration"
		}

		var configurationFiles: [String: String] {
			if let configurationArgument {
				["SafeDIConfiguration.swift": "import SafeDI\n\n#SafeDIConfiguration(mockConditionalCompilation: \(configurationArgument))"]
			} else {
				[:]
			}
		}

		/// The condition the compile defines so that the mocks compile, beside `DEBUG`, which it always defines.
		var fixtureCondition: String? {
			condition == "DEBUG" ? nil : condition
		}

		var holderPublicMock: String {
			wrapped("""
			extension Holder {
			    /// Overrides for the mock dependency tree.
			    public struct SafeDIOverrides {
			        public init(
			            child: __safeDI_Feature_Child_MockConfiguration = .init()
			        ) {
			            self.child = child
			        }

			        public let child: __safeDI_Feature_Child_MockConfiguration
			    }

			    public static func mock(
			        started: Date? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Holder {
			        let started = started ?? (Date())
			        func __safeDI_child() -> Child {
			            return Child.__safeDI_init(date: safeDIOverrides.child.date, safeDIBuilder: safeDIOverrides.child.safeDIBuilder)
			        }
			        let child: Child = __safeDI_child()
			        return Holder(child: child, started: started)
			    }
			}

			extension Holder {
			    public enum __safeDI_Holder_mock_D99CE8F9AE8D1020 {}
			}
			""")
		}

		/// The module-level configuration of `Child`, which the configuration's code ends with a newline after.
		var childPublicConfiguration: String {
			wrapped("""
			/// Configuration for how `Child` is constructed within the public mock trees of module `Feature`.
			public struct __safeDI_Feature_Child_MockConfiguration {
			    public init(
			        date: Date? = nil,
			        _ safeDIBuilder: ((Date) -> Child)? = nil
			    ) {
			        self.date = date
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Child`'s `date`.
			    public let date: Date?
			    /// Overrides how `Child` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Date) -> Child)?
			}

			extension Child {
			    static func __safeDI_init(date: Date?, safeDIBuilder: ((Date) -> Child)?) -> Child {
			        let date = date ?? (Date())
			        return if let safeDIBuilder { safeDIBuilder(date) } else { Child(date: date) }
			    }
			}
			""") + "\n"
		}

		private func wrapped(_ code: String) -> String {
			if let condition {
				"#if \(condition)\n\(code)\n#endif"
			} else {
				code
			}
		}
	}

	/// The import of Foundation `Child.swift` spells, and what every generated file of the module spells for it.
	struct WrittenImport: CustomTestStringConvertible, Sendable {
		static let allCases = [
			WrittenImport(level: "internal", generatedImport: "internal import Foundation"),
			WrittenImport(level: "fileprivate", generatedImport: "internal import Foundation"),
			WrittenImport(level: "private", generatedImport: "internal import Foundation"),
			WrittenImport(level: "package", generatedImport: "internal import Foundation"),
			WrittenImport(level: "public", generatedImport: "import Foundation"),
			WrittenImport(level: nil, generatedImport: "import Foundation"),
		]

		/// The level `Child.swift` spells on its import of Foundation, or `nil` for none.
		let level: String?
		let generatedImport: String

		var testDescription: String {
			level ?? "no level"
		}

		/// Whether `Child`'s initializer can name a Foundation type: a `fileprivate` or `private` import lets only
		/// declarations of that level name one, so `Child` uses Foundation in its body alone.
		private var namesFoundationTypeInDeclarations: Bool {
			level != "fileprivate" && level != "private"
		}

		var child: String {
			let foundationImport = level.map { "\($0) import Foundation" } ?? "import Foundation"
			return if namesFoundationTypeInDeclarations {
				"""
				import SafeDI
				\(foundationImport)

				@Instantiable(generateMock: true)
				final class Child: Instantiable {
				    init(date: Date = Date()) {
				        self.date = date
				    }

				    let date: Date
				}
				"""
			} else {
				"""
				import SafeDI
				\(foundationImport)

				@Instantiable(generateMock: true)
				final class Child: Instantiable {
				    init() {
				        identifier = UUID().uuidString
				    }

				    let identifier: String
				}
				"""
			}
		}

		var childMock: String {
			if namesFoundationTypeInDeclarations {
				"""
				#if DEBUG
				extension Child {
				    static func mock(
				        date: Date = Date()
				    ) -> Child {
				        return Child(date: date)
				    }
				}
				#endif

				#if DEBUG
				extension Child {
				    /// Configuration for how this type is constructed within a mock tree.
				    struct SafeDIMockConfiguration {
				        init(
				            date: Date = Date(),
				            _ safeDIBuilder: ((Date) -> Child)? = nil
				        ) {
				            self.date = date
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let date: Date
				        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
				        let safeDIBuilder: ((Date) -> Child)?
				    }
				}
				#endif
				"""
			} else {
				"""
				#if DEBUG
				extension Child {
				    static func mock() -> Child {
				        Child()
				    }
				}
				#endif
				"""
			}
		}

		var rootMock: String {
			let childOverride = namesFoundationTypeInDeclarations ? "Child.SafeDIMockConfiguration" : "(() -> Child)?"
			let childOverrideDefault = namesFoundationTypeInDeclarations ? ".init()" : "nil"
			let childConstruction = if namesFoundationTypeInDeclarations {
				"""
				        func __safeDI_child() -> Child {
				            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(safeDIOverrides.child.date) } else { Child(date: safeDIOverrides.child.date) }
				        }
				        let child: Child = __safeDI_child()
				"""
			} else {
				"""
				        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder() } else { Child() }
				"""
			}
			return """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            child: \(childOverride) = \(childOverrideDefault),
			            panel: Panel.SafeDIMockConfiguration = .init()
			        ) {
			            self.child = child
			            self.panel = panel
			        }

			        let child: \(childOverride)
			        let panel: Panel.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			\(childConstruction)
			        func __safeDI_panel() -> Panel {
			            let gauge = if let safeDIBuilder = safeDIOverrides.panel.gauge { safeDIBuilder() } else { Gauge() }
			            return if let safeDIBuilder = safeDIOverrides.panel.safeDIBuilder { safeDIBuilder(gauge) } else { Panel(gauge: gauge) }
			        }
			        let panel: Panel = __safeDI_panel()
			        return Root(child: child, panel: panel)
			    }
			}
			#endif
			"""
		}
	}

	/// The `#if canImport` block that imports `module` as `spelling` spells it.
	private static func importLine(module: String, spelled spelling: String) -> String {
		"""
		#if canImport(\(module))
		\(spelling)
		#endif
		"""
	}

	/// The `#if canImport` block that imports `module` as `spelling` spells it where `condition`, the module's mock
	/// condition, is active, and as `otherwise` spells it where it is not.
	private static func importLine(module: String, spelled spelling: String, where condition: String, otherwise: String) -> String {
		"""
		#if canImport(\(module))
		#if \(condition)
		\(spelling)
		#else
		\(otherwise)
		#endif
		#endif
		"""
	}

	private static func importBlock(_ lines: [String]) -> String {
		lines.joined(separator: "\n")
	}

	/// A generated file: the header, `imports`, and `bodies`, as `generate` joins them.
	private static func file(importing imports: String, bodies: [String]) -> String {
		generatedFileHeader + imports + "\n\n" + bodies.joined(separator: "\n\n")
	}

	private static let root = """
	import SafeDI

	@Instantiable(isRoot: true, generateMock: true)
	final class Root: Instantiable {
	    init(child: Child, panel: Panel) {
	        self.child = child
	        self.panel = panel
	    }

	    @Instantiated let child: Child
	    @Instantiated let panel: Panel
	}
	"""

	private static let panelSeam = """
	public import SafeDI

	@Instantiable(generateDependencyTree: true)
	public struct Panel: Instantiable {
	    public init(gauge: Gauge) {
	        self.gauge = gauge
	    }

	    @Instantiated let gauge: Gauge
	}
	"""

	private static let gaugePublicMock = """
	public import SafeDI

	@Instantiable(generateMock: .public)
	public struct Gauge: Instantiable {
	    public init() {}
	}
	"""

	private static let panelTree = """
	extension Panel {
	    public init() {
	        let gauge = Gauge()
	        self.init(gauge: gauge)
	    }
	}

	extension Panel {
	    public enum __safeDI_Panel_CBF29CE484222325 {}
	}
	"""

	private static let rootTree = """
	extension Root {
	    public convenience init() {
	        let child = Child()
	        func __safeDI_panel() -> Panel {
	            _ = Panel.__safeDI_Panel_CBF29CE484222325.self
	            return Panel()
	        }
	        let panel: Panel = __safeDI_panel()
	        self.init(child: child, panel: panel)
	    }
	}
	"""

	private static let gaugeMock = """
	#if DEBUG
	extension Gauge {
	    public static func mock() -> Gauge {
	        Gauge()
	    }
	}

	extension Gauge {
	    public enum __safeDI_Gauge_mock_CBF29CE484222325 {}
	}
	#endif
	"""

	private static let panelConfiguration = """
	#if DEBUG
	extension Panel {
	    /// Configuration for how this type is constructed within a mock tree.
	    struct SafeDIMockConfiguration {
	        init(
	            gauge: (() -> Gauge)? = nil,
	            _ safeDIBuilder: ((Gauge) -> Panel)? = nil
	        ) {
	            self.gauge = gauge
	            self.safeDIBuilder = safeDIBuilder
	        }

	        let gauge: (() -> Gauge)?
	        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
	        let safeDIBuilder: ((Gauge) -> Panel)?
	    }
	}
	#endif

	"""

	private static let feedTree = """
	extension Feed {
	    public init(url __safeDI_url: @autoclosure @escaping () -> URL) {
	        let url = LazilyInstantiated<URL>(__safeDI_url)
	        let loader = Loader(url: url.instance)
	        self.init(loader: loader)
	    }
	}

	extension Feed {
	    public enum __safeDI_Feed_BB233D7C144A6DFA {}
	}
	"""

	private static let shelfTree = """
	extension Shelf {
	    package init(directory __safeDI_directory: @autoclosure @escaping () -> URL) {
	        let directory = LazilyInstantiated<URL>(__safeDI_directory)
	        let cache = Cache(directory: directory.instance)
	        self.init(cache: cache)
	    }
	}

	extension Shelf {
	    public enum __safeDI_Shelf_3AB86B822A19F0A5 {}
	}
	"""

	private static let feedGaugeTree = """
	extension Feed {
	    public init() {
	        let gauge = Gauge()
	        self.init(gauge: gauge)
	    }
	}

	extension Feed {
	    public enum __safeDI_Feed_CBF29CE484222325 {}
	}
	"""

	/// The seam `Session`'s initializer. The one file of a module that reads its dependencies' module info, which SafeDI
	/// does not read every first-party module from, names the type it reads no declaration of in a comment.
	/// The tree of cell 23a's `Screen`, which calls `Mid`'s seam `Session`.
	private static func screenTreeCallingMidsSession(integration: MultiModuleIntegration) -> String {
		// A plugin's call carries the plugin comment, and a plugin's run reads every first-party module, so it names no
		// type it reads no declaration of.
		let pluginComment = integration.seamCallComment(type: "Session", declaringModule: "Mid")
		let unreadTypeComment = integration == .moduleInfo ? "    // SafeDI counts `Window` as `public`: no module it reads declares it narrower. If `Window` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.\n" : ""
		return """
		extension Screen {
		\(unreadTypeComment)    public init(window __safeDI_window: @autoclosure @escaping () -> Window) {
		        let window = LazilyInstantiated<Window>(__safeDI_window)
		        func __safeDI_session() -> Session {
		            _ = Session.__safeDI_Session_48814468D463AD3C.self\(pluginComment)
		            return Session(window: window.instance)
		        }
		        let session: Session = __safeDI_session()
		        self.init(session: session)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_48814468D463AD3C {}
		}
		"""
	}

	/// The public mock of cell 23b's `Screen`, which calls `Mid`'s public mock of `Service`.
	private static func screenMockCallingMidsService(integration: MultiModuleIntegration) -> String {
		// A plugin's call carries the plugin comment, and a plugin's run reads every first-party module, so it names no
		// type it reads no declaration of.
		let pluginComment = integration.seamCallComment(type: "Service", declaringModule: "Mid")
		let unreadTypeComment = integration == .moduleInfo ? "    // SafeDI counts `Window` as `public`: no module it reads declares it narrower. If `Window` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.\n" : ""
		return """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            service: Service.SafeDIOverrides = .init()
		        ) {
		            self.service = service
		        }

		        public let service: Service.SafeDIOverrides
		    }

		\(unreadTypeComment)    public static func mock(
		        window: Window,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Service.__safeDI_Service_mock_3CD7306A9A29A31B.self\(pluginComment)
		        let service = Service.mock(window: window, safeDIOverrides: safeDIOverrides.service)
		        return Screen(service: service)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_3CD7306A9A29A31B {}
		}
		#endif
		"""
	}

	private static func sessionTree(integration: MultiModuleIntegration) -> String {
		let unreadTypeComment = switch integration {
		case .moduleInfo:
			"    // SafeDI counts `Window` as `public`: no module it reads declares it narrower. If `Window` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.\n"
		case .swiftPackagePlugin:
			""
		}
		return """
		extension Session {
		\(unreadTypeComment)    public init(url __safeDI_url: @autoclosure @escaping () -> URL, window __safeDI_window: @autoclosure @escaping () -> Window) {
		        let url = LazilyInstantiated<URL>(__safeDI_url)
		        let window = LazilyInstantiated<Window>(__safeDI_window)
		        let vault = Vault(window: window.instance)
		        let loader = Loader(url: url.instance)
		        self.init(vault: vault, loader: loader)
		    }
		}

		extension Session {
		    public enum __safeDI_Session_602EAC63224D3199 {}
		}
		"""
	}

	private static let childPublicMock = """
	#if DEBUG
	extension Child {
	    public static func mock(
	        date: Date? = nil
	    ) -> Child {
	        let date = date ?? (Date())
	        return Child(date: date)
	    }
	}

	extension Child {
	    public enum __safeDI_Child_mock_07065D30E817A8C6 {}
	}
	#endif
	"""

	private static let appRootTree = """
	extension Root {
	    public convenience init() {
	        let child = Child()
	        self.init(child: child)
	    }
	}
	"""

	private static let appRootMock = """
	#if DEBUG
	extension Root {
	    /// Overrides for the mock dependency tree.
	    struct SafeDIOverrides {
	        init(
	            child: Child.SafeDIMockConfiguration = .init()
	        ) {
	            self.child = child
	        }

	        let child: Child.SafeDIMockConfiguration
	    }

	    static func mock(
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> Root {
	        func __safeDI_child() -> Child {
	            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(safeDIOverrides.child.date) } else { Child(date: safeDIOverrides.child.date) }
	        }
	        let child: Child = __safeDI_child()
	        return Root(child: child)
	    }
	}
	#endif
	"""

	private static let childConfiguration = """
	#if DEBUG
	extension Child {
	    /// Configuration for how this type is constructed within a mock tree.
	    struct SafeDIMockConfiguration {
	        init(
	            date: Date = Date(),
	            _ safeDIBuilder: ((Date) -> Child)? = nil
	        ) {
	            self.date = date
	            self.safeDIBuilder = safeDIBuilder
	        }

	        let date: Date
	        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
	        let safeDIBuilder: ((Date) -> Child)?
	    }
	}
	#endif

	"""

	/// `Root` instantiating `Clock`, whose mock is generated, each file importing as given.
	private static func clockFixture(
		rootImports: String,
		clockImports: String,
		clockDeclarationPrefix: String = "",
		clockDeclarationSuffix: String = "",
	) -> [String] {
		[
			"""
			\(rootImports)

			@Instantiable(isRoot: true)
			final class Root: Instantiable {
			    init(clock: Clock) {
			        self.clock = clock
			    }

			    @Instantiated let clock: Clock
			}
			""",
			"""
			\(clockImports)

			\(clockDeclarationPrefix)@Instantiable(generateMock: true)
			final class Clock: Instantiable {
			    init(start: Date = Date()) {
			        self.start = start
			    }

			    let start: Date
			}\(clockDeclarationSuffix)
			""",
		]
	}

	/// The files `clockFixture` generates, each importing `imports`.
	private static func clockFiles(importing imports: String) -> [String: String] {
		[
			"Clock+SafeDIMock.swift": file(importing: imports, bodies: [clockMock]),
			"Root+SafeDI.swift": file(importing: imports, bodies: [clockRootTree]),
			"SafeDIMockConfiguration.swift": file(importing: imports, bodies: [""]),
		]
	}

	private static let clockRootTree = """
	extension Root {
	    public convenience init() {
	        let clock = Clock()
	        self.init(clock: clock)
	    }
	}
	"""

	private static let clockMock = """
	#if DEBUG
	extension Clock {
	    static func mock(
	        start: Date = Date()
	    ) -> Clock {
	        return Clock(start: start)
	    }
	}
	#endif
	"""
}
