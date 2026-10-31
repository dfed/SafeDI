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

/// How `generate` checks that the code it generates in a module can construct each type: a type and the method that
/// constructs it can be `internal` where their own module constructs them, `package` where another module of their
/// package does, and must be `public` where another package does.
struct SafeDIToolAccessEnforcementTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Constructions that compile

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_constructsPackageType_whenAnotherModuleOfItsPackageConstructsIt(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.feature(
					inPackage: "Shop",
					declaring: """
					@Instantiable
					package final class Service: Instantiable {
					    package init() {}
					}
					""",
				),
				Self.app(inPackage: "Shop"),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		#expect(try #require(output.modules["App"]).generatedFiles == Self.appGeneratedFiles(under: integration, code: """
		extension Root {
		    public convenience init() {
		        let service = Service()
		        self.init(service: service)
		    }
		}
		"""))
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_constructsInternalType_whenItsOwnModuleConstructsIt(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContent: [
						"""
						@Instantiable
						final class Service: Instantiable {
						    init() {}
						}
						""",
						"""
						@Instantiable(isRoot: true)
						final class Root: Instantiable {
						    init(service: Service) {
						        self.service = service
						    }
						    @Instantiated let service: Service
						}
						""",
					],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let code = """
		extension Root {
		    public convenience init() {
		        let service = Service()
		        self.init(service: service)
		    }
		}
		"""
		let expectedGeneratedFiles = switch integration {
		case .moduleInfo:
			["App.swift": generatedFileHeader + code]
		case .swiftPackagePlugin:
			["Root+SafeDI.swift": generatedFileHeader + code]
		}
		#expect(try #require(output.modules["App"]).generatedFiles == expectedGeneratedFiles)
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assumesPackageAccessWithComment_whenModuleMembershipIsUnknown() async throws {
		// Without the target graph, as for the Xcode project plugin, the tool cannot tell which module declares
		// `Service`, so it accepts a `package` declaration and says so where it constructs it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.feature(
					inPackage: "Shop",
					declaring: """
					@Instantiable
					package final class Service: Instantiable {
					    package init() {}
					}
					""",
				),
				Self.app(inPackage: "Shop"),
			],
			integration: .swiftPackagePlugin,
			writesTargetGraph: false,
			filesToDelete: &filesToDelete,
		)

		#expect(try #require(output.modules["App"]).generatedFiles == Self.appGeneratedFiles(under: .swiftPackagePlugin, code: """
		extension Root {
		    public convenience init() {
		        let service = Service() // SafeDI could not verify that Service is in this package; `package` access is assumed.
		        self.init(service: service)
		    }
		}
		"""))
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assumesPackageAccessWithCommentOnEachConstructionLine_whenModuleMembershipIsUnknown() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						"""
						@Instantiable
						package final class Service: Instantiable {
						    package init() {}
						}
						""",
						"""
						@Instantiable
						package final class Engine: Instantiable {
						    package init(service: Service) {
						        self.service = service
						    }
						    @Instantiated let service: Service
						}
						""",
					],
				),
				ModuleFixture(
					name: "TestSupport",
					packageName: "Shop",
					swiftFileContentByFilePath: [
						"ServiceMock.swift": """
						import Feature

						@Instantiable(mockOnly: true)
						package extension Service {
						    static func mock() -> Service { Service() }
						}
						""",
					],
					dependencies: ["Feature"],
				),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContent: [
						"""
						import Feature

						@Instantiable(isRoot: true)
						final class Root: Instantiable {
						    init(engine: Engine, serviceBuilder: Instantiator<Service>, lazyService: LazilyInstantiated<Service>) {
						        self.engine = engine
						        self.serviceBuilder = serviceBuilder
						        self.lazyService = lazyService
						    }
						    @Instantiated let engine: Engine
						    @Instantiated let serviceBuilder: Instantiator<Service>
						    @Instantiated let lazyService: LazilyInstantiated<Service>
						}
						""",
						"""
						import Feature
						import TestSupport

						@Instantiable(generateMock: true)
						final class Screen: Instantiable {
						    init(engine: Engine) {
						        self.engine = engine
						    }
						    @Instantiated let engine: Engine
						}
						""",
					],
					swiftFileContentByFilePath: [
						"SafeDIConfiguration.swift": """
						#SafeDIConfiguration(additionalMocksToGenerate: ["Engine"])
						""",
					],
					dependencies: ["Feature", "TestSupport"],
				),
			],
			integration: .swiftPackagePlugin,
			writesTargetGraph: false,
			filesToDelete: &filesToDelete,
		)

		// Every line that constructs a type of another module says so: in a builder function, an instantiator's, and a
		// lazily instantiated dependency's; in a mock's tree, with an initializer and with a hand-written mock; and the
		// line that constructs a listed mock's root. A `SafeDIMockConfiguration` constructs nothing.
		let header = generatedFileHeader + Self.importBlock("Feature") + "\n" + Self.importBlock("TestSupport") + "\n\n"
		let assumption = { (typeName: String) in "// SafeDI could not verify that \(typeName) is in this package; `package` access is assumed." }
		#expect(try #require(output.modules["App"]).generatedFiles == [
			"Root+SafeDI.swift": header + """
			extension Root {
			    public convenience init() {
			        func __safeDI_engine() -> Engine {
			            let service = Service() \(assumption("Service"))
			            return Engine(service: service) \(assumption("Engine"))
			        }
			        let engine: Engine = __safeDI_engine()
			        func __safeDI_serviceBuilder() -> Service {
			            Service() \(assumption("Service"))
			        }
			        let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
			        func __safeDI_lazyService() -> Service {
			            Service() \(assumption("Service"))
			        }
			        let lazyService = LazilyInstantiated<Service>(__safeDI_lazyService)
			        self.init(engine: engine, serviceBuilder: serviceBuilder, lazyService: lazyService)
			    }
			}
			""",
			"Screen+SafeDIMock.swift": header + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            engine: Engine.SafeDIMockConfiguration = .init()
			        ) {
			            self.engine = engine
			        }

			        let engine: Engine.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_engine() -> Engine {
			            let service = if let safeDIBuilder = safeDIOverrides.engine.service { safeDIBuilder() } else { Service.mock() } \(assumption("Service"))
			            return if let safeDIBuilder = safeDIOverrides.engine.safeDIBuilder { safeDIBuilder(service) } else { Engine(service: service) } \(assumption("Engine"))
			        }
			        let engine: Engine = __safeDI_engine()
			        return Screen(engine: engine)
			    }
			}
			#endif
			""",
			"Engine+SafeDIMock.swift": header + """
			#if DEBUG
			extension Engine {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: (() -> Service)? = nil
			        ) {
			            self.service = service
			        }

			        let service: (() -> Service)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Engine {
			        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service.mock() } \(assumption("Service"))
			        return Engine(service: service) \(assumption("Engine"))
			    }
			}
			#endif

			#if DEBUG
			extension Engine {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            service: (() -> Service)? = nil,
			            _ safeDIBuilder: ((Service) -> Engine)? = nil
			        ) {
			            self.service = service
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let service: (() -> Service)?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((Service) -> Engine)?
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": header,
		])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assumesPackageAccessWithCommentAfterForwardedParameter_whenItsDefaultCallsHandWrittenMockOfUnknownModule() async throws {
		// `mock()` defaults `user` to `User.mock()`, which constructs `User` as any line of a mock's tree does, so its
		// line ends with the same comment, after the comma that ends the parameter.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.feature(
					inPackage: "Shop",
					declaring: """
					@Instantiable
					public final class User: Instantiable {
					    public init() {}
					    package static func mock() -> User { User() }
					}
					""",
				),
				Self.app(inPackage: "Shop", declaring: """
				import Feature

				@Instantiable(generateMock: true)
				final class Profile: Instantiable {
				    init(user: User, name: String = "") {
				        self.user = user
				    }
				    @Forwarded let user: User
				}
				"""),
			],
			integration: .swiftPackagePlugin,
			writesTargetGraph: false,
			filesToDelete: &filesToDelete,
		)

		let header = generatedFileHeader + Self.importBlock("Feature") + "\n\n"
		#expect(try #require(output.modules["App"]).generatedFiles == [
			"Profile+SafeDIMock.swift": header + """
			#if DEBUG
			extension Profile {
			    static func mock(
			        user: User = User.mock(), // SafeDI could not verify that User is in this package; `package` access is assumed.
			        name: String = ""
			    ) -> Profile {
			        return Profile(user: user, name: name)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": header,
		])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_constructsInternalTypes_whenHandWrittenManifestNamesNoOwnFiles() async throws {
		// A hand-written manifest that names no `mockScopedFilePaths` describes one module, so each of its files is
		// one of the module's own.
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		filesToDelete.append(directory)
		let rootFile = directory.appendingPathComponent("Root.swift")
		try """
		@Instantiable(isRoot: true)
		final class Root: Instantiable {
		    init(service: Service) {
		        self.service = service
		    }
		    @Instantiated let service: Service
		}

		@Instantiable
		final class Service: Instantiable {
		    init() {}
		}
		""".write(to: rootFile, atomically: true, encoding: .utf8)
		let swiftFileCSV = directory.appendingPathComponent("Inputs.csv")
		try rootFile.path.write(to: swiftFileCSV, atomically: true, encoding: .utf8)
		let outputFile = directory.appendingPathComponent("Root+SafeDI.swift")
		let manifestFile = directory.appendingPathComponent("Manifest.json")
		try JSONEncoder().encode(SafeDIToolManifest(dependencyTreeGeneration: [
			.init(inputFilePath: rootFile.path, outputFilePath: outputFile.path),
		])).write(to: manifestFile)

		try await Generate.parse([swiftFileCSV.path, "--swift-manifest", manifestFile.path]).generate()

		#expect(try String(contentsOf: outputFile, encoding: .utf8) == generatedFileHeader + """
		extension Root {
		    public convenience init() {
		        let service = Service()
		        self.init(service: service)
		    }
		}
		""")
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicInstantiateMethod_whenAnotherPackageConstructsTypeThroughInternalExtension(integration: MultiModuleIntegration) async throws {
		// Swift caps no member of an extension by the extension's level, and only warns at a member more permissive
		// than its extension, so another package can call the `public` method.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Toolkit",
					swiftFileContentByFilePath: [
						"Service.swift": """
						public final class Service {}
						extension Service: Instantiable {}

						@Instantiable(conformsElsewhere: true)
						internal extension Service {
						    public static func instantiate() -> Service { Service() }
						}
						""",
					],
				),
				Self.app(inPackage: "Shop"),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		#expect(try #require(output.modules["App"]).generatedFiles == Self.appGeneratedFiles(under: integration, code: """
		extension Root {
		    public convenience init() {
		        let service: Service = Service.instantiate()
		        self.init(service: service)
		    }
		}
		"""))
		try expectEveryModuleCompiled(output)
	}

	// MARK: Tests – Constructions that do not compile

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWithFixItReplacingModifierWithPackage_whenAnotherModuleOfItsPackageConstructsInternalType(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = Self.declarationPath(of: "Service.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(servicePath):2:1: error: `Service` is `internal`, so module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` to fix.
			\(servicePath):2:1-2:9: fixit: package
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(
						inPackage: "Shop",
						declaring: """
						@Instantiable
						internal final class Service: Instantiable {
						    package init() {}
						}
						""",
					),
					Self.app(inPackage: "Shop"),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWithFixItInsertingModifier_whenInitializerSpellsNoModifier(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = Self.declarationPath(of: "Service.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(servicePath):3:5: error: `Service`’s initializer is `internal`, so module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix.
			\(servicePath):3:5-3:5: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(
						inPackage: "Shop",
						declaring: """
						@Instantiable
						package final class Service: Instantiable {
						    init() {}
						}
						""",
					),
					Self.app(inPackage: "Shop"),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWithPublicFixIt_whenAnotherPackageConstructsPackageType(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = Self.declarationPath(of: "Service.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(servicePath):2:1: error: `Service` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Service` `public` to fix.
			\(servicePath):2:1-2:8: fixit: public
			\(servicePath):3:5: error: `Service`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(servicePath):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(
						inPackage: "Toolkit",
						declaring: """
						@Instantiable
						package final class Service: Instantiable {
						    package init() {}
						}
						""",
					),
					Self.app(inPackage: "Shop"),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtEnclosingType_whenTypeEnclosingConstructedTypeIsInternal() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: `Namespace`, which encloses `Namespace.Service`, is `internal`, so module `App`, another module of the same package, cannot construct `Namespace.Service` in the code SafeDI generates. Make `Namespace` `package` to fix.
			\(fixtures["Feature"]!["Service.swift"]):1:1-1:1: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(
						inPackage: "Shop",
						declaring: """
						enum Namespace {
						    @Instantiable
						    public final class Service: Instantiable {
						        public init() {}
						    }
						}
						""",
					),
					Self.app(inPackage: "Shop", serviceType: "Namespace.Service"),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsEnclosingTypeOnce_whenSeveralTypesItEnclosesAreConstructed() async {
		// `Zulu` is declared before `Alpha`, so the error names it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Namespace.swift"]):1:1: error: `Namespace`, which encloses `Namespace.Zulu`, is `internal`, so module `App`, another module of the same package, cannot construct `Namespace.Zulu` in the code SafeDI generates. Make `Namespace` `package` to fix.
			\(fixtures["Feature"]!["Namespace.swift"]):1:1-1:1: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"Namespace.swift": """
							enum Namespace {
							    @Instantiable
							    public final class Zulu: Instantiable {
							        public init() {}
							    }

							    @Instantiable
							    public final class Alpha: Instantiable {
							        public init() {}
							    }
							}
							""",
						],
					),
					Self.app(inPackage: "Shop", declaring: """
					import Feature

					@Instantiable(isRoot: true)
					final class Root: Instantiable {
					    init(alpha: Namespace.Alpha, zulu: Namespace.Zulu) {
					        self.alpha = alpha
					        self.zulu = zulu
					    }

					    @Instantiated let alpha: Namespace.Alpha
					    @Instantiated let zulu: Namespace.Zulu
					}
					"""),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtExtension_whenConstructedTypeTakesInternalFromExtensionItIsDirectlyInside() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):2:1: error: The extension that declares `Namespace.Service` is `internal`, so module `App`, another module of the same package, cannot construct `Namespace.Service` in the code SafeDI generates. Make the extension `package` to fix.
			\(fixtures["Feature"]!["Service.swift"]):2:1-2:9: fixit: package
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"Service.swift": """
							public enum Namespace {}
							internal extension Namespace {
							    @Instantiable
							    final class Service: Instantiable {
							        public init() {}
							    }
							}
							""",
						],
					),
					Self.app(inPackage: "Shop", serviceType: "Namespace.Service"),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtExtension_whenTypeEnclosingConstructedTypeTakesInternalFromExtensionItIsDirectlyInside() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):2:1: error: The extension that declares `Namespace.Middle`, which encloses `Namespace.Middle.Service`, is `internal`, so module `App`, another module of the same package, cannot construct `Namespace.Middle.Service` in the code SafeDI generates. Make the extension `package` to fix.
			\(fixtures["Feature"]!["Service.swift"]):2:1-2:9: fixit: package
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"Service.swift": """
							public enum Namespace {}
							internal extension Namespace {
							    enum Middle {
							        @Instantiable
							        public final class Service: Instantiable {
							            public init() {}
							        }
							    }
							}
							""",
						],
					),
					Self.app(inPackage: "Shop", serviceType: "Namespace.Middle.Service"),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtExtension_whenInstantiateMethodSpellsNoModifierAndItsExtensionIsInternal() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):5:1: error: The extension that declares `Service.instantiate()` is `internal`, so module `App`, another module of the same package, cannot call `Service.instantiate()` in the code SafeDI generates. Make the extension `package` to fix.
			\(fixtures["Feature"]!["Service.swift"]):5:1-5:9: fixit: package
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"Service.swift": """
							public final class Service {}
							extension Service: Instantiable {}

							@Instantiable(conformsElsewhere: true)
							internal extension Service {
							    static func instantiate() -> Service { Service() }
							}
							""",
						],
					),
					Self.app(inPackage: "Shop"),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWithPublicFixItAtExtension_whenAnotherPackageCallsInstantiateMethodTakingPackageFromItsExtension(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = Self.declarationPath(of: "Service.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(servicePath):5:1: error: The extension that declares `Service.instantiate()` is `package`, so module `App`, in another package, cannot call `Service.instantiate()` in the code SafeDI generates. Make the extension `public` to fix.
			\(servicePath):5:1-5:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Feature",
						packageName: "Toolkit",
						swiftFileContentByFilePath: [
							"Service.swift": """
							public final class Service {}
							extension Service: Instantiable {}

							@Instantiable(conformsElsewhere: true)
							package extension Service {
							    static func instantiate() -> Service { Service() }
							}
							""",
						],
					),
					Self.app(inPackage: "Shop"),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtInstantiateMethod_whenNeitherMethodNorItsExtensionSpellsModifier() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):5:5: error: `Service.instantiate()` is `internal`, so module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make `Service.instantiate()` `package` to fix.
			\(fixtures["Feature"]!["Service.swift"]):5:5-5:5: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"Service.swift": """
							public final class Service {}

							@Instantiable
							extension Service: Instantiable {
							    static func instantiate() -> Service { Service() }
							}
							""",
						],
					),
					Self.app(inPackage: "Shop"),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWithInternalFixIt_whenOwnMockConstructsTypeNestedInPrivateType() async {
		// The generated mock is in another file of the module, which cannot see into a `private` type.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Service.swift"]):1:1: error: `Namespace`, which encloses `Namespace.Service`, is `private`, so the code SafeDI generates in another file of module `App` cannot construct `Namespace.Service`. Make `Namespace` `internal` to fix.
			\(fixtures["App"]!["Service.swift"]):1:1-1:8: fixit: internal
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [
							"""
							private enum Namespace {
							    @Instantiable(generateMock: true)
							    final class Service: Instantiable {
							        init() {}
							    }
							}
							""",
						],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtReferenceNamingDeclaringModule_whenDeclaringFileCannotBeRead() async {
		// A sandboxed Bazel action is handed `Feature`'s `.safedi` but not its files, so the error is reported where
		// `App` instantiates `Service`, and names the module that must change.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):8:5: error: `Service` is `internal` in module `Feature`, so module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` in module `Feature` to fix.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(
						inPackage: "Shop",
						declaring: """
						@Instantiable
						final class Service: Instantiable {
						    package init() {}
						}
						""",
						deletesSwiftFilesAfterRunning: true,
					),
					Self.app(inPackage: "Shop"),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtFirstReferenceInSourceOrder_whenSeveralDependenciesConstructTypeWhoseFileCannotBeRead() async {
		// `first` is declared before `second`, but the walk reaches `Service` through `second` first.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):10:5: error: `Service` is `internal` in module `Feature`, so module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` in module `Feature` to fix.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(inPackage: "Shop", declaring: Self.internalServiceWithPackageInitializer, deletesSwiftFilesAfterRunning: true),
					Self.app(inPackage: "Shop", declaring: """
					import Feature

					@Instantiable(isRoot: true)
					final class Root: Instantiable {
					    init(first: Service, second: Service) {
					        self.first = first
					        self.second = second
					    }

					    @Instantiated let first: Service
					    @Instantiated let second: Service
					}
					"""),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsInaccessibleConstructionOnceAtEarliestReference_whenSeveralRootsConstructTypeWhoseFileCannotBeRead() async {
		// Roots are checked in type order, so `Alpha`, in `B.swift`, is checked before `Zulu`, in `A.swift`, whose
		// reference comes first in source order.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["A.swift"]):8:5: error: `Service` is `internal` in module `Feature`, so module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` in module `Feature` to fix.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(inPackage: "Shop", declaring: Self.internalServiceWithPackageInitializer, deletesSwiftFilesAfterRunning: true),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"A.swift": """
							import Feature

							@Instantiable(isRoot: true)
							final class Zulu: Instantiable {
							    init(service: Service) {
							        self.service = service
							    }
							    @Instantiated let service: Service
							}
							""",
							"B.swift": """
							import Feature

							@Instantiable(isRoot: true)
							final class Alpha: Instantiable {
							    init(service: Service) {
							        self.service = service
							    }
							    @Instantiated let service: Service
							}
							""",
						],
						dependencies: ["Feature"],
					),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingPackageOrPublic_whenModuleMembershipIsUnknownAndTypeIsInternal() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = NormalizedFilePath(fixtures["Feature"]!.compilerPath(of: "Service.swift")).path
			return """
			\(servicePath):2:1: error: `Service` is `internal`, so this module, which SafeDI cannot tell is in the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` to fix, or `public` if the two modules are in different packages.
			\(servicePath):2:1-2:1: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(
						inPackage: "Shop",
						declaring: """
						@Instantiable
						final class Service: Instantiable {
						    package init() {}
						}
						""",
					),
					Self.app(inPackage: "Shop"),
				],
				integration: .swiftPackagePlugin,
				writesTargetGraph: false,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenHandWrittenManifestNamesNoOwnFilesAndAdditionalDirectoryDeclaresInternalType() async throws {
		// A hand-written manifest that names no `mockScopedFilePaths` makes the input files the module's own, and a
		// file reached through `additionalDirectoriesToInclude` is not one of them.
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		let additionalDirectory = directory.appendingPathComponent("Additional")
		try FileManager.default.createDirectory(at: additionalDirectory, withIntermediateDirectories: true)
		filesToDelete.append(directory)
		let serviceFile = additionalDirectory.appendingPathComponent("Service.swift")
		try """
		@Instantiable
		final class Service: Instantiable {
		    package init() {}
		}
		""".write(to: serviceFile, atomically: true, encoding: .utf8)
		let configurationFile = directory.appendingPathComponent("SafeDIConfiguration.swift")
		try """
		#SafeDIConfiguration(additionalDirectoriesToInclude: ["\(additionalDirectory.path)"])
		""".write(to: configurationFile, atomically: true, encoding: .utf8)
		let rootFile = directory.appendingPathComponent("Root.swift")
		try """
		@Instantiable(isRoot: true)
		final class Root: Instantiable {
		    init(service: Service) {
		        self.service = service
		    }
		    @Instantiated let service: Service
		}
		""".write(to: rootFile, atomically: true, encoding: .utf8)
		let swiftFileCSV = directory.appendingPathComponent("Inputs.csv")
		try [rootFile.path, configurationFile.path].joined(separator: ",").write(to: swiftFileCSV, atomically: true, encoding: .utf8)
		let manifestFile = directory.appendingPathComponent("Manifest.json")
		try JSONEncoder().encode(SafeDIToolManifest(
			dependencyTreeGeneration: [
				.init(inputFilePath: rootFile.path, outputFilePath: directory.appendingPathComponent("Root+SafeDI.swift").path),
			],
			configurationFilePaths: [configurationFile.path],
		)).write(to: manifestFile)

		do {
			try await Generate.parse([swiftFileCSV.path, "--swift-manifest", manifestFile.path]).generate()
			Issue.record("Did not throw error!")
		} catch {
			#expect("\(error)" == """
			\(serviceFile.path):2:1: error: `Service` is `internal`, so this module, which SafeDI cannot tell is in the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` to fix, or `public` if the two modules are in different packages.
			\(serviceFile.path):2:1-2:1: fixit: package\(" ")
			""")
		}
	}

	// MARK: Tests – Mocks

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenMockConstructsTypeAnotherModuleCannotReach(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = Self.declarationPath(of: "Service.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(servicePath):2:1: error: `Service` is `internal`, so module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` to fix.
			\(servicePath):2:1-2:1: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(inPackage: "Shop", declaring: Self.internalServiceWithPackageInitializer),
					Self.app(inPackage: "Shop", declaring: Self.screenMockedInApp),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsInaccessibleConstructionOnce_whenSeveralMocksConstructIt() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):2:1: error: `Service` is `internal`, so module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` to fix.
			\(fixtures["Feature"]!["Service.swift"]):2:1-2:1: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(inPackage: "Shop", declaring: Self.internalServiceWithPackageInitializer),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [
							Self.screenMockedInApp,
							"""
							import Feature

							@Instantiable(generateMock: true)
							final class Settings: Instantiable {
							    init(service: Service) {
							        self.service = service
							    }
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
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsInaccessibleConstructionOnceAtEarliestReference_whenSeveralMocksConstructTypeWhoseFileCannotBeRead() async {
		// Mock roots are checked in type order, so `Alpha`, in `B.swift`, is checked before `Zulu`, in `A.swift`, whose
		// reference comes first in source order.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["A.swift"]):8:5: error: `Service` is `internal` in module `Feature`, so module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` in module `Feature` to fix.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(inPackage: "Shop", declaring: Self.internalServiceWithPackageInitializer, deletesSwiftFilesAfterRunning: true),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"A.swift": """
							import Feature

							@Instantiable(generateMock: true)
							final class Zulu: Instantiable {
							    init(service: Service) {
							        self.service = service
							    }
							    @Instantiated let service: Service
							}
							""",
							"B.swift": """
							import Feature

							@Instantiable(generateMock: true)
							final class Alpha: Instantiable {
							    init(service: Service) {
							        self.service = service
							    }
							    @Instantiated let service: Service
							}
							""",
						],
						dependencies: ["Feature"],
					),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsInaccessibleConstructionOnce_whenTypeOfAnotherModuleConstructsItTwice() async {
		// `Hub` instantiates `Service` twice, and `App` generates both constructions, which refer to `Service` from
		// one place in `App`: its `hub` property.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):2:1: error: `Service` is `internal`, so module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` to fix.
			\(fixtures["Feature"]!["Service.swift"]):2:1-2:1: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(inPackage: "Shop", declaring: Self.internalServiceWithPackageInitializer, alongside: """
					@Instantiable
					public final class Hub: Instantiable {
					    package init(first: Service, second: Service) {
					        self.first = first
					        self.second = second
					    }
					    @Instantiated let first: Service
					    @Instantiated let second: Service
					}
					"""),
					Self.app(inPackage: "Shop", serviceType: "Hub"),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtMockMethod_whenMockDefaultsForwardedParameterToInternalHandWrittenMockOfAnotherModule() async {
		// `mock()` defaults `user` to `User.mock()`, which `App` cannot call.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["User.swift"]):4:5: error: `User.mock()` is `internal`, so module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make `User.mock()` `package` to fix.
			\(fixtures["Feature"]!["User.swift"]):4:5-4:5: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(inPackage: "Shop", declaring: """
					@Instantiable
					public final class User: Instantiable {
					    public init() {}
					    static func mock() -> User { User() }
					}
					"""),
					Self.app(inPackage: "Shop", declaring: """
					import Feature

					@Instantiable(generateMock: true)
					final class Profile: Instantiable {
					    init(user: User) {
					        self.user = user
					    }
					    @Forwarded let user: User
					}
					"""),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func query_reportsWhatMockNeeds_whenMockConstructsTypeAnotherModuleCannotReach() async throws {
		// The query reports what a type needs whichever module assembles it, so it checks no module's access.
		let output = try await executeSafeDIToolQuery(
			typeName: "Screen",
			modules: [
				Self.feature(inPackage: "Shop", declaring: Self.internalServiceWithPackageInitializer).queryTestModule,
				Self.app(inPackage: "Shop", declaring: Self.screenMockedInApp).queryTestModule,
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.result.modules.map(\.name) == ["App", "Feature"])
		#expect(output.result.mock?.modules.map(\.name) == ["App", "Feature"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtMockMethod_whenHandWrittenMockAnotherModuleDeclaresIsInternal() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["TestSupport"]!["ServiceMock.swift"]):5:5: error: `Service.mock()` is `internal`, so module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make `Service.mock()` `package` to fix.
			\(fixtures["TestSupport"]!["ServiceMock.swift"]):5:5-5:5: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesMockingServiceFromTestSupport(mockDeclaration: """
				@Instantiable(mockOnly: true)
				extension Service {
				    static func mock() -> Service { Service() }
				}
				"""),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtExtension_whenHandWrittenMockSpellsNoModifierAndItsExtensionIsInternal() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["TestSupport"]!["ServiceMock.swift"]):4:1: error: The extension that declares `Service.mock()` is `internal`, so module `App`, another module of the same package, cannot call `Service.mock()` in the code SafeDI generates. Make the extension `package` to fix.
			\(fixtures["TestSupport"]!["ServiceMock.swift"]):4:1-4:9: fixit: package
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesMockingServiceFromTestSupport(mockDeclaration: """
				@Instantiable(mockOnly: true)
				internal extension Service {
				    static func mock() -> Service { Service() }
				}
				"""),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicHandWrittenMock_whenAnotherPackageCallsItThroughInternalExtension(integration: MultiModuleIntegration) async throws {
		// Swift caps no member of an extension by the extension's level, and only warns at a member more permissive
		// than its extension, so another package can call the `public` mock.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesMockingServiceFromTestSupport(inPackage: "Kit", mockDeclaration: """
			@Instantiable(mockOnly: true)
			internal extension Service {
			    public static func mock() -> Service { Service() }
			}
			"""),
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let header = generatedFileHeader + Self.importBlock("Feature") + "\n" + Self.importBlock("TestSupport") + "\n\n"
		let screenMock = header + """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            service: (() -> Service)? = nil
		        ) {
		            self.service = service
		        }

		        let service: (() -> Service)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service.mock() }
		        return Screen(service: service)
		    }
		}
		#endif
		"""
		let expectedGeneratedFiles = switch integration {
		case .moduleInfo:
			["App.swift": screenMock]
		case .swiftPackagePlugin:
			["Screen+SafeDIMock.swift": screenMock, "SafeDIMockConfiguration.swift": header]
		}
		#expect(try #require(output.modules["App"]).generatedFiles == expectedGeneratedFiles)
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWithPublicFixItAtExtension_whenAnotherPackageCallsHandWrittenMockTakingPackageFromItsExtension(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let mockPath = Self.declarationPath(of: "ServiceMock.swift", in: "TestSupport", fixtures: fixtures, under: integration)
			return """
			\(mockPath):4:1: error: The extension that declares `Service.mock()` is `package`, so module `App`, in another package, cannot call `Service.mock()` in the code SafeDI generates. Make the extension `public` to fix.
			\(mockPath):4:1-4:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesMockingServiceFromTestSupport(inPackage: "Kit", mockDeclaration: """
				@Instantiable(mockOnly: true)
				package extension Service {
				    static func mock() -> Service { Service() }
				}
				"""),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – Roots another module declares

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_leavesDependencysRootWithoutCode_whenItsTreeConstructsInternalType() async throws {
		// The plugin's CSV for `App` lists `Feature`'s files, so `App` plans a file for `Feature`'s root too. `App`
		// cannot construct `Feature`'s internal types, so it leaves the file without code but a comment saying why, and
		// reports nothing: `Feature` generates the root and reports any problem with it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.feature(inPackage: "Shop", declaring: Self.internalServiceWithPackageInitializer, alongside: """
				@Instantiable(isRoot: true)
				final class FeatureRoot: Instantiable {
				    init(service: Service) {
				        self.service = service
				    }
				    @Instantiated let service: Service
				}
				"""),
				Self.app(inPackage: "Shop", declaring: Self.appRootIndependentOfFeature),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)

		let featureRootCode = """
		extension FeatureRoot {
		    public convenience init() {
		        let service = Service()
		        self.init(service: service)
		    }
		}
		"""
		#expect(try #require(output.modules["Feature"]).generatedFiles == ["FeatureRoot+SafeDI.swift": generatedFileHeader + featureRootCode])
		#expect(try #require(output.modules["App"]).generatedFiles["FeatureRoot+SafeDI.swift"] == generatedFileHeader + Self.importBlock("Feature") + "\n\n" + """
		// SafeDI generates the dependency tree of FeatureRoot only in the module that declares it, because the tree constructs a declaration that is neither `public` nor `open`.
		""")
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesDependencysRootAsItsModuleDoes_whenItsTreeConstructsOnlyPublicTypes() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.feature(
					inPackage: "Shop",
					declaring: """
					@Instantiable
					public final class Service: Instantiable {
					    public init() {}
					}
					""",
					alongside: """
					@Instantiable(isRoot: true)
					public final class FeatureRoot: Instantiable {
					    public init(service: Service) {
					        self.service = service
					    }
					    @Instantiated let service: Service
					}
					""",
				),
				Self.app(inPackage: "Shop", declaring: Self.appRootIndependentOfFeature),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)

		let featureRootCode = """
		extension FeatureRoot {
		    public convenience init() {
		        let service = Service()
		        self.init(service: service)
		    }
		}
		"""
		#expect(try #require(output.modules["Feature"]).generatedFiles == ["FeatureRoot+SafeDI.swift": generatedFileHeader + featureRootCode])
		#expect(try #require(output.modules["App"]).generatedFiles["FeatureRoot+SafeDI.swift"] == generatedFileHeader + Self.importBlock("Feature") + "\n\n" + featureRootCode)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// An `internal` `Service` with a `package` initializer, so that only the type keeps another module from
	/// constructing it.
	private static let internalServiceWithPackageInitializer = """
	@Instantiable
	final class Service: Instantiable {
	    package init() {}
	}
	"""

	/// A root in `App` that constructs nothing of `Feature`'s.
	private static let appRootIndependentOfFeature = """
	import Feature

	@Instantiable(isRoot: true)
	final class Root: Instantiable {
	    init() {}
	}
	"""

	/// A type in `App` whose generated mock builds `Feature`'s `Service`.
	private static let screenMockedInApp = """
	import Feature

	@Instantiable(generateMock: true)
	final class Screen: Instantiable {
	    init(service: Service) {
	        self.service = service
	    }
	    @Instantiated let service: Service
	}
	"""

	/// A `Feature` module of `packageName` declaring `declaration`, and `otherDeclaration` in a file of its own.
	private static func feature(
		inPackage packageName: String,
		declaring declaration: String,
		alongside otherDeclaration: String? = nil,
		deletesSwiftFilesAfterRunning: Bool = false,
	) -> ModuleFixture {
		ModuleFixture(
			name: "Feature",
			packageName: packageName,
			swiftFileContent: [declaration] + [otherDeclaration].compactMap(\.self),
			deletesSwiftFilesAfterRunning: deletesSwiftFilesAfterRunning,
		)
	}

	/// An `App` module of `packageName` depending on `Feature`, which declares `declaration`: by default, a root that
	/// instantiates `Feature`'s `serviceType`.
	private static func app(inPackage packageName: String, serviceType: String = "Service", declaring declaration: String? = nil) -> ModuleFixture {
		ModuleFixture(
			name: "App",
			packageName: packageName,
			swiftFileContent: [
				declaration ?? """
				import Feature

				@Instantiable(isRoot: true)
				final class Root: Instantiable {
				    init(service: \(serviceType)) {
				        self.service = service
				    }
				    @Instantiated let service: \(serviceType)
				}
				""",
			],
			dependencies: ["Feature"],
		)
	}

	/// A public `Service` in `Feature`, its hand-written mock in `TestSupport`, and a type in `App` whose generated
	/// mock builds `Service` with that mock: `Feature` and `App` in package `Shop`, and `TestSupport` in
	/// `testSupportPackageName`.
	private static func modulesMockingServiceFromTestSupport(inPackage testSupportPackageName: String = "Shop", mockDeclaration: String) -> [ModuleFixture] {
		[
			feature(
				inPackage: "Shop",
				declaring: """
				@Instantiable
				public final class Service: Instantiable {
				    public init() {}
				}
				""",
			),
			ModuleFixture(
				name: "TestSupport",
				packageName: testSupportPackageName,
				swiftFileContentByFilePath: ["ServiceMock.swift": "import Feature\n\n" + mockDeclaration],
				dependencies: ["Feature"],
			),
			ModuleFixture(
				name: "App",
				packageName: "Shop",
				swiftFileContent: ["import TestSupport\n" + screenMockedInApp],
				dependencies: ["Feature", "TestSupport"],
			),
		]
	}

	/// The path a diagnostic cites for the named fixture of `moduleName`: the CSV's absolute path under Bazel's
	/// invocation, and the compiler's spelling normalized under the plugin's.
	private static func declarationPath(of fileName: String, in moduleName: String, fixtures: [String: FixturePaths], under integration: MultiModuleIntegration) -> String {
		switch integration {
		case .moduleInfo:
			fixtures[moduleName]![fileName]
		case .swiftPackagePlugin:
			NormalizedFilePath(fixtures[moduleName]!.compilerPath(of: fileName)).path
		}
	}

	/// The files `App` generates under `integration` when it imports `Feature` and generates `code` for its root.
	private static func appGeneratedFiles(under integration: MultiModuleIntegration, code: String) -> [String: String] {
		switch integration {
		case .moduleInfo:
			["App.swift": generatedFileHeader + importBlock("Feature") + "\n\n" + code]
		case .swiftPackagePlugin:
			["Root+SafeDI.swift": generatedFileHeader + importBlock("Feature") + "\n\n" + code]
		}
	}

	/// The lines a generated file repeats for a fixture's `import <moduleName>`.
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
		#expect(compilation.modules.map(\.moduleName) == output.moduleNames, sourceLocation: sourceLocation)
		#expect(compilation.failure == nil, sourceLocation: sourceLocation)
	}
}
