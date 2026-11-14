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
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assumesPackageAccessWithoutComment_whenModuleMembershipIsUnknown() async throws {
		// Without the target graph, as for the Xcode project plugin, the tool cannot tell which module declares
		// `Service`, so it accepts a `package` declaration, and the compiler reports it if the two modules are in different
		// packages.
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
		        let service = Service()
		        self.init(service: service)
		    }
		}
		"""))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assumesPackageAccessOnEachConstructionLine_whenModuleMembershipIsUnknown() async throws {
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

		// Every construction of a type of another module relies on `package` access: in a builder function, an
		// instantiator's, and a lazily instantiated dependency's; in a mock's tree, with an initializer and with a
		// hand-written mock; and the construction of a listed mock's root. No line says so.
		let header = generatedFileHeader + Self.importBlock("Feature") + "\n" + Self.importBlock("TestSupport") + "\n\n"
		#expect(try #require(output.modules["App"]).generatedFiles == [
			"Root+SafeDI.swift": header + """
			extension Root {
			    public convenience init() {
			        func __safeDI_engine() -> Engine {
			            let service = Service()
			            return Engine(service: service)
			        }
			        let engine: Engine = __safeDI_engine()
			        func __safeDI_serviceBuilder() -> Service {
			            Service()
			        }
			        let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
			        func __safeDI_lazyService() -> Service {
			            Service()
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
			            let service = if let safeDIBuilder = safeDIOverrides.engine.service { safeDIBuilder() } else { Service.mock() }
			            return if let safeDIBuilder = safeDIOverrides.engine.safeDIBuilder { safeDIBuilder(service) } else { Engine(service: service) }
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
			        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service.mock() }
			        return Engine(service: service)
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
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assumesPackageAccessWithoutComment_whenForwardedParameterDefaultCallsHandWrittenMockOfUnknownModule() async throws {
		// `mock()` defaults `user` to `User.mock()`, which constructs `User` as any line of a mock's tree does, relying on
		// `package` access, which nothing on the line mentions.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.feature(inPackage: "Shop", declaring: Self.publicUserWithPackageMock),
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
			        user: User = User.mock(),
			        name: String = ""
			    ) -> Profile {
			        return Profile(user: user, name: name)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": header,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_constructsInternalTypes_whenHandWrittenManifestNamesNoOwnFiles() async throws {
		// A hand-written manifest that names no `mockScopedFilePaths` makes the input files the module's own, so the
		// generated code constructs the internal types they declare.
		let directory = TestTemporaryDirectory.root.appendingPathComponent(UUID().uuidString)
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

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorsOfferingSeamForTypesInItsTree_whenRootOfAnotherPackageBuildsPackageTypesThroughPublicType(integration: MultiModuleIntegration) async {
		// `Service`'s module could build its tree, `TokenCache` included, and `App` would call the initializer it generates
		// for `Service`, whose widest tier is at `Service`'s access, `public`, and calls the `package` initializer inside
		// `Core`, so the error about that initializer offers the seam too
		// (`generate_callsSeamsPublicInitializer_whenErrorsOfferedSeamIsDeclared`).
		await assertThrowsErrorsOfferingServiceAsSeamForTokenCache(tokenCacheReceivesSession: false, integration: integration)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorsOfferingSeamForTypesInItsTree_whenTypeInItsTreeReceivesPropertyTheSeamCandidateReceives() async {
		// `TokenCache` receives the `session` that `Service` receives: the initializer `Core` would generate for `Service`
		// takes it as `Service`'s own parameter, as visible as `Session`, `public`, and calls `Service`'s `package`
		// initializer inside `Core`, so every error offers the seam.
		await assertThrowsErrorsOfferingServiceAsSeamForTokenCache(tokenCacheReceivesSession: true, integration: .moduleInfo)
	}

	/// Asserts that `App`'s root, which builds `Core`'s `public` `Service` through its own `Screen`, gets an error at
	/// `Service`'s `package` initializer, one at `TokenCache`, which `Service` instantiates, and one at its `package`
	/// initializer, each offering `Service` as a seam. `Service` receives `analytics` and `session`, and so does
	/// `TokenCache` when `tokenCacheReceivesSession` is set.
	private mutating func assertThrowsErrorsOfferingServiceAsSeamForTokenCache(tokenCacheReceivesSession: Bool, integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = Self.declarationPath(of: "Service.swift", in: "Core", fixtures: fixtures, under: integration)
			return """
			\(servicePath):3:5: error: `Service`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix\(Self.seamRemedy(declaring: "Service", in: "Core")).
			\(servicePath):3:5-3:12: fixit: public
			\(servicePath):27:1: error: `TokenCache` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Make `TokenCache` `public` to fix\(Self.seamRemedy(declaring: "Service", in: "Core")).
			\(servicePath):27:1-27:8: fixit: public
			\(servicePath):28:5: error: `TokenCache`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix\(Self.seamRemedy(declaring: "Service", in: "Core")).
			\(servicePath):28:5-28:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.coreDeclaringServiceBuildingTokenCache(serviceAttribute: "@Instantiable", tokenCacheReceivesSession: tokenCacheReceivesSession),
					Self.appBuildingServiceThroughScreen(screenAttribute: "@Instantiable(generateMock: true)"),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamsPublicInitializer_whenErrorsOfferedSeamIsDeclared(integration: MultiModuleIntegration) async throws {
		// The remedy the errors about `Service`'s `package` initializer and `TokenCache` offer, applied with nothing else
		// changed: `Core` builds `TokenCache` and calls `Service`'s `package` initializer in the `public` initializer it
		// generates, which `App` calls.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.coreDeclaringServiceBuildingTokenCache(serviceAttribute: "@Instantiable(generateDependencyTree: true)", tokenCacheReceivesSession: false),
				Self.appBuildingServiceThroughScreen(screenAttribute: "@Instantiable"),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let seamCode = """
		extension Service {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_analytics analytics: LazilyInstantiated<Analytics>, __safeDI_session session: Session) {
		        let tokenCache = TokenCache()
		        self.init(analytics: analytics, session: session, tokenCache: tokenCache)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_EEBD82F55D1C7D4A {}
		}
		"""
		let pluginComment = integration.seamCallComment(type: "Service", declaringModule: "Core")
		let rootCode = """
		extension AppRoot {
		    public init() {
		        func __safeDI_analytics() -> Analytics {
		            Analytics()
		        }
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        let session = Session()
		        func __safeDI_screen() -> Screen {
		            func __safeDI_service() -> Service {
		                _ = Service.__safeDI_Service_EEBD82F55D1C7D4A.self\(pluginComment)
		                return Service(__safeDI_analytics: analytics, __safeDI_session: session)
		            }
		            let service: Service = __safeDI_service()
		            return Screen(analytics: analytics, session: session, service: service)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(analytics: analytics, session: session, screen: screen)
		    }
		}
		"""
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + seamCode])
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + rootCode])
		case .swiftPackagePlugin:
			#expect(output.modules["Core"]?.generatedFiles == ["Service+SafeDI.swift": generatedFileHeader + seamCode])
			#expect(output.modules["App"]?.generatedFiles == ["AppRoot+SafeDI.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + rootCode])
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingOutermostTypeOfAnotherModuleAsSeam_whenRootConstructsPackageTypeThroughIt(integration: MultiModuleIntegration) async {
		// `Root` calls the initializer `Feature` generates for `Seam`, whose tree is built in `Feature`, so only the tree
		// of `Service` constructs `Gate` in `App`'s production code. Production code is generated, and checked, before the
		// mock of `Container`, which builds `Seam`'s tree too.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let gatePath = Self.declarationPath(of: "Gate.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(gatePath):3:5: error: `Gate`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix\(Self.seamRemedy(declaring: "Service", in: "Feature")).
			\(gatePath):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.featureDeclaringGateBuiltByServiceAndSeam,
					Self.appInstantiatingServiceAndSeam(in: ["Root": "@Instantiable(isRoot: true)", "Container": "@Instantiable(generateMock: true)"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersSeamOnlyForDeclarationsItsModuleCanConstruct_whenTreeOfTypeOfAnotherPackageReachesThirdModule(integration: MultiModuleIntegration) async {
		// `Core`, which would build `Service`'s tree as a seam, can call its own `Cache`'s `package` initializer, but not
		// `Base`'s `Formatter`'s, which is `internal`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let formatterPath = Self.declarationPath(of: "Formatter.swift", in: "Base", fixtures: fixtures, under: integration)
			let cachePath = Self.declarationPath(of: "Cache.swift", in: "Core", fixtures: fixtures, under: integration)
			return """
			\(formatterPath):3:5: error: `Formatter`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(formatterPath):3:5-3:5: fixit: public\(" ")
			\(cachePath):3:5: error: `Cache`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix\(Self.seamRemedy(declaring: "Service", in: "Core")).
			\(cachePath):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Base",
						packageName: "Toolkit",
						swiftFileContent: [
							"""
							@Instantiable
							public final class Formatter: Instantiable {
							    init() {}
							}
							""",
						],
					),
					ModuleFixture(
						name: "Core",
						packageName: "Toolkit",
						swiftFileContent: [
							"""
							@Instantiable
							public final class Cache: Instantiable {
							    package init() {}
							}
							""",
							"""
							import Base

							@Instantiable
							public final class Service: Instantiable {
							    public init(cache: Cache, formatter: Formatter) {
							        self.cache = cache
							        self.formatter = formatter
							    }

							    @Instantiated let cache: Cache
							    @Instantiated let formatter: Formatter
							}
							""",
						],
						dependencies: ["Base"],
					),
					Self.rootInstantiatingService(dependencies: ["Base", "Core"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: ThirdModuleReach.cellsWhereCoreReadsBase)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersSeamForDeclarationOfThirdModule_whenCandidatesModuleReadsThatModule(reach: ThirdModuleReach, integration: MultiModuleIntegration) async {
		// `Core`'s own run reads `Base`'s declarations, so declared a seam, `Service` has `Core` build `Formatter`, whose
		// `package` initializer `Core`, in `Base`'s package, can call, and `App` calls the initializer `Core` generates
		// (`generate_callsSeamBuildingDeclarationOfThirdModule_whenOfferedSeamIsDeclared`).
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let formatterPath = Self.declarationPath(of: "Formatter.swift", in: "Base", fixtures: fixtures, under: integration)
			return """
			\(formatterPath):3:5: error: `Formatter`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix\(Self.seamRemedy(declaring: "Service", in: "Core")).
			\(formatterPath):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesBuildingFormatterThroughService(reach: reach, serviceAttribute: "@Instantiable"),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: ThirdModuleReach.cellsWhereCoreReadsBase)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamBuildingDeclarationOfThirdModule_whenOfferedSeamIsDeclared(reach: ThirdModuleReach, integration: MultiModuleIntegration) async throws {
		// The remedy `generate_offersSeamForDeclarationOfThirdModule_whenCandidatesModuleReadsThatModule` offers, applied
		// with nothing else changed: `Core` builds `Formatter` in the initializer it generates for `Service`, which `App`
		// calls, and every module compiles.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesBuildingFormatterThroughService(reach: reach, serviceAttribute: "@Instantiable(generateDependencyTree: true)"),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let seamCode = """
		extension Service {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public convenience init() {
		        let formatter = Formatter()
		        self.init(formatter: formatter)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_CBF29CE484222325 {}
		}
		"""
		let pluginComment = integration.seamCallComment(type: "Service", declaringModule: "Core")
		let rootCode = """
		extension Root {
		    public convenience init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_CBF29CE484222325.self\(pluginComment)
		            return Service()
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""
		let coreFile = generatedFileHeader + reach.importBlocksOfCoresGeneratedFile + "\n\n" + seamCode
		let appFile = generatedFileHeader + reach.importBlocksOfAppsGeneratedFile + "\n\n" + rootCode
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": coreFile])
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": appFile])
		case .swiftPackagePlugin:
			#expect(output.modules["Core"]?.generatedFiles == ["Service+SafeDI.swift": coreFile])
			#expect(output.modules["App"]?.generatedFiles == ["Root+SafeDI.swift": appFile])
		}
	}

	@Test(arguments: ThirdModuleReach.cellsWhereCoreDoesNotReadBase)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersNoSeamForDeclarationOfThirdModule_whenCandidatesModuleDoesNotReadThatModule(reach: ThirdModuleReach, integration: MultiModuleIntegration) async {
		// `Core` imports `Base`, or a module that re-exports it, but does not depend on it directly. These runs model a
		// Tuist run, or a custom script's, which gives `Core`'s run only the module info of the modules it depends on
		// directly, so declared a seam, `Service` would take a builder for `Formatter`, which `App` would still fill
		// (`generate_throwsErrorAtDeclarationOfThirdModule_whenSeamWhoseModuleDoesNotReadThatModuleIsDeclared`). A Bazel
		// run, told of every module beneath, reports this same error: `Core` declares no root or seam, so its run reads
		// nothing from beneath, and the remedy is withheld, although the seam, once declared, would read `Base` from
		// beneath and build `Formatter`
		// (`generate_callsSeamBuildingDeclarationOfThirdModule_whenSeamWhoseModuleReadsThatModuleFromBeneathIsDeclared`).
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let formatterPath = Self.declarationPath(of: "Formatter.swift", in: "Base", fixtures: fixtures, under: integration)
			return """
			\(formatterPath):3:5: error: `Formatter`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(formatterPath):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesBuildingFormatterThroughService(reach: reach, serviceAttribute: "@Instantiable"),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: ThirdModuleReach.cellsWhereCoreDoesNotReadBase)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtDeclarationOfThirdModule_whenSeamWhoseModuleDoesNotReadThatModuleIsDeclared(reach: ThirdModuleReach, integration: MultiModuleIntegration) async {
		// The seam `generate_offersNoSeamForDeclarationOfThirdModule_whenCandidatesModuleDoesNotReadThatModule` withholds,
		// declared anyway, under a Tuist run or a custom script's, which gives `Core`'s run only the module info of the
		// modules it depends on directly: `Core` sees no `@Instantiable` declaration of `Formatter`, so `App` fills the
		// builder the seam takes for it and still calls `Formatter`'s initializer. `Formatter` builds no tree, so no
		// seam is offered. A Bazel run, told of every module beneath, reads `Base` from beneath for the seam's tree, so
		// the seam builds `Formatter` itself and `App` compiles
		// (`generate_callsSeamBuildingDeclarationOfThirdModule_whenSeamWhoseModuleReadsThatModuleFromBeneathIsDeclared`).
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let formatterPath = Self.declarationPath(of: "Formatter.swift", in: "Base", fixtures: fixtures, under: integration)
			return """
			\(formatterPath):3:5: error: `Formatter`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(formatterPath):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesBuildingFormatterThroughService(reach: reach, serviceAttribute: "@Instantiable(generateDependencyTree: true)"),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: ThirdModuleReach.reachesWhereCoreDoesNotDependOnBase)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamBuildingDeclarationOfThirdModule_whenSeamWhoseModuleReadsThatModuleFromBeneathIsDeclared(reach: ThirdModuleReach) async throws {
		// The shape of `generate_throwsErrorAtDeclarationOfThirdModule_whenSeamWhoseModuleDoesNotReadThatModuleIsDeclared`,
		// with each run told of every module beneath it, as Bazel's rule tells it: `Core` declares a seam whose tree
		// needs `Formatter`, which no module it depends on directly declares, so its run reads `Base` from beneath,
		// builds `Formatter` in the initializer it generates for `Service`, and imports `Base`. `App` calls that
		// initializer, and every module compiles.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesBuildingFormatterThroughService(reach: reach, serviceAttribute: "@Instantiable(generateDependencyTree: true)"),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		let seamCode = """
		extension Service {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public convenience init() {
		        let formatter = Formatter()
		        self.init(formatter: formatter)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_CBF29CE484222325 {}
		}
		"""
		let pluginComment = MultiModuleIntegration.moduleInfo.seamCallComment(type: "Service", declaringModule: "Core")
		let rootCode = """
		extension Root {
		    public convenience init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_CBF29CE484222325.self\(pluginComment)
		            return Service()
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""
		#expect(output.modules["Core"]?.moduleInfoFile?.dependencyModuleNames == (["Base"] + reach.coreDependencies).sorted())
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + reach.importBlocksOfCoresGeneratedFileReadingBaseFromBeneath + "\n\n" + seamCode])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + reach.importBlocksOfAppsGeneratedFile + "\n\n" + rootCode])
	}

	@Test(arguments: FormatterConstruction.neighborsOfConstant, MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersSeamForDeclarationOfThirdModule_whenCandidatesTreeBuildsItThroughWrapperExistentialNestingOrTypeOfCandidatesModule(construction: FormatterConstruction, integration: MultiModuleIntegration) async {
		// However `Service`'s tree builds `Formatter`, `Core`'s own run reads `Base`, which it depends on and imports.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let formatterPath = Self.declarationPath(of: "Formatter.swift", in: "Base", fixtures: fixtures, under: integration)
			let (line, column) = construction.initializerLocation
			return """
			\(formatterPath):\(line):\(column): error: `\(construction.formatterType)`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix\(Self.seamRemedy(declaring: "Service", in: "Core")).
			\(formatterPath):\(line):\(column)-\(line):\(column + 7): fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesBuildingFormatterThroughService(reach: .importsDependency, construction: construction, serviceAttribute: "@Instantiable"),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersNoSeamForDeclarationOfThirdModule_whenAnotherPathConstructsItWithoutPassingThroughCandidate(integration: MultiModuleIntegration) async {
		// `Root` instantiates `Formatter` beside `Service`, so declaring `Service` a seam would leave a construction of
		// `Formatter` in `App`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let formatterPath = Self.declarationPath(of: "Formatter.swift", in: "Base", fixtures: fixtures, under: integration)
			return """
			\(formatterPath):3:5: error: `Formatter`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(formatterPath):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Array(Self.modulesBuildingFormatterThroughService(reach: .importsDependency, serviceAttribute: "@Instantiable").dropLast()) + [
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"Root.swift": TokenCacheConstruction.type(declaredAs: "import Base\n\n@Instantiable(isRoot: true)\nfinal class Root", initializerModifier: "", instantiating: ["service: Service", "formatter: Formatter"], importing: "Core"),
						],
						dependencies: ["Base", "Core"],
					),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersNoSeamForPackageDeclarationOfThirdModule_whenThatModuleIsInAnotherPackageThanCandidatesModule(integration: MultiModuleIntegration) async {
		// `Core` reads `Base`, but `Base` is in a package of its own, so `Core` can no more call `Formatter`'s `package`
		// initializer than `App` can.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let formatterPath = Self.declarationPath(of: "Formatter.swift", in: "Base", fixtures: fixtures, under: integration)
			return """
			\(formatterPath):3:5: error: `Formatter`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(formatterPath):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesBuildingFormatterThroughService(reach: .importsDependency, basePackageName: "Formats", serviceAttribute: "@Instantiable"),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersNoSeam_whenPathFromCandidatePassesThroughTypeOfModuleCandidatesModuleDoesNotRead(integration: MultiModuleIntegration) async {
		// `Service`'s tree reaches `Feature`'s own `Cache` through `DefaultUserService`, which fulfills `UserService` in
		// `FeatureImpl`, a module that depends on `Feature`. Declared a seam, `Service` would take a builder for
		// `UserService`, which `App` would fill, building `Cache` itself
		// (`generate_offersFillsTypeAsSeam_whenFillsTreeBuildsDeclarationOfModuleFillsModuleReads`).
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = Self.declarationPath(of: "Service.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(servicePath):5:5: error: `Cache`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(servicePath):5:5-5:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesFillingServiceWithImplementationBuildingCache(seams: []),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersNoSeam_whenPathFromCandidatePassesThroughTypeOfModuleSafeDIDoesNotKnow(integration: MultiModuleIntegration) async {
		// `App` reads `DefaultUserService`, which fulfills `UserService` and builds `Feature`'s own `Cache`, through
		// `additionalDirectoriesToInclude`, so SafeDI knows no module that declares it, and no other module's run reads it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = Self.declarationPath(of: "Service.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(servicePath):5:5: error: `Cache`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(servicePath):5:5-5:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesFillingServiceWithImplementationBuildingCache(seams: [], appReadsImplementationThroughAdditionalDirectory: true),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersFillsTypeAsSeam_whenFillsTreeBuildsDeclarationOfModuleFillsModuleReads(integration: MultiModuleIntegration) async {
		// `Service` is a seam, and `App` fills its builder with `DefaultUserService`, whose tree builds `Feature`'s `Cache`.
		// `FeatureImpl` depends on `Feature`, so declared a seam, `DefaultUserService` has `FeatureImpl`, in `Feature`'s
		// package, build `Cache` (`generate_callsFillsSeam_whenFillsTreeBuildsDeclarationOfModuleFillsModuleReads`).
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = Self.declarationPath(of: "Service.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(servicePath):5:5: error: `Cache`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix\(Self.seamRemedy(declaring: "DefaultUserService", in: "FeatureImpl")).
			\(servicePath):5:5-5:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesFillingServiceWithImplementationBuildingCache(seams: ["Service"]),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsFillsSeam_whenFillsTreeBuildsDeclarationOfModuleFillsModuleReads(integration: MultiModuleIntegration) async throws {
		// The remedy `generate_offersFillsTypeAsSeam_whenFillsTreeBuildsDeclarationOfModuleFillsModuleReads` offers,
		// applied with nothing else changed: `FeatureImpl` builds `Cache` in the initializer it generates for
		// `DefaultUserService`, which `App`'s fill of `Service`'s builder calls, and every module compiles.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesFillingServiceWithImplementationBuildingCache(seams: ["Service", "DefaultUserService"]),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let featureCode = """
		extension Service {
		    @frozen public enum SafeDIScope_UserService {
		        case userService(userService_Values)

		        public struct userService_Values {}
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public convenience init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let userService: any UserService = __safeDI_userServiceBuilder(.userService(SafeDIScope_UserService.userService_Values()))
		        self.init(userService: userService)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_47FCCD49F0077492 {}
		}
		"""
		let featureImplCode = """
		extension DefaultUserService {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public convenience init() {
		        let cache = Cache()
		        self.init(cache: cache)
		    }
		}

		extension DefaultUserService {
		    public enum __safeDI_DefaultUserService_CBF29CE484222325 {}
		}
		"""
		let rootCode = """
		extension Root {
		    public convenience init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_47FCCD49F0077492.self\(integration.seamCallComment(type: "Service", declaringModule: "Feature"))
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case .userService:
		                    func __safeDI_userService() -> DefaultUserService {
		                        _ = DefaultUserService.__safeDI_DefaultUserService_CBF29CE484222325.self\(integration.seamCallComment(type: "DefaultUserService", declaringModule: "FeatureImpl"))
		                        return DefaultUserService()
		                    }
		                    let userService: any UserService = __safeDI_userService()
		                    return userService
		                }
		            }
		            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + featureCode])
			#expect(output.modules["FeatureImpl"]?.generatedFiles == ["FeatureImpl.swift": generatedFileHeader + Self.importBlock("Feature") + "\n\n" + featureImplCode])
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + Self.importBlock("Feature") + "\n" + Self.importBlock("FeatureImpl") + "\n\n" + rootCode])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == ["Service+SafeDI.swift": generatedFileHeader + featureCode])
			#expect(output.modules["FeatureImpl"]?.generatedFiles == ["DefaultUserService+SafeDI.swift": generatedFileHeader + Self.importBlock("Feature") + "\n\n" + featureImplCode])
			#expect(output.modules["App"]?.generatedFiles == ["Root+SafeDI.swift": generatedFileHeader + Self.importBlock("Feature") + "\n" + Self.importBlock("FeatureImpl") + "\n\n" + rootCode])
		}
	}

	@Test(arguments: TokenCacheConstruction.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingNoSeam_whenAnotherPathConstructsTypeWithoutPassingThroughCandidate(construction: TokenCacheConstruction) async {
		// Declaring `Service` a seam would leave the construction of `TokenCache` that bypasses it in `App`, although the
		// path through `Service` refers to `TokenCache` first, and no one type is the outermost on every path to the
		// `Cipher` that `TokenCache` instantiates.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Service.swift"]):12:5: error: `TokenCache`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(fixtures["Core"]!["Service.swift"]):12:5-12:12: fixit: public
			\(fixtures["Core"]!["Service.swift"]):21:5: error: `Cipher`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(fixtures["Core"]!["Service.swift"]):21:5-21:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Core",
						packageName: "Toolkit",
						swiftFileContent: [
							"""
							@Instantiable
							public final class Service: Instantiable {
							    public init(tokenCache: TokenCache) {
							        self.tokenCache = tokenCache
							    }

							    @Instantiated let tokenCache: TokenCache
							}

							@Instantiable
							public final class TokenCache: Instantiable {
							    package init(cipher: Cipher) {
							        self.cipher = cipher
							    }

							    @Instantiated let cipher: Cipher
							}

							@Instantiable
							public final class Cipher: Instantiable {
							    package init() {}
							}
							""",
						],
					),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContentByFilePath: construction.appFiles,
						dependencies: ["Core"],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: SessionProvider.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersSeam_whenTypeBeneathCandidateReceivesPropertyProvidedAboveOrBeneathCandidate(sessionProvider: SessionProvider) async {
		// `TokenCache` receives `session`. Where `Service`'s tree provides it, `Core` would build the tree and pass it;
		// where `Root` provides it, the initializer `Core` would generate for `Service` takes it as a parameter as
		// visible as `Session`, `public`, and calls `TokenCache`'s initializer inside `Core`, as
		// `SafeDIToolSeamAccessTests.generate_callsPublicTierPassingValue_whenReceiversInitializerIsNarrowerThanCallerCanCall`
		// compiles.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["TokenCache.swift"]):2:5: error: `TokenCache`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix\(Self.seamRemedy(declaring: "Service", in: "Core")).
			\(fixtures["Core"]!["TokenCache.swift"]):2:5-2:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Core",
						packageName: "Toolkit",
						swiftFileContentByFilePath: [
							"Service.swift": sessionProvider.serviceFile,
							"Session.swift": """
							@Instantiable
							public final class Session: Instantiable {
							    public init() {}
							}
							""",
							"TokenCache.swift": """
							@Instantiable public final class TokenCache: Instantiable {
							    package init(session: Session) {
							        self.session = session
							    }

							    @Received let session: Session
							}
							""",
						],
					),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Root.swift": sessionProvider.rootFile], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersSeamForEveryDeclarationButCandidatesType_whenRootErasesPackageTypeOfAnotherPackage() async {
		// `App` names `Service` only through the erasure. The initializer `Core` would generate for `Service` is no more
		// visible than `Service`, so the error at `Service` offers no seam and must be fixed first; once it is, the seam
		// leaves `Service`'s initializer and `TokenCache` to `Core`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Core"]!["Service.swift"]):4:1: error: `Service` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Service` `public` to fix.
			\(fixtures["Core"]!["Service.swift"]):4:1-4:8: fixit: public
			\(fixtures["Core"]!["Service.swift"]):5:5: error: `Service`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix\(Self.seamRemedy(declaring: "Service", in: "Core")).
			\(fixtures["Core"]!["Service.swift"]):5:5-5:12: fixit: public
			\(fixtures["Core"]!["Service.swift"]):13:1: error: `TokenCache` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Make `TokenCache` `public` to fix\(Self.seamRemedy(declaring: "Service", in: "Core")).
			\(fixtures["Core"]!["Service.swift"]):13:1-13:8: fixit: public
			\(fixtures["Core"]!["Service.swift"]):14:5: error: `TokenCache`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix\(Self.seamRemedy(declaring: "Service", in: "Core")).
			\(fixtures["Core"]!["Service.swift"]):14:5-14:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Core",
						packageName: "CorePackage",
						swiftFileContentByFilePath: [
							"Service.swift": """
							public protocol ServiceProtocol {}

							@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
							package final class Service: ServiceProtocol, Instantiable {
							    package init(tokenCache: TokenCache) {
							        self.tokenCache = tokenCache
							    }

							    @Instantiated let tokenCache: TokenCache
							}

							@Instantiable
							package struct TokenCache: Instantiable {
							    package init() {}
							}
							""",
						],
					),
					ModuleFixture(
						name: "App",
						packageName: "AppPackage",
						swiftFileContentByFilePath: [
							"Root.swift": """
							import Core

							final class AnyServiceProtocol: ServiceProtocol {
							    init(_ service: some ServiceProtocol) {
							        self.service = service
							    }

							    let service: any ServiceProtocol
							}

							@Instantiable(isRoot: true)
							final class Root: Instantiable {
							    init(service: AnyServiceProtocol) {
							        self.service = service
							    }

							    @Instantiated(fulfilledByType: "Service", erasedToConcreteExistential: true) let service: AnyServiceProtocol
							}
							""",
						],
						dependencies: ["Core"],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersNoSeam_whenDeclarationIsInModuleCandidatesModuleDoesNotRead() async {
		// `Service`'s tree builds `DefaultUserService`, which fulfills `UserService` in `FeatureImpl`, a module that depends
		// on `Feature`. Declared a seam, `Service` could not build it in `Feature`, whose own run does not read it, so `App`
		// would still construct it, and the error offers no seam.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["FeatureImpl"]!["DefaultUserService.swift"]):5:5: error: `DefaultUserService`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(fixtures["FeatureImpl"]!["DefaultUserService.swift"]):5:5-5:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Feature",
						packageName: "Kit",
						swiftFileContentByFilePath: [
							"Service.swift": """
							public protocol UserService: AnyObject {}

							@Instantiable
							public final class Profile: Instantiable {
							    public init(userService: any UserService) {
							        self.userService = userService
							    }

							    @Instantiated let userService: any UserService
							}

							@Instantiable
							public final class Service: Instantiable {
							    public init(profile: Profile) {
							        self.profile = profile
							    }

							    @Instantiated let profile: Profile
							}
							""",
						],
					),
					ModuleFixture(
						name: "FeatureImpl",
						packageName: "Kit",
						swiftFileContentByFilePath: [
							"DefaultUserService.swift": """
							import Feature

							@Instantiable(fulfillingAdditionalTypes: [UserService.self])
							public final class DefaultUserService: UserService, Instantiable {
							    package init() {}
							}
							""",
						],
						dependencies: ["Feature"],
					),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"Root.swift": """
							import Feature
							import FeatureImpl

							@Instantiable(isRoot: true)
							final class Root: Instantiable {
							    init(service: Service) {
							        self.service = service
							    }

							    @Instantiated let service: Service
							}
							""",
						],
						dependencies: ["Feature", "FeatureImpl"],
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	/// Which type instantiates the `session` that `Core`'s `TokenCache`, beneath `Service`, receives.
	enum SessionProvider: CaseIterable {
		/// `Service`, the outermost type of `Core` on the path to `TokenCache`.
		case service
		/// `App`'s root, above `Service`.
		case root

		/// `Service.swift`: `Service`, which instantiates `TokenCache`, and `session` when it provides it.
		var serviceFile: String {
			let properties = (self == .service ? ["session: Session"] : []) + ["tokenCache: TokenCache"]
			return TokenCacheConstruction.type(declaredAs: "@Instantiable\npublic final class Service", initializerModifier: "public ", instantiating: properties, importing: nil)
		}

		/// `Root.swift`: a root that instantiates `Service`, and `session` when it provides it.
		var rootFile: String {
			let properties = (self == .root ? ["session: Session"] : []) + ["service: Service"]
			return TokenCacheConstruction.type(declaredAs: "@Instantiable(isRoot: true)\nfinal class Root", initializerModifier: "", instantiating: properties, importing: "Core")
		}
	}

	/// How `App`'s roots construct `Core`'s `TokenCache` besides through `Service`, which they refer to first.
	enum TokenCacheConstruction: CaseIterable {
		/// The root that instantiates `Service` also instantiates `TokenCache`.
		case besideServiceInOneRoot
		/// A root after the one that instantiates `Service` instantiates `TokenCache`.
		case inAnotherRoot

		/// `App`'s files, by path.
		var appFiles: [String: String] {
			switch self {
			case .besideServiceInOneRoot:
				["Root.swift": Self.root(named: "Root", instantiating: ["service: Service", "tokenCache: TokenCache"])]
			case .inAnotherRoot:
				[
					"Alpha.swift": Self.root(named: "Alpha", instantiating: ["service: Service"]),
					"Beta.swift": Self.root(named: "Beta", instantiating: ["tokenCache: TokenCache"]),
				]
			}
		}

		/// A root named `name` of `App` that instantiates each of `properties`, in order.
		private static func root(named name: String, instantiating properties: [String]) -> String {
			type(declaredAs: "@Instantiable(isRoot: true)\nfinal class \(name)", initializerModifier: "", instantiating: properties, importing: "Core")
		}

		/// A type `declaration` declares, whose initializer, spelled with `initializerModifier`, takes each of
		/// `properties`, which it instantiates, in order, in a file that imports `importedModule`.
		static func type(declaredAs declaration: String, initializerModifier: String, instantiating properties: [String], importing importedModule: String?) -> String {
			let labels = properties.map { $0.prefix { $0 != ":" } }
			return (importedModule.map { "import \($0)\n\n" } ?? "") + """
			\(declaration): Instantiable {
			    \(initializerModifier)init(\(properties.joined(separator: ", "))) {
			\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
			    }

			\(properties.map { "    @Instantiated let \($0)" }.joined(separator: "\n"))
			}
			"""
		}
	}

	/// How `Core`, which declares `Service`, reaches `Base`, which declares the `Formatter` that `Service` instantiates.
	enum ThirdModuleReach: CaseIterable {
		/// `Core` depends on `Base` and imports it.
		case importsDependency
		/// `Core` depends on `Base` and imports it with `@_exported`.
		case reexportsDependency
		/// `Core` depends on `Base` and imports it inside `#if canImport(Base)`.
		case importsDependencyConditionally
		/// `Core` depends only on `Umbrella`, which depends on `Base` and re-exports it, and imports `Umbrella`.
		case importsModuleReexportingIt
		/// `Core` depends only on `Mid`, which depends on `Base`, and imports `Base`.
		case importsDependencyOfDependency

		/// Each reach with each integration under which `Core`'s own run reads `Base`'s declarations.
		static let cellsWhereCoreReadsBase = allCases.flatMap { reach in
			MultiModuleIntegration.allCases.filter(reach.coreReadsBase(under:)).map { (reach, $0) }
		}

		/// Each reach with each integration under which `Core`'s own run does not read `Base`'s declarations.
		static let cellsWhereCoreDoesNotReadBase = allCases.flatMap { reach in
			MultiModuleIntegration.allCases.filter { !reach.coreReadsBase(under: $0) }.map { (reach, $0) }
		}

		/// Each reach under which `Core` does not depend on `Base` directly, so that its run reads `Base` only when told
		/// of the modules beneath it, as Bazel's rule tells it.
		static let reachesWhereCoreDoesNotDependOnBase = allCases.filter { !$0.coreDependencies.contains("Base") }

		/// Whether `Core`'s own run reads `Base`'s declarations under `integration`: the plugin hands a run the files of
		/// every module its module depends on, directly or not, and `.moduleInfo`, told of no module beneath as a Tuist
		/// run or a custom script's is, the module info of the modules it depends on directly.
		func coreReadsBase(under integration: MultiModuleIntegration) -> Bool {
			switch integration {
			case .moduleInfo:
				coreDependencies.contains("Base")
			case .swiftPackagePlugin:
				true
			}
		}

		/// The lines `Service.swift` starts with.
		var coreImports: String {
			switch self {
			case .importsDependency, .importsDependencyOfDependency:
				"import Base"
			case .reexportsDependency:
				"@_exported import Base"
			case .importsDependencyConditionally:
				"#if canImport(Base)\nimport Base\n#endif"
			case .importsModuleReexportingIt:
				"import Umbrella"
			}
		}

		/// The modules `Core` depends on directly.
		var coreDependencies: [String] {
			switch self {
			case .importsDependency, .reexportsDependency, .importsDependencyConditionally:
				["Base"]
			case .importsModuleReexportingIt:
				["Umbrella"]
			case .importsDependencyOfDependency:
				["Mid"]
			}
		}

		/// The modules between `Base` and `Core`, which declare nothing SafeDI reads.
		var intermediateModules: [ModuleFixture] {
			switch self {
			case .importsDependency, .reexportsDependency, .importsDependencyConditionally:
				[]
			case .importsModuleReexportingIt:
				[ModuleFixture(name: "Umbrella", packageName: "Toolkit", swiftFileContentByFilePath: ["Umbrella.swift": "@_exported import Base\n"], dependencies: ["Base"])]
			case .importsDependencyOfDependency:
				[ModuleFixture(name: "Mid", packageName: "Toolkit", swiftFileContentByFilePath: ["Mid.swift": "import Base\n\npublic enum Toolbox {}\n"], dependencies: ["Base"])]
			}
		}

		/// The imports the file `Core` generates for `Service` starts with: those of `Service.swift`.
		var importBlocksOfCoresGeneratedFile: String {
			switch self {
			case .importsDependency, .importsDependencyConditionally, .importsDependencyOfDependency:
				SafeDIToolAccessEnforcementTests.importBlock("Base")
			case .reexportsDependency:
				"#if canImport(Base)\n@_exported import Base\n#endif"
			case .importsModuleReexportingIt:
				SafeDIToolAccessEnforcementTests.importBlock("Umbrella")
			}
		}

		/// The imports the file `Core` generates for `Service` starts with when its run is told of the modules beneath it
		/// and its seam's tree reads `Base` from there: those of `Service.swift` and `Base`'s, sorted by module.
		var importBlocksOfCoresGeneratedFileReadingBaseFromBeneath: String {
			switch self {
			case .importsDependency, .reexportsDependency, .importsDependencyConditionally, .importsDependencyOfDependency:
				importBlocksOfCoresGeneratedFile
			case .importsModuleReexportingIt:
				SafeDIToolAccessEnforcementTests.importBlock("Base") + "\n" + importBlocksOfCoresGeneratedFile
			}
		}

		/// The imports the file `App` generates for its root starts with: those of `Service.swift` and of `Root.swift`,
		/// sorted by module.
		var importBlocksOfAppsGeneratedFile: String {
			switch self {
			case .importsDependency, .reexportsDependency, .importsDependencyConditionally, .importsDependencyOfDependency:
				importBlocksOfCoresGeneratedFile + "\n" + SafeDIToolAccessEnforcementTests.importBlock("Core")
			case .importsModuleReexportingIt:
				SafeDIToolAccessEnforcementTests.importBlock("Core") + "\n" + importBlocksOfCoresGeneratedFile
			}
		}
	}

	/// How `Service`'s tree builds `Base`'s `Formatter`, whose initializer is `package`.
	enum FormatterConstruction: CaseIterable {
		/// `Service` instantiates a `Formatter`.
		case constant
		/// `Service` instantiates an `Instantiator<Formatter>`.
		case instantiator
		/// `Service` instantiates a `LazilyInstantiated<Formatter>`.
		case lazilyInstantiated
		/// `Service` instantiates an `any Formatting`, which `Formatter` fulfills.
		case existential
		/// `Service` instantiates a `Formats.Formatter`, which `Base`'s `Formats` encloses.
		case nested
		/// `Service` instantiates `Core`'s `Cache`, which instantiates a `Formatter`.
		case beneathTypeOfCandidatesModule

		/// Every construction but `constant`.
		static let neighborsOfConstant = allCases.filter { $0 != .constant }

		/// `Formatter.swift`, in `Base`.
		var baseFile: String {
			switch self {
			case .constant, .instantiator, .lazilyInstantiated, .beneathTypeOfCandidatesModule:
				"""
				@Instantiable
				public final class Formatter: Instantiable {
				    package init() {}
				}
				"""
			case .existential:
				"""
				public protocol Formatting {}

				@Instantiable(fulfillingAdditionalTypes: [Formatting.self])
				public final class Formatter: Formatting, Instantiable {
				    package init() {}
				}
				"""
			case .nested:
				"""
				public enum Formats {
				    @Instantiable
				    public final class Formatter: Instantiable {
				        package init() {}
				    }
				}
				"""
			}
		}

		/// The type the error names.
		var formatterType: String {
			switch self {
			case .constant, .instantiator, .lazilyInstantiated, .existential, .beneathTypeOfCandidatesModule:
				"Formatter"
			case .nested:
				"Formats.Formatter"
			}
		}

		/// Where `Formatter`'s initializer starts in `baseFile`.
		var initializerLocation: (line: Int, column: Int) {
			switch self {
			case .constant, .instantiator, .lazilyInstantiated, .beneathTypeOfCandidatesModule:
				(3, 5)
			case .existential:
				(5, 5)
			case .nested:
				(4, 9)
			}
		}

		/// The property `Service` instantiates, and the declarations `Service.swift` holds after `Service`.
		var serviceProperty: String {
			switch self {
			case .constant:
				"formatter: Formatter"
			case .instantiator:
				"formatterBuilder: Instantiator<Formatter>"
			case .lazilyInstantiated:
				"formatter: LazilyInstantiated<Formatter>"
			case .existential:
				"formatter: any Formatting"
			case .nested:
				"formatter: Formats.Formatter"
			case .beneathTypeOfCandidatesModule:
				"cache: Cache"
			}
		}

		/// The declarations `Service.swift` holds after `Service`.
		var otherCoreDeclarations: String? {
			switch self {
			case .constant, .instantiator, .lazilyInstantiated, .existential, .nested:
				nil
			case .beneathTypeOfCandidatesModule:
				TokenCacheConstruction.type(declaredAs: "@Instantiable\npublic final class Cache", initializerModifier: "public ", instantiating: ["formatter: Formatter"], importing: nil)
			}
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
	mutating func generate_reportsEnclosingTypeOnceNamingTypeOfEarliestReference_whenSeveralTypesItEnclosesAreConstructed() async {
		// `Zulu` is declared first, but `Root` refers to `Alpha` first, so the error names `Alpha`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Namespace.swift"]):1:1: error: `Namespace`, which encloses `Namespace.Alpha`, is `internal`, so module `App`, another module of the same package, cannot construct `Namespace.Alpha` in the code SafeDI generates. Make `Namespace` `package` to fix.
			\(fixtures["Feature"]!["Namespace.swift"]):1:1-1:1: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.featureDeclaringNamespace(enclosing: ["Zulu", "Alpha"], deletesSwiftFilesAfterRunning: false),
					Self.app(inPackage: "Shop", declaring: Self.rootReferringToAlphaThenZulu),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsEnclosingTypeOnceAtEarliestReferenceNamingTypeItConstructs_whenDeclaringFileCannotBeRead() async {
		// `Zulu` is declared first, but `Root` refers to `Alpha` first, so the error is reported there and names `Alpha`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):10:5: error: `Namespace`, which encloses `Namespace.Alpha`, is `internal` in module `Feature`, so module `App`, another module of the same package, cannot construct `Namespace.Alpha` in the code SafeDI generates. Make `Namespace` `package` in module `Feature` to fix.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.featureDeclaringNamespace(enclosing: ["Zulu", "Alpha"], deletesSwiftFilesAfterRunning: true),
					Self.app(inPackage: "Shop", declaring: Self.rootReferringToAlphaThenZulu),
				],
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsEnclosingTypeOnceNamingTypeDeclaredFirst_whenOneReferenceLeadsToSeveralTypesItEncloses() async {
		// Every mock refers to its tree from the `#SafeDIConfiguration` that lists it, so the error names the type
		// declared first: `Mike`, whose mock is checked neither first nor last, as mocks are checked in type order.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["SafeDIConfiguration.swift"]):1:1: error: `Namespace`, which encloses `Namespace.Mike`, is `internal` in module `Feature`, so the mock of `Namespace.Mike`, generated in module `App`, another module of the same package, cannot construct `Namespace.Mike` in the code SafeDI generates. Make `Namespace` `package` in module `Feature` to fix.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.featureDeclaringNamespace(enclosing: ["Mike", "Zulu", "Alpha"], deletesSwiftFilesAfterRunning: true),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"SafeDIConfiguration.swift": """
							#SafeDIConfiguration(additionalMocksToGenerate: ["Namespace.Alpha", "Namespace.Mike", "Namespace.Zulu"])
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
			\(fixtures["App"]!["Service.swift"]):1:1: error: `Namespace`, which encloses `Namespace.Service`, is `private`, so the mock of `Namespace.Service`, which SafeDI generates in another file of module `App`, cannot construct `Namespace.Service`. Make `Namespace` `internal` to fix.
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
		// Roots are checked in type order – `Alpha`, in `C.swift`, `Mike`, in `A.swift`, then `Zulu`, in `B.swift` – so
		// the reference that comes first in source order is checked neither first nor last.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["A.swift"]):8:5: error: `Service` is `internal` in module `Feature`, so module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` in module `Feature` to fix.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(inPackage: "Shop", declaring: Self.internalServiceWithPackageInitializer, deletesSwiftFilesAfterRunning: true),
					Self.appInstantiatingService(
						in: ["A.swift": "Mike", "B.swift": "Zulu", "C.swift": "Alpha"],
						decoratedWith: "@Instantiable(isRoot: true)",
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
			\(servicePath):2:1: error: `Service` is `internal`, so this module, which SafeDI cannot tell is in the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` to fix, which needs both modules compiled with one package name (`SWIFT_PACKAGE_NAME` in an Xcode project), or `public` if the two modules are in different packages.
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
	mutating func generate_reportsSeamBuiltInlineAtItsReferenceAndEachDeclaration_whenTargetThatNamesNoModuleCannotConstructItsTree() async {
		// As the Xcode project plugin runs the tool for an app target that reads its local package's modules through
		// `additionalDirectoriesToInclude`: a CSV of the target's own files, `scan` while planning, then `generate` with
		// the manifest, and no target graph, so SafeDI knows no module, and the errors are those of any run given no
		// module name. They are joined in source order, and the harness writes the target's files and the additional
		// directory into directories with random names.
		await assertThrowsError(diagnostics: { fixtures in
			let rootPath = NormalizedFilePath(fixtures.compilerPath(of: "Root.swift")).path
			let featureViewPath = fixtures["AdditionalDirectory/FeatureView.swift"]
			let inlineSeamError = "\(rootPath):9:5: error: \(Self.inlineSeamMessage(reaching: "`Formatter` is `internal`"))"
			let featureViewErrors = """
			\(featureViewPath):5:5: error: `FeatureView`’s initializer is `internal`, so this module, which SafeDI cannot tell is in the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix, which needs both modules compiled with one package name (`SWIFT_PACKAGE_NAME` in an Xcode project), or `public` if the two modules are in different packages.
			\(featureViewPath):5:5-5:5: fixit: package\(" ")
			\(featureViewPath):15:1: error: `Formatter` is `internal`, so this module, which SafeDI cannot tell is in the same package, cannot construct it in the code SafeDI generates. Make `Formatter` `package` to fix, which needs both modules compiled with one package name (`SWIFT_PACKAGE_NAME` in an Xcode project), or `public` if the two modules are in different packages.
			\(featureViewPath):15:1-15:1: fixit: package\(" ")
			\(featureViewPath):16:5: error: `Formatter`’s initializer is `internal`, so this module, which SafeDI cannot tell is in the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix, which needs both modules compiled with one package name (`SWIFT_PACKAGE_NAME` in an Xcode project), or `public` if the two modules are in different packages.
			\(featureViewPath):16:5-16:5: fixit: package\(" ")
			"""
			return rootPath < featureViewPath ? "\(inlineSeamError)\n\(featureViewErrors)" : "\(featureViewErrors)\n\(inlineSeamError)"
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.rootReferringToFeatureView,
					"""
					#SafeDIConfiguration(additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"])
					""",
				],
				additionalDirectorySwiftFileContent: [
					Self.featureViewFile(formatterDeclaration: Self.internalFormatter),
					Self.packageNetworkClient,
				],
				pluginInvocation: .scanWhilePlanning(reportsFixtureDirectoryThroughSymbolicLink: false),
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsConstructionNamingMock_whenTargetThatNamesNoModuleCannotConstructTypeItsMockBuilds() async {
		// The mock of `Screen`, a type of the target's own, builds `Formatter`, which the target reads from another
		// directory, as under the Xcode project plugin: the error names the mock and the module it is generated in.
		await assertThrowsError(diagnostics: { fixtures in
			let formatterPath = fixtures["AdditionalDirectory/Formatter.swift"]
			return """
			\(formatterPath):2:1: error: `Formatter` is `internal`, so the mock of `Screen`, generated in this module, which SafeDI cannot tell is in the same package, cannot construct it in the code SafeDI generates. Make `Formatter` `package` to fix, which needs both modules compiled with one package name (`SWIFT_PACKAGE_NAME` in an Xcode project), or `public` if the two modules are in different packages.
			\(formatterPath):2:1-2:1: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					struct Screen: Instantiable {
					    init(formatter: Formatter) {
					        self.formatter = formatter
					    }

					    @Instantiated let formatter: Formatter
					}
					""",
					"""
					#SafeDIConfiguration(additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"])
					""",
				],
				additionalDirectorySwiftFileContent: [
					"""
					@Instantiable
					struct Formatter: Instantiable {
					    package init() {}
					}
					""",
				],
				pluginInvocation: .scanWhilePlanning(reportsFixtureDirectoryThroughSymbolicLink: false),
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsSeamBuiltInlineNamingItsInitializer_whenTargetThatNamesNoModuleCannotConstructOnlyTheSeam() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let rootPath = NormalizedFilePath(fixtures["App"]!.compilerPath(of: "Root.swift")).path
			let featureViewPath = NormalizedFilePath(fixtures["Feature"]!.compilerPath(of: "FeatureView.swift")).path
			return """
			\(rootPath):9:5: error: \(Self.inlineSeamMessage(reaching: "`FeatureView`’s initializer is `internal`"))
			\(featureViewPath):5:5: error: `FeatureView`’s initializer is `internal`, so this module, which SafeDI cannot tell is in the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix, which needs both modules compiled with one package name (`SWIFT_PACKAGE_NAME` in an Xcode project), or `public` if the two modules are in different packages.
			\(featureViewPath):5:5-5:5: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesOfTargetReachingFeatureView(formatterDeclaration: """
				package struct Formatter: Instantiable {
				    package init() {}
				}
				"""),
				integration: .swiftPackagePlugin,
				writesTargetGraph: false,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamsInitializer_whenTargetGraphNamesModuleOfSeamWhoseTreeTargetCannotConstruct() async throws {
		// The modules a run that names no module builds `FeatureView`'s tree inline for, where `App` cannot construct
		// `Formatter`, built with the target graph the SwiftPM plugin writes: `Feature` generates `FeatureView`'s
		// initializer, which constructs its own `Formatter`, and `App` calls it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesOfTargetReachingFeatureView(formatterDeclaration: Self.internalFormatter),
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)

		#expect(try #require(output.modules["Feature"]).generatedFiles == [
			"FeatureView+SafeDI.swift": generatedFileHeader + Self.importBlock("Core") + "\n\n" + """
			extension FeatureView {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    package init() {
			        let networkClient = NetworkClient()
			        let formatter = Formatter()
			        self.init(networkClient: networkClient, formatter: formatter)
			    }
			}

			extension FeatureView {
			    public enum __safeDI_FeatureView_CBF29CE484222325 {}
			}
			""",
		])
		#expect(try #require(output.modules["App"]).generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + Self.importBlock("Core") + "\n" + Self.importBlock("Feature") + "\n\n" + """
			extension Root {
			    public init() {
			        func __safeDI_featureView() -> FeatureView {
			            _ = FeatureView.__safeDI_FeatureView_CBF29CE484222325.self // If this line does not compile, add the SafeDI plugin to the target that declares FeatureView.
			            return FeatureView()
			        }
			        let featureView: FeatureView = __safeDI_featureView()
			        self.init(featureView: featureView)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_commentsSeamBuiltInlineAndAssumesPackageAccess_whenRunThatNamesNoModuleBuildsPackageSeamOfUnnamedModule() async throws {
		// `App` reads `Feature`'s files with no target graph and no module name, as the Xcode project plugin runs the tool,
		// so SafeDI knows neither module: it builds `Screen`'s tree inline, and assumes `package` access reaches it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContentByFilePath: [
						"Screen.swift": """
						@Instantiable(generateDependencyTree: true)
						package struct Screen: Instantiable {
						    package init(session: Session, detail: Detail) {
						        self.session = session
						        self.detail = detail
						    }

						    @Received let session: Session
						    @Instantiated let detail: Detail
						}

						@Instantiable
						package struct Detail: Instantiable {
						    package init(session: Session) {
						        self.session = session
						    }

						    @Received let session: Session
						}

						@Instantiable
						public struct Session: Instantiable {
						    public init() {}
						}
						""",
					],
				),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContentByFilePath: [
						"Root.swift": """
						import Feature

						@Instantiable(isRoot: true)
						struct Root: Instantiable {
						    init(session: Session, screen: Screen) {
						        self.session = session
						        self.screen = screen
						    }

						    @Instantiated let session: Session
						    @Instantiated let screen: Screen
						}
						""",
					],
					dependencies: ["Feature"],
				),
			],
			integration: .swiftPackagePlugin,
			writesTargetGraph: false,
			filesToDelete: &filesToDelete,
		)

		// The seam's construction says it is built inline; neither construction says that it relies on `package` access.
		let header = generatedFileHeader + Self.importBlock("Feature") + "\n\n"
		#expect(try #require(output.modules["App"]).generatedFiles == [
			"Root+SafeDI.swift": header + """
			extension Root {
			    public init() {
			        let session = Session()
			        func __safeDI_screen() -> Screen {
			            let detail = Detail(session: session)
			            return Screen(session: session, detail: detail) // Built inline: SafeDI does not know which module declares `Screen`, so this tree cannot call the initializer SafeDI generates for it.
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(session: session, screen: screen)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoSeamBuiltInline_whenModuleThatNamesNoModuleCallsSeamOfNamedModule() async {
		// `App` calls the initializer `Feature` generates for `FeatureView`, which `App` cannot reach because `FeatureView`
		// is `package`, and builds none of its tree.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["FeatureView.swift"]):2:1: error: `FeatureView` is `package`, so this module, in another package, cannot construct it in the code SafeDI generates. Make `FeatureView` `public` to fix.
			\(fixtures["Feature"]!["FeatureView.swift"]):2:1-2:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Feature",
						packageName: "Kit",
						swiftFileContentByFilePath: [
							"FeatureView.swift": """
							@Instantiable(generateDependencyTree: true)
							package struct FeatureView: Instantiable {
							    package init(formatter: Formatter) {
							        self.formatter = formatter
							    }

							    @Instantiated let formatter: Formatter
							}

							@Instantiable
							struct Formatter: Instantiable {
							    init() {}
							}
							""",
						],
					),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [
							"""
							import Feature

							@Instantiable(isRoot: true)
							struct Root: Instantiable {
							    init(featureView: FeatureView) {
							        self.featureView = featureView
							    }

							    @Instantiated let featureView: FeatureView
							}
							""",
						],
						dependencies: ["Feature"],
						omitsModuleName: true,
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenHandWrittenManifestNamesNoOwnFilesAndAdditionalDirectoryDeclaresInternalType() async throws {
		// A hand-written manifest that names no `mockScopedFilePaths` makes the input files the module's own, and a
		// file reached through `additionalDirectoriesToInclude` is not one of them.
		let directory = TestTemporaryDirectory.root.appendingPathComponent(UUID().uuidString)
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
			\(serviceFile.path):2:1: error: `Service` is `internal`, so this module, which SafeDI cannot tell is in the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` to fix, which needs both modules compiled with one package name (`SWIFT_PACKAGE_NAME` in an Xcode project), or `public` if the two modules are in different packages.
			\(serviceFile.path):2:1-2:1: fixit: package\(" ")
			""")
		}
	}

	// MARK: Tests – Modules SafeDI is not told the package of

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingToPassPackage_whenModuleWithPackageConstructsPackageTypeOfModuleRunWithoutItsPackage() async {
		// `Feature` is compiled in package `Shop`, but its run is not told so, as a hand-wired build might do: a named
		// module SafeDI is not told the package of has none, so `App` needs `public`, and the error says how to tell SafeDI.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = fixtures["Feature"]!["Service.swift"]
			return """
			\(servicePath):2:1: error: `Service` is `package`, so module `App`, which SafeDI is not told is in the same package, cannot construct it in the code SafeDI generates. Give module `Feature` the package name of module `App` (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if the two are in one package, or make `Service` `public` to fix.
			\(servicePath):2:1-2:8: fixit: public
			\(servicePath):3:5: error: `Service`’s initializer is `package`, so module `App`, which SafeDI is not told is in the same package, cannot call it in the code SafeDI generates. Give module `Feature` the package name of module `App` (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if the two are in one package, or make the initializer `public` to fix.
			\(servicePath):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContent: [Self.packageService],
						omitsPackageName: true,
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
	mutating func generate_throwsErrorOfferingToPassPackage_whenModuleRunWithoutItsPackageConstructsPackageTypeOfModuleWithPackage() async {
		// The mirror of the case above: `App` is compiled in package `Shop`, but its run is not told so.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = fixtures["Feature"]!["Service.swift"]
			return """
			\(servicePath):2:1: error: `Service` is `package`, so module `App`, which SafeDI is not told is in the same package, cannot construct it in the code SafeDI generates. Give module `App` the package name of module `Feature` (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if the two are in one package, or make `Service` `public` to fix.
			\(servicePath):2:1-2:8: fixit: public
			\(servicePath):3:5: error: `Service`’s initializer is `package`, so module `App`, which SafeDI is not told is in the same package, cannot call it in the code SafeDI generates. Give module `App` the package name of module `Feature` (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if the two are in one package, or make the initializer `public` to fix.
			\(servicePath):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(inPackage: "Shop", declaring: Self.packageService),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [Self.rootInstantiating("Service")],
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
	mutating func generate_throwsErrorOfferingToPassBothPackages_whenNeitherModuleIsToldItsPackage() async {
		// Bazel's default: both modules are named and neither is given a package, so a `package` type of one never
		// reaches the other.
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
						swiftFileContent: [Self.packageService],
						omitsPackageName: true,
					),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [Self.rootInstantiating("Service")],
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
	mutating func generate_throwsErrorOfferingPublicThenBothPackagesAndPackageAccess_whenNeitherModuleIsToldItsPackageAndInitializerIsInternal() async {
		// Bazel's commonest slip: a `public` type whose initializer spells no access. SafeDI cannot tell the two modules
		// are in different packages, so beside `public`, which the fix-it inserts, the error offers passing the packages
		// with `package` access, which an `internal` initializer still needs.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = fixtures["Feature"]!["Service.swift"]
			return """
			\(servicePath):3:5: error: `Service`’s initializer is `internal`, so module `App`, which SafeDI is not told is in the same package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix, or, if the two modules are in one package, give modules `App` and `Feature` the same package name (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) and make it `package`.
			\(servicePath):3:5-3:5: fixit: public\(" ")
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
							public final class Service: Instantiable {
							    init() {}
							}
							""",
						],
						omitsPackageName: true,
					),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [Self.rootInstantiating("Service")],
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
	mutating func generate_throwsErrorOfferingPublicThenPackageNameAndPackageAccess_whenModuleRunWithoutItsPackageConstructsInternalTypeOfModuleWithPackage() async {
		// `App` is compiled in package `Shop`, but its run is not told so, and `Service` spells no access: beside `public`,
		// the error offers giving `App` `Feature`'s package name with `package` access, which both declarations need.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = fixtures["Feature"]!["Service.swift"]
			return """
			\(servicePath):2:1: error: `Service` is `internal`, so module `App`, which SafeDI is not told is in the same package, cannot construct it in the code SafeDI generates. Make `Service` `public` to fix, or, if the two modules are in one package, give module `App` the package name of module `Feature` (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) and make it `package`.
			\(servicePath):2:1-2:1: fixit: public\(" ")
			\(servicePath):3:5: error: `Service`’s initializer is `internal`, so module `App`, which SafeDI is not told is in the same package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix, or, if the two modules are in one package, give module `App` the package name of module `Feature` (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) and make it `package`.
			\(servicePath):3:5-3:5: fixit: public\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(inPackage: "Shop", declaring: """
					@Instantiable
					final class Service: Instantiable {
					    init() {}
					}
					"""),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [Self.rootInstantiating("Service")],
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
	mutating func generate_throwsErrorJoiningRemediesWithSemicolons_whenPackageNameRemedyIsFollowedBySeamRemedy() async {
		// A remedy after the package-name remedy would read as part of its "if" clause, so the three remedies are joined
		// with semicolons.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let formatterPath = fixtures["Feature"]!["Formatter.swift"]
			return """
			\(formatterPath):3:5: error: `Formatter`’s initializer is `internal`, so module `App`, which SafeDI is not told is in the same package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix; if the two modules are in one package, give modules `App` and `Feature` the same package name (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) and make it `package`; or declare `Screen` with `generateDependencyTree: true`, so that module `Feature` generates its tree and this module calls the initializer it generates.
			\(formatterPath):3:5-3:5: fixit: public\(" ")
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
							public final class Screen: Instantiable {
							    public init(formatter: Formatter) {
							        self.formatter = formatter
							    }

							    @Instantiated let formatter: Formatter
							}
							""",
							"""
							@Instantiable
							public final class Formatter: Instantiable {
							    init() {}
							}
							""",
						],
						omitsPackageName: true,
					),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [Self.rootInstantiating("Screen")],
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
	mutating func generate_constructsPublicTypeWithoutComment_whenNeitherModuleIsToldItsPackage() async throws {
		// Both modules are compiled without `-package-name`, so `public` is what reaches across, and the construction
		// says nothing about packages.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						"""
						@Instantiable
						public final class Service: Instantiable {
						    public init() {}
						}
						""",
					],
					omitsPackageName: true,
				),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContent: [Self.rootInstantiating("Service")],
					dependencies: ["Feature"],
					omitsPackageName: true,
				),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(try #require(output.modules["App"]).generatedFiles == Self.appGeneratedFiles(under: .moduleInfo, code: """
		extension Root {
		    public convenience init() {
		        let service = Service()
		        self.init(service: service)
		    }
		}
		"""))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingMockAndOfferingToPassBothPackages_whenMockCallsPackageMockMethodAndNeitherModuleIsToldItsPackage() async {
		// `Screen`'s mock builds `Service` with its hand-written `package` mock, which needs `public` across two modules
		// SafeDI is told no package of.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = fixtures["Feature"]!["Service.swift"]
			return """
			\(servicePath):5:5: error: `Service.mock()` is `package`, so the mock of `Screen`, generated in module `App`, which SafeDI is not told is in the same package, cannot call it in the code SafeDI generates. Give modules `App` and `Feature` the same package name (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if they are in one package, or make `Service.mock()` `public` to fix.
			\(servicePath):5:5-5:12: fixit: public
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
							public final class Service: Instantiable {
							    public init() {}

							    package static func mock() -> Service { Service() }
							}
							""",
						],
						omitsPackageName: true,
					),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [Self.screenMockedInApp],
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
	mutating func generate_assumesPackageAccessWithoutComment_whenNamedModuleConstructsPackageTypeOfAdditionalDirectory() async throws {
		// `App` reads `Feature`'s files through `additionalDirectoriesToInclude`, so SafeDI knows no module that declares
		// `Service`, and assumes `package` access reaches it; the construction says nothing about it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [Self.packageService],
					runsSafeDI: false,
				),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContentByFilePath: [
						"Root.swift": Self.rootInstantiating("Service"),
						"SafeDIConfiguration.swift": "#SafeDIConfiguration(additionalDirectoriesToInclude: [\"$FIXTURE_ROOT/Shop/Sources/Feature\"])\n",
					],
					dependencies: ["Feature"],
				),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(try #require(output.modules["App"]).generatedFiles == Self.appGeneratedFiles(under: .moduleInfo, code: """
		extension Root {
		    public convenience init() {
		        let service = Service()
		        self.init(service: service)
		    }
		}
		"""))
	}

	// MARK: Tests – Mocks

	/// BZ-4's modules, in package `Shop`: `Storage` declares what the trees receive; `Feature` declares the seam
	/// `ProfileScreen`, `package`, whose tree constructs `ProfileStore` with its `internal` initializer and the `internal`
	/// `BioFormatter`; `App`'s root calls the seam, and the mock of `LoggedInView` builds the seam's tree inline.
	private static func modulesWhoseMockReachesPackageSeam(featureFilesAreDeleted: Bool = false) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Storage", packageName: "Shop", swiftFileContent: [
				"""
				public protocol StringStorage {}

				@Instantiable(fulfillingAdditionalTypes: [StringStorage.self])
				public final class DefaultStringStorage: Instantiable, StringStorage {
				    public init() {}
				}

				public struct User {
				    public init() {}
				}
				""",
			]),
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContentByFilePath: ["ProfileScreen.swift": """
				import Storage

				@Instantiable(generateDependencyTree: true)
				package struct ProfileScreen: Instantiable {
				    package init(user: User, stringStorage: StringStorage, profileStore: ProfileStore) {
				        self.user = user
				        self.stringStorage = stringStorage
				        self.profileStore = profileStore
				    }

				    @Received let user: User
				    @Received let stringStorage: StringStorage
				    @Instantiated let profileStore: ProfileStore
				}

				@Instantiable
				package final class ProfileStore: Instantiable {
				    init(stringStorage: StringStorage, bioFormatter: BioFormatter) {
				        self.stringStorage = stringStorage
				        self.bioFormatter = bioFormatter
				    }

				    @Received let stringStorage: StringStorage
				    @Instantiated let bioFormatter: BioFormatter
				}

				@Instantiable
				struct BioFormatter: Instantiable {
				    init() {}
				}
				"""],
				dependencies: ["Storage"],
				deletesSwiftFilesAfterRunning: featureFilesAreDeleted,
			),
			ModuleFixture(
				name: "App",
				packageName: "Shop",
				swiftFileContentByFilePath: ["Root.swift": """
				import Feature
				import SafeDI
				import Storage

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(stringStorage: StringStorage, loggedInViewBuilder: Instantiator<LoggedInView>) {
				        self.stringStorage = stringStorage
				        self.loggedInViewBuilder = loggedInViewBuilder
				    }

				    @Instantiated let stringStorage: StringStorage
				    @Instantiated let loggedInViewBuilder: Instantiator<LoggedInView>
				}

				@Instantiable(generateMock: true)
				public struct LoggedInView: Instantiable {
				    init(user: User, profileScreen: ProfileScreen) {
				        self.user = user
				        self.profileScreen = profileScreen
				    }

				    @Forwarded let user: User
				    @Instantiated let profileScreen: ProfileScreen
				}
				"""],
				dependencies: ["Storage", "Feature"],
			),
		]
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingMockAndSuggestingPublicMockOfPackageSeam_whenMockBuildsSeamsTreeInline(integration: MultiModuleIntegration) async {
		// BZ-4: the errors name the mock, whose tree the user did not write, and suggest declaring the `package` seam the
		// mock builds inline `public` with a public mock, which the mock would call instead.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let path = Self.declarationPath(of: "ProfileScreen.swift", in: "Feature", fixtures: fixtures, under: integration)
			let remedy = "or declare `ProfileScreen` `public` with `generateMock: .public`: mocks build a seam's tree inline, and this mock would call the mock `Feature` generates instead."
			return """
			\(path):18:5: error: `ProfileStore`’s initializer is `internal`, so the mock of `LoggedInView`, generated in module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix, \(remedy)
			\(path):18:5-18:5: fixit: package\(" ")
			\(path):28:1: error: `BioFormatter` is `internal`, so the mock of `LoggedInView`, generated in module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `BioFormatter` `package` to fix, \(remedy)
			\(path):28:1-28:1: fixit: package\(" ")
			\(path):29:5: error: `BioFormatter`’s initializer is `internal`, so the mock of `LoggedInView`, generated in module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix, \(remedy)
			\(path):29:5-29:5: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.modulesWhoseMockReachesPackageSeam(), integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtReferenceNamingMockAndDeclaringModule_whenMockBuildsSeamsTreeWhoseFileCannotBeRead() async {
		// BZ-4: a sandboxed Bazel action is handed `Feature`'s `.safedi` but not its files, so each error is reported
		// where `LoggedInView` instantiates the seam, naming the module that must change.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let remedy = "or declare `ProfileScreen` `public` with `generateMock: .public`: mocks build a seam's tree inline, and this mock would call the mock `Feature` generates instead."
			return """
			\(fixtures["App"]!["Root.swift"]):24:5: error: `BioFormatter` is `internal` in module `Feature`, so the mock of `LoggedInView`, generated in module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `BioFormatter` `package` in module `Feature` to fix, \(remedy)
			\(fixtures["App"]!["Root.swift"]):24:5: error: `BioFormatter`’s initializer is `internal` in module `Feature`, so the mock of `LoggedInView`, generated in module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make the initializer `package` in module `Feature` to fix, \(remedy)
			\(fixtures["App"]!["Root.swift"]):24:5: error: `ProfileStore`’s initializer is `internal` in module `Feature`, so the mock of `LoggedInView`, generated in module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make the initializer `package` in module `Feature` to fix, \(remedy)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesWhoseMockReachesPackageSeam(featureFilesAreDeleted: true),
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenMockConstructsTypeAnotherModuleCannotReach(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let servicePath = Self.declarationPath(of: "Service.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(servicePath):2:1: error: `Service` is `internal`, so the mock of `Screen`, generated in module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` to fix, or declare `Service` `public` with `generateMock: .public`.
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

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingNoSeam_whenOnlyMockConstructsPackageTypeThroughTypeOfAnotherModule(integration: MultiModuleIntegration) async {
		// Mocks build every tree inline, a seam's included, so declaring `Service` a seam would change nothing here; the
		// error names the mock and offers `Service` a public mock, which the mock would call instead.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let gatePath = Self.declarationPath(of: "Gate.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(gatePath):3:5: error: `Gate`’s initializer is `package`, so the mock of `Container`, generated in module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix, or give `Service` a public mock: `generateMock: .public`, or a hand-written public `mock`.
			\(gatePath):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.featureDeclaringGateBuiltByServiceAndSeam,
					Self.appInstantiatingServiceAndSeam(in: ["Container": "@Instantiable(generateMock: true)"]),
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
			\(fixtures["Feature"]!["Service.swift"]):2:1: error: `Service` is `internal`, so the mock of `Screen`, generated in module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` to fix, or declare `Service` `public` with `generateMock: .public`.
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
	mutating func generate_reportsInaccessibleConstructionOnceNamingMockDeclaredFirst_whenSeveralMocksReachItThroughOneReference() async {
		// BZ-4: `Screen`'s mock and `Zebra`'s, whose `Instantiator<Screen>` builds `Screen`, both reach `Service` through
		// `Screen`'s `service`: the one error names the mock declared first (`Zebra`, in `Container.swift`), not the mock
		// root checked first (`Screen`, by type order).
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):2:1: error: `Service` is `internal`, so the mock of `Zebra`, generated in module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` to fix, or declare `Service` `public` with `generateMock: .public`.
			\(fixtures["Feature"]!["Service.swift"]):2:1-2:1: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(inPackage: "Shop", declaring: Self.internalServiceWithPackageInitializer),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"Screen.swift": Self.screenMockedInApp,
							"Container.swift": """
							import SafeDI

							@Instantiable(generateMock: true)
							final class Zebra: Instantiable {
							    init(screenBuilder: Instantiator<Screen>) {
							        self.screenBuilder = screenBuilder
							    }
							    @Instantiated let screenBuilder: Instantiator<Screen>
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
		// Mock roots are checked in type order – `Alpha`, in `C.swift`, `Mike`, in `A.swift`, then `Zulu`, in `B.swift` –
		// so the reference that comes first in source order is checked neither first nor last.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["A.swift"]):8:5: error: `Service` is `internal` in module `Feature`, so the mock of `Mike`, generated in module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` in module `Feature` to fix, or declare `Service` `public` with `generateMock: .public`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(inPackage: "Shop", declaring: Self.internalServiceWithPackageInitializer, deletesSwiftFilesAfterRunning: true),
					Self.appInstantiatingService(
						in: ["A.swift": "Mike", "B.swift": "Zulu", "C.swift": "Alpha"],
						decoratedWith: "@Instantiable(generateMock: true)",
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
	mutating func generate_throwsErrorAtConfigurationNamingDeclaringModule_whenAdditionalMockConstructsTypeWhoseFileCannotBeRead() async {
		// No type of `App` builds `Service`, so the mock `App` generates for it refers to it from the
		// `#SafeDIConfiguration` that lists it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["SafeDIConfiguration.swift"]):1:1: error: `Service` is `internal` in module `Feature`, so the mock of `Service`, generated in module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` in module `Feature` to fix, or declare `Service` `public` with `generateMock: .public`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.feature(inPackage: "Shop", declaring: Self.internalServiceWithPackageInitializer, deletesSwiftFilesAfterRunning: true),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"SafeDIConfiguration.swift": """
							#SafeDIConfiguration(additionalMocksToGenerate: ["Service"])
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
			\(fixtures["Feature"]!["Service.swift"]):2:1: error: `Service` is `internal`, so module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Service` `package` to fix\(Self.seamRemedy(declaring: "Hub", in: "Feature")).
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
	mutating func generate_takesForwardedParameterWithoutDefault_whenItsHandWrittenMockIsInternalToAnotherModule() async throws {
		// `App` cannot call `User.mock()`, so `mock()` does not default `user` to it, and nothing is reported.
		let output = try await executeSafeDIToolMultiModuleTest(
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

		#expect(try #require(output.modules["App"]).generatedFiles == [
			"App.swift": generatedFileHeader + Self.importBlock("Feature") + "\n\n" + """
			#if DEBUG
			extension Profile {
			    static func mock(
			        user: User
			    ) -> Profile {
			        return Profile(user: user)
			    }
			}
			#endif
			""",
		])
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
			\(fixtures["TestSupport"]!["ServiceMock.swift"]):5:5: error: `Service.mock()` is `internal`, so the mock of `Screen`, generated in module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make `Service.mock()` `package` to fix.
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
			\(fixtures["TestSupport"]!["ServiceMock.swift"]):4:1: error: The extension that declares `Service.mock()` is `internal`, so the mock of `Screen`, generated in module `App`, another module of the same package, cannot call `Service.mock()` in the code SafeDI generates. Make the extension `package` to fix.
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
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWithPublicFixItAtExtension_whenAnotherPackageCallsHandWrittenMockTakingPackageFromItsExtension(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let mockPath = Self.declarationPath(of: "ServiceMock.swift", in: "TestSupport", fixtures: fixtures, under: integration)
			return """
			\(mockPath):4:1: error: The extension that declares `Service.mock()` is `package`, so the mock of `Screen`, generated in module `App`, in another package, cannot call `Service.mock()` in the code SafeDI generates. Make the extension `public` to fix.
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

	// MARK: Tests – Types an extension of a plain type declares

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtNamespaceEnum_whenAnotherPackageConstructsPublicTypeDeclaredInUnspelledExtensionOfPackageEnum(integration: MultiModuleIntegration) async {
		// `Space.swift` holds no SafeDI marker, so `scan` reads it only because an extension holding an `@Instantiable`
		// type extends a type it may declare.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let spacePath = Self.declarationPath(of: "Space.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(spacePath):2:1: error: `Space`, which encloses `Space.Shelf`, is `package`, so module `App`, in another package, cannot construct `Space.Shelf` in the code SafeDI generates. Make `Space` `public` to fix, or declare `Screen` with `generateDependencyTree: true`, so that module `Feature` generates its tree and this module calls the initializer it generates.
			\(spacePath):2:1-2:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.featureExtendingNamespace(inPackage: "Toolkit", declaredAs: "package enum Space {}"),
					Self.app(inPackage: "Shop", serviceType: "Screen"),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_constructsPublicTypeDeclaredInUnspelledExtensionOfPublicEnum_whenAnotherPackageConstructsIt(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.featureExtendingNamespace(inPackage: "Toolkit", declaredAs: "public enum Space {}"),
				Self.app(inPackage: "Shop", serviceType: "Screen"),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		#expect(try #require(output.modules["App"]).generatedFiles == Self.appGeneratedFiles(under: integration, code: """
		extension Root {
		    public convenience init() {
		        func __safeDI_service() -> Screen {
		            let shelf: any Shelving = Space.Shelf()
		            return Screen(shelf: shelf)
		        }
		        let service: Screen = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""))
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtNamespaceEnum_whenAnotherModuleOfPackageConstructsPublicTypeDeclaredInUnspelledExtensionOfInternalEnum(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let spacePath = Self.declarationPath(of: "Space.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(spacePath):2:1: error: `Space`, which encloses `Space.Shelf`, is `internal`, so module `App`, another module of the same package, cannot construct `Space.Shelf` in the code SafeDI generates. Make `Space` `package` to fix, or declare `Screen` with `generateDependencyTree: true`, so that module `Feature` generates its tree and this module calls the initializer it generates.
			\(spacePath):2:1-2:1: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.featureExtendingNamespace(inPackage: "Shop", declaredAs: "enum Space {}"),
					Self.app(inPackage: "Shop", serviceType: "Screen"),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtExtendedType_whenAnotherModuleConstructsExtensionBasedTypeWhosePlainDeclarationIsInternal(integration: MultiModuleIntegration) async {
		// The extension caps nothing, and `instantiate()` is `public`, but code that calls it names `Rack`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let rackPath = Self.declarationPath(of: "Rack.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(rackPath):1:1: error: `Rack` is `internal`, so module `App`, another module of the same package, cannot construct it in the code SafeDI generates. Make `Rack` `package` to fix, or declare `Screen` with `generateDependencyTree: true`, so that module `Feature` generates its tree and this module calls the initializer it generates.
			\(rackPath):1:1-1:1: fixit: package\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(
						name: "Feature",
						packageName: "Shop",
						swiftFileContentByFilePath: [
							"Screen.swift": """
							@Instantiable
							public final class Screen: Instantiable {
							    public init(rack: any Racking) {
							        self.rack = rack
							    }
							    @Instantiated(fulfilledByType: "Rack") let rack: any Racking
							}
							""",
							"Rack.swift": """
							final class Rack: Racking {
							    init() {}
							}
							""",
							"Rack+Instantiable.swift": """
							public protocol Racking {}

							@Instantiable
							extension Rack: Instantiable {
							    public static func instantiate() -> Rack {
							        Rack()
							    }
							}
							""",
						],
					),
					Self.app(inPackage: "Shop", serviceType: "Screen"),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtNamespaceEnumOfferingToPassPackages_whenTypeDeclaredInExtensionOfPackageEnumIsConstructedAcrossModulesToldNoPackage() async {
		// Neither run is told a package, so `App` needs `public` of the namespace, as it would from another package, and
		// the error says how to tell SafeDI the package `Feature` is compiled with.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let spacePath = fixtures["Feature"]!["Space.swift"]
			return """
			\(spacePath):2:1: error: `Space`, which encloses `Space.Shelf`, is `package`, so module `App`, which SafeDI is not told is in the same package, cannot construct `Space.Shelf` in the code SafeDI generates. Give modules `App` and `Feature` the same package name (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if they are in one package, or make `Space` `public` to fix, or declare `Screen` with `generateDependencyTree: true`, so that module `Feature` generates its tree and this module calls the initializer it generates.
			\(spacePath):2:1-2:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.featureExtendingNamespace(inPackage: "Shop", declaredAs: "package enum Space {}", omitsPackageName: true),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [Self.rootInstantiating("Screen")],
						dependencies: ["Feature"],
						omitsPackageName: true,
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtEnclosingNamespace_whenAnotherPackageConstructsPublicTypeDeclaredInUnspelledExtensionOfNestedPublicEnumOfPackageEnum(integration: MultiModuleIntegration) async {
		// The extension extends `Outer.Space`, whose file declares it inside `Outer`: the outermost type is what is narrower.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let spacePath = Self.declarationPath(of: "Space.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(spacePath):2:1: error: `Outer`, which encloses `Outer.Space.Shelf`, is `package`, so module `App`, in another package, cannot construct `Outer.Space.Shelf` in the code SafeDI generates. Make `Outer` `public` to fix, or declare `Screen` with `generateDependencyTree: true`, so that module `Feature` generates its tree and this module calls the initializer it generates.
			\(spacePath):2:1-2:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.featureExtendingNamespace(inPackage: "Toolkit", declaredAs: "package enum Outer {\n    public enum Space {}\n}", extending: "Outer.Space"),
					Self.app(inPackage: "Shop", serviceType: "Screen"),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_constructsTypeDeclaredInUnspelledExtensionOfImportedNamespace_whenAnotherFileOfExtensionsModuleDeclaresFilePrivateTypeOfNamespacesName(integration: MultiModuleIntegration) async throws {
		// `Metrics.swift`'s `Space` is invisible in `Shelf.swift`, whose extension therefore extends `Kit`'s `Space`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.kitDeclaringNamespaceAndAppImportingIt.kit,
				Self.featureExtendingNamespace(inPackage: "Toolkit", declaredAs: nil, importing: "Kit", alongside: [
					"Metrics.swift": """
					// A file-private helper that shares the namespace's name.
					private enum Space {
					    static let spacing = 4
					}

					func featureSpacing() -> Int {
					    Space.spacing
					}
					""",
				]),
				Self.kitDeclaringNamespaceAndAppImportingIt.app,
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let code = generatedFileHeader + Self.importBlock("Feature") + "\n" + Self.importBlock("Kit") + "\n\n" + """
		extension Root {
		    public convenience init() {
		        func __safeDI_service() -> Screen {
		            let shelf: any Shelving = Space.Shelf()
		            return Screen(shelf: shelf)
		        }
		        let service: Screen = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""
		#expect(try #require(output.modules["App"]).generatedFiles == [integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": code])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtFilePrivateNamespace_whenExtensionsOwnFileDeclaresFilePrivateTypeOfImportedNamespacesName(integration: MultiModuleIntegration) async {
		// A `private` type in the extension's own file is what the extension extends, so it is the namespace to report.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let shelfPath = Self.declarationPath(of: "Shelf.swift", in: "Feature", fixtures: fixtures, under: integration)
			return """
			\(shelfPath):5:1: error: `Space`, which encloses `Space.Shelf`, is `private`, so module `App`, in another package, cannot construct `Space.Shelf` in the code SafeDI generates. Make `Space` `public` to fix.
			\(shelfPath):5:1-5:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					Self.kitDeclaringNamespaceAndAppImportingIt.kit,
					Self.featureExtendingNamespace(inPackage: "Toolkit", declaredAs: nil, importing: "Kit", shelfFileDeclaration: """
					private enum Space {
					    static let spacing = 4
					}
					"""),
					Self.kitDeclaringNamespaceAndAppImportingIt.app,
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtTypealiasNamespace_whenAnotherPackageConstructsTypeInExtensionOfPackageTypealias(integration: MultiModuleIntegration) async {
		// C7: `Space` is a `package` typealias, which SafeDI now records as any plain declaration: code naming `Space.Shelf`
		// names `Space`, so `App`, in another package, is told to widen it (and Swift then requires `RealSpace` to be
		// `public` too, at the typealias).
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let spacePath = switch integration {
			case .moduleInfo:
				fixtures["Core"]!["Space.swift"]
			case .swiftPackagePlugin:
				NormalizedFilePath(fixtures["Core"]!.compilerPath(of: "Space.swift")).path
			}
			return """
			\(spacePath):2:1: error: `Space`, which encloses `Space.Shelf`, is `package`, so module `App`, in another package, cannot construct `Space.Shelf` in the code SafeDI generates. Make `Space` `public` to fix.
			\(spacePath):2:1-2:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: [
						"Space.swift": "package enum RealSpace {}\npackage typealias Space = RealSpace",
						"Shelf.swift": "public protocol Storage {}\n\nextension Space {\n    @Instantiable(fulfillingAdditionalTypes: [Storage.self])\n    public final class Shelf: Instantiable, Storage {\n        public init() {}\n    }\n}",
					]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Core\n\n@Instantiable(isRoot: true)\npublic struct Root: Instantiable {\n    public init(storage: any Storage) {\n        self.storage = storage\n    }\n\n    @Instantiated let storage: any Storage\n}"], dependencies: ["Core"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNamespaceDeclaredInSelectedClause_whenConstructingModuleCannotSeeIt(integration: MultiModuleIntegration) async {
		// IF16: `Space` is declared `package` in the clause `FLAG` selects, which SafeDI reads as any declaration outside a
		// block: `App`, in another package, is told to widen it, where the compiler would report the generated file.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let spacePath = switch integration {
			case .moduleInfo:
				fixtures["Core"]!["Space.swift"]
			case .swiftPackagePlugin:
				NormalizedFilePath(fixtures["Core"]!.compilerPath(of: "Space.swift")).path
			}
			return """
			\(spacePath):2:1: error: `Space`, which encloses `Space.Shelf`, is `package`, so module `App`, in another package, cannot construct `Space.Shelf` in the code SafeDI generates. Make `Space` `public` to fix.
			\(spacePath):2:1-2:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.shelfInSpaceModules(space: "#if FLAG\npackage enum Space {}\n#endif", conditions: ["FLAG"]),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNarrowestNamespace_whenPlatformClausesDeclareItAtDifferentLevels(integration: MultiModuleIntegration) async {
		// IF16b: the compiler may select either clause, so the construction check reads the narrower declaration of `Space`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let spacePath = switch integration {
			case .moduleInfo:
				fixtures["Core"]!["Space.swift"]
			case .swiftPackagePlugin:
				NormalizedFilePath(fixtures["Core"]!.compilerPath(of: "Space.swift")).path
			}
			return """
			\(spacePath):2:1: error: `Space`, which encloses `Space.Shelf`, is `package`, so module `App`, in another package, cannot construct `Space.Shelf` in the code SafeDI generates. Make `Space` `public` to fix.
			\(spacePath):2:1-2:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.shelfInSpaceModules(space: "#if os(Linux)\npackage enum Space {}\n#else\npublic enum Space {}\n#endif", conditions: []),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsFirstNamespaceInSourceOrder_whenPlatformClausesDeclareItAtLevelsThatCountAlike() async {
		// IF16c: `Space`'s clauses declare it `internal` and `fileprivate`, both of which count as `internal`, so the
		// construction check reads the first in source order rather than the one whose spelled level sorts first.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let spacePath = fixtures["Core"]!["Space.swift"]
			return """
			\(spacePath):2:1: error: `Space`, which encloses `Space.Shelf`, is `internal`, so module `App`, in another package, cannot construct `Space.Shelf` in the code SafeDI generates. Make `Space` `public` to fix.
			\(spacePath):2:1-2:1: fixit: public\(" ")
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: [
						"Space.swift": "#if os(Linux)\nenum Space {}\n#else\nfileprivate enum Space {}\n#endif\n\npublic protocol Storage {}\n\nextension Space {\n    @Instantiable(fulfillingAdditionalTypes: [Storage.self])\n    public final class Shelf: Instantiable, Storage {\n        public init() {}\n    }\n}",
					]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Core\n\n@Instantiable(isRoot: true)\npublic struct Root: Instantiable {\n    public init(storage: any Storage) {\n        self.storage = storage\n    }\n\n    @Instantiated let storage: any Storage\n}"], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtNamespace_whenItsMarkerFreeFileSpellsItsNameNeedlesslyInBackticks(integration: MultiModuleIntegration) async {
		// D3.8: the text search finds `` `Space` ``, and the declaration in backticks is the one the extension of `Space`
		// extends, so the check reads it, where the compiler would report the generated file. The error names the type as
		// its declaration spells it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let spacePath = Self.declarationPath(of: "Space.swift", in: "Core", fixtures: fixtures, under: integration)
			return """
			\(spacePath):1:1: error: ``Space``, which encloses `Space.Shelf`, is `package`, so module `App`, in another package, cannot construct `Space.Shelf` in the code SafeDI generates. Make ``Space`` `public` to fix.
			\(spacePath):1:1-1:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.shelfInSpaceModules(space: "package enum `Space` {}", conditions: []),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – Namespaces declared inside an extension

	/// How `Core` declares the namespaces that enclose `Helper` inside extensions, each in a file without a SafeDI marker.
	enum ExtensionNamespaceChain: CaseIterable, Sendable {
		/// `Outer.Namespace`, `package`, inside an extension of `Outer`, in `Namespace.swift`.
		case oneLink
		/// `Outer.A`, `package`, inside an extension of `Outer`, in `Namespace.swift`, and `Outer.A.B`, `public`, inside an
		/// extension of `Outer.A`, in `B.swift`.
		case twoLinks
		/// `Outer.Namespace`, a `package` `typealias` of `Real`, `public`, inside an extension of `Outer`, in
		/// `Namespace.swift`.
		case typealiasLink

		/// The files that declare the namespaces, with `level` in place of the narrowest one's `package`.
		func namespaceFiles(narrowestSpelled level: String = "package") -> [String: String] {
			switch self {
			case .oneLink:
				["Namespace.swift": "extension Outer {\n    \(level) enum Namespace {}\n}"]
			case .twoLinks:
				["Namespace.swift": "extension Outer {\n    \(level) enum A {}\n}", "B.swift": "extension Outer.A {\n    public enum B {}\n}"]
			case .typealiasLink:
				["Namespace.swift": "extension Outer {\n    \(level) typealias Namespace = Real\n}", "Real.swift": "public enum Real {}"]
			}
		}

		/// The type an extension declaring `Helper` extends.
		var extendedType: String {
			switch self {
			case .oneLink, .typealiasLink:
				"Outer.Namespace"
			case .twoLinks:
				"Outer.A.B"
			}
		}

		/// The narrowest namespace, which `Namespace.swift` declares `package` at its second line.
		var narrowestNamespace: String {
			switch self {
			case .oneLink, .typealiasLink:
				"Outer.Namespace"
			case .twoLinks:
				"Outer.A"
			}
		}
	}

	@Test(arguments: ExtensionNamespaceChain.allCases, MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtNarrowestNamespace_whenAnotherPackageConstructsTypeInExtensionOfNamespaceDeclaredInsideExtension(chain: ExtensionNamespaceChain, integration: MultiModuleIntegration) async {
		// D2.1, D2.3: the check follows `Helper`'s extended type to the declaration inside an extension of `Outer`, and on to
		// `Outer`, each in `Core`, and reports the `package` one, where the compiler would report the generated file.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let namespacePath = Self.declarationPath(of: "Namespace.swift", in: "Core", fixtures: fixtures, under: integration)
			let helper = "\(chain.extendedType).Helper"
			return """
			\(namespacePath):2:5: error: `\(chain.narrowestNamespace)`, which encloses `\(helper)`, is `package`, so module `App`, in another package, cannot construct `\(helper)` in the code SafeDI generates. Make `\(chain.narrowestNamespace)` `public` to fix.
			\(namespacePath):2:5-2:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesConstructingHelper(declaredInsideExtensionOf: chain.extendedType, namespaceFiles: chain.namespaceFiles(), appPackage: "Other"),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: ExtensionNamespaceChain.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtReferenceNamingNamespacesModule_whenFileDeclaringNamespaceInsideExtensionCannotBeRead(chain: ExtensionNamespaceChain) async {
		// D2.1, D2.3 under Bazel: `Core`'s `.safedi` carries the namespaces, and its files are gone, so the error is reported
		// where `App` refers to the construction, names `Core`, and offers no fix-it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let helper = "\(chain.extendedType).Helper"
			return """
			\(fixtures["App"]!["Root.swift"]):9:5: error: `\(chain.narrowestNamespace)`, which encloses `\(helper)`, is `package` in module `Core`, so module `App`, in another package, cannot construct `\(helper)` in the code SafeDI generates. Make `\(chain.narrowestNamespace)` `public` in module `Core` to fix.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesConstructingHelper(declaredInsideExtensionOf: chain.extendedType, namespaceFiles: chain.namespaceFiles(), appPackage: "Other", deletesCoreFiles: true),
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: ExtensionNamespaceChain.allCases, MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_constructsTypeInExtensionOfNamespaceDeclaredInsideExtension_whenFixItMakesNarrowestNamespacePublic(chain: ExtensionNamespaceChain, integration: MultiModuleIntegration) async throws {
		// D2.1, D2.3: the source the error's fix-it leaves, which compiles.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesConstructingHelper(declaredInsideExtensionOf: chain.extendedType, namespaceFiles: chain.namespaceFiles(narrowestSpelled: "public"), appPackage: "Other"),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == Self.rootFiles(under: integration, constructing: "\(chain.extendedType).Helper"))
	}

	@Test(arguments: ExtensionNamespaceChain.allCases, MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_constructsTypeInExtensionOfPackageNamespaceDeclaredInsideExtension_whenModuleOfItsPackageConstructsIt(chain: ExtensionNamespaceChain, integration: MultiModuleIntegration) async throws {
		// D2.2: another module of `Core`'s package can name the `package` namespace, as it could before the check followed it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesConstructingHelper(declaredInsideExtensionOf: chain.extendedType, namespaceFiles: chain.namespaceFiles(), appPackage: "Shop"),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == Self.rootFiles(under: integration, constructing: "\(chain.extendedType).Helper"))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingToPassPackages_whenTypeInExtensionOfPackageNamespaceDeclaredInsideExtensionIsConstructedFromModuleToldNoPackage() async {
		// `App` and `Core` are named and told no package, so each has none: the `package` `Outer.Namespace`, which the check
		// reads, needs `public`, and the error also offers passing the packages if the modules are compiled with one.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let namespacePath = Self.declarationPath(of: "Namespace.swift", in: "Core", fixtures: fixtures, under: .moduleInfo)
			return """
			\(namespacePath):2:5: error: `Outer.Namespace`, which encloses `Outer.Namespace.Helper`, is `package`, so module `App`, which SafeDI is not told is in the same package, cannot construct `Outer.Namespace.Helper` in the code SafeDI generates. Give modules `App` and `Core` the same package name (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if they are in one package, or make `Outer.Namespace` `public` to fix.
			\(namespacePath):2:5-2:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesConstructingHelper(
					declaredInsideExtensionOf: "Outer.Namespace",
					namespaceFiles: ExtensionNamespaceChain.oneLink.namespaceFiles(),
					appPackage: "Shop",
					omitsPackageNames: true,
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsNoDeclarationNamedLikeNestedInstantiable_whenMarkerFreeFileDeclaresTypeOfItsOwnName() async throws {
		// The names that keep plain declarations hold those bounding `Outer.Namespace.Helper`, `Outer` and `Namespace`, and
		// not `Helper`'s own: the check reads no other declaration of that name, so `Core` neither parses nor carries the
		// unrelated internal `Helper`, in a file without a marker and without the word `package`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesConstructingHelper(
				declaredInsideExtensionOf: "Outer.Namespace",
				namespaceFiles: ExtensionNamespaceChain.oneLink.namespaceFiles().merging(["Unrelated.swift": "struct Helper {}"], uniquingKeysWith: { first, _ in first }),
				appPackage: "Shop",
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.moduleInfo?.plainTypeDeclarations.map(\.typeDescription.asSource) == ["Outer.Namespace", "Outer"])
		#expect(output.modules["App"]?.generatedFiles == Self.rootFiles(under: .moduleInfo, constructing: "Outer.Namespace.Helper"))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_constructsTypeInExtensionOfNamespaceDeclaredInsideExtensionOfTypeOfModuleSafeDIDoesNotRead_whichThenFailsToCompile() async throws {
		// D2.4: `Kit` does not run SafeDI, so the check follows `Outer.Namespace`, `public`, to `Outer`, of which it reads no
		// declaration, and stops there: the compiler reports in the generated file that `App`, in another package, cannot
		// see the `package` `Outer`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Kit", packageName: "Shop", swiftFileContentByFilePath: ["Outer.swift": "package enum Outer {}"], runsSafeDI: false),
				ModuleFixture(
					name: "Core",
					packageName: "Shop",
					swiftFileContentByFilePath: [
						"Namespace.swift": "import Kit\n\nextension Outer {\n    public enum Namespace {}\n}",
						"Helper.swift": "import Kit\n\n" + Self.helperSource(declaredInsideExtensionOf: "Outer.Namespace"),
					],
					dependencies: ["Kit"],
				),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContentByFilePath: ["Root.swift": "import Kit\n" + Self.rootInstantiatingHelping], dependencies: ["Kit", "Core"]),
			],
			integration: .moduleInfo,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + Self.importBlock("Core") + "\n" + Self.importBlock("Kit") + "\n\n" + Self.rootCode(constructing: "Outer.Namespace.Helper")])
		try expectModuleCompilationFails(output, module: "App", containing: "cannot find 'Outer' in scope")
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_constructsTypeInExtensionOfNamespaceAnotherModuleDeclaresInsideExtension_whichThenFailsToCompile(integration: MultiModuleIntegration) async throws {
		// D2.5: `Base`, not `Core`, declares `Outer.Namespace`, and the check looks a namespace up only in the module of the
		// extension it bounds: in another module, a type of the name could be a namesake of the one the extension extends,
		// and of several the check would take the narrowest, so a namesake could fail a construction that compiles. The
		// compiler reports that `Namespace` is `package` in the generated file.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Base", packageName: "Shop", swiftFileContentByFilePath: ["Outer.swift": "public enum Outer {}\n\nextension Outer {\n    package enum Namespace {}\n}"]),
				ModuleFixture(
					name: "Core",
					packageName: "Shop",
					swiftFileContentByFilePath: ["Helper.swift": "import Base\n\n" + Self.helperSource(declaredInsideExtensionOf: "Outer.Namespace")],
					dependencies: ["Base"],
				),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContentByFilePath: ["Root.swift": "import Base\n" + Self.rootInstantiatingHelping], dependencies: ["Base", "Core"]),
			],
			integration: integration,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)
		let code = generatedFileHeader + Self.importBlock("Base") + "\n" + Self.importBlock("Core") + "\n\n" + Self.rootCode(constructing: "Outer.Namespace.Helper")
		#expect(output.modules["App"]?.generatedFiles == [integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": code])
		try expectModuleCompilationFails(output, module: "App", containing: "'Namespace' is inaccessible due to 'package' protection level")
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtInstantiableExtendedType_whenAnotherPackageConstructsTypeInExtensionOfPackageInstantiable(integration: MultiModuleIntegration) async {
		// D2.6: the extended type is `@Instantiable`, outside every extension, and its own declaration is what is read.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let outerPath = Self.declarationPath(of: "Outer.swift", in: "Core", fixtures: fixtures, under: integration)
			return """
			\(outerPath):2:1: error: `Outer`, which encloses `Outer.Helper`, is `package`, so module `App`, in another package, cannot construct `Outer.Helper` in the code SafeDI generates. Make `Outer` `public` to fix.
			\(outerPath):2:1-2:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesConstructingHelper(
					declaredInsideExtensionOf: "Outer",
					outerDeclaration: "@Instantiable\npackage final class Outer: Instantiable {\n    package init() {}\n}",
					namespaceFiles: [:],
					appPackage: "Other",
				),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtInstantiableNamespace_whenItIsDeclaredInsideExtensionAndAnotherPackageConstructsTypeInExtensionOfIt(integration: MultiModuleIntegration) async {
		// D2.11: the namespace inside an extension of `Outer` is `@Instantiable`, so the check reads its own declaration, and
		// then `Outer`'s, as it does a plain namespace's.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let namespacePath = Self.declarationPath(of: "Namespace.swift", in: "Core", fixtures: fixtures, under: integration)
			return """
			\(namespacePath):3:5: error: `Outer.Namespace`, which encloses `Outer.Namespace.Helper`, is `package`, so module `App`, in another package, cannot construct `Outer.Namespace.Helper` in the code SafeDI generates. Make `Outer.Namespace` `public` to fix.
			\(namespacePath):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesConstructingHelper(
					declaredInsideExtensionOf: "Outer.Namespace",
					namespaceFiles: ["Namespace.swift": "extension Outer {\n    @Instantiable\n    package final class Namespace: Instantiable {\n        package init() {}\n    }\n}"],
					appPackage: "Other",
				),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtPrivateExtension_whenNamespaceItDeclaresWithoutModifierEnclosesTypeAnotherPackageConstructs(integration: MultiModuleIntegration) async {
		// D2.7: `Namespace` spells no level, so it takes `fileprivate` from the `private` extension it is directly inside,
		// which is the declaration to widen.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let helperPath = Self.declarationPath(of: "Helper.swift", in: "Core", fixtures: fixtures, under: integration)
			return """
			\(helperPath):1:1: error: The extension that declares `Outer.Namespace`, which encloses `Outer.Namespace.Helper`, is `fileprivate`, so module `App`, in another package, cannot construct `Outer.Namespace.Helper` in the code SafeDI generates. Make the extension `public` to fix.
			\(helperPath):1:1-1:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesConstructingHelper(
					declaredInsideExtensionOf: "Outer.Namespace",
					namespaceFiles: [:],
					helperFilePrefix: "private extension Outer {\n    enum Namespace {}\n}\n\n",
					appPackage: "Other",
				),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingMock_whenMockInAnotherPackageConstructsTypeInExtensionOfPackageNamespaceDeclaredInsideExtension(integration: MultiModuleIntegration) async {
		// D2.8: the mock of `Screen` builds `Helper`, and names `Outer.Namespace` in `App`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let namespacePath = Self.declarationPath(of: "Namespace.swift", in: "Core", fixtures: fixtures, under: integration)
			return """
			\(namespacePath):2:5: error: `Outer.Namespace`, which encloses `Outer.Namespace.Helper`, is `package`, so the mock of `Screen`, generated in module `App`, in another package, cannot construct `Outer.Namespace.Helper` in the code SafeDI generates. Make `Outer.Namespace` `public` to fix.
			\(namespacePath):2:5-2:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesConstructingHelper(
					declaredInsideExtensionOf: "Outer.Namespace",
					namespaceFiles: ExtensionNamespaceChain.oneLink.namespaceFiles(),
					appPackage: "Other",
					appDeclaration: "import Core\n\n@Instantiable(generateMock: true)\npublic struct Screen: Instantiable {\n    public init(helping: any Helping) {\n        self.helping = helping\n    }\n\n    @Instantiated let helping: any Helping\n}",
				),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtNamespace_whenAnotherPackageCallsGeneratedInitializerOfSeamInExtensionOfPackageNamespaceDeclaredInsideExtension(integration: MultiModuleIntegration) async {
		// D2.9: `App` calls the initializer `Core` generates for the seam `Helper`, which names `Outer.Namespace`: the error
		// is at the namespace, never at the generated initializer, which is as visible as `Helper`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let namespacePath = Self.declarationPath(of: "Namespace.swift", in: "Core", fixtures: fixtures, under: integration)
			return """
			\(namespacePath):2:5: error: `Outer.Namespace`, which encloses `Outer.Namespace.Helper`, is `package`, so module `App`, in another package, cannot construct `Outer.Namespace.Helper` in the code SafeDI generates. Make `Outer.Namespace` `public` to fix.
			\(namespacePath):2:5-2:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesConstructingHelper(
					declaredInsideExtensionOf: "Outer.Namespace",
					namespaceFiles: ExtensionNamespaceChain.oneLink.namespaceFiles(),
					helperAttribute: "@Instantiable(generateDependencyTree: true, fulfillingAdditionalTypes: [Helping.self])",
					helperDependencies: ["@Instantiated let gear: Gear"],
					helperFilePrefix: "@Instantiable\npublic struct Gear: Instantiable {\n    public init() {}\n}\n\n",
					appPackage: "Other",
				),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtNarrowestClause_whenNamespaceInsideExtensionIsDeclaredInClausesOfPlatformConditionedBlock(integration: MultiModuleIntegration) async {
		// D2.10: the compiler may select either clause, so the check reads the narrower declaration of `Outer.Namespace`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let namespacePath = Self.declarationPath(of: "Namespace.swift", in: "Core", fixtures: fixtures, under: integration)
			return """
			\(namespacePath):3:5: error: `Outer.Namespace`, which encloses `Outer.Namespace.Helper`, is `package`, so module `App`, in another package, cannot construct `Outer.Namespace.Helper` in the code SafeDI generates. Make `Outer.Namespace` `public` to fix.
			\(namespacePath):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesConstructingHelper(
					declaredInsideExtensionOf: "Outer.Namespace",
					namespaceFiles: ["Namespace.swift": "extension Outer {\n#if os(Linux)\n    package enum Namespace {}\n#else\n    public enum Namespace {}\n#endif\n}"],
					appPackage: "Other",
				),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assertsDecisionSelectingNamespace_whenModuleOfItsPackageConstructsTypeInExtensionOfNamespaceDeclaredInsideExtensionInSelectedClause(integration: MultiModuleIntegration) async throws {
		// D2.10: `FLAG` selects the clause that declares `Outer.Namespace` `package`, which the construction relies on, so
		// the generated code asserts the decision, as it asserts any decision a read resolves by: `App`'s, which reads
		// `Core`'s files under the plugin, and `Core`'s, whose `.safedi` `App` reads under Bazel.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesConstructingHelper(
				declaredInsideExtensionOf: "Outer.Namespace",
				namespaceFiles: ["Namespace.swift": "extension Outer {\n#if FLAG\n    package enum Namespace {}\n#else\n    enum Namespace {}\n#endif\n}"],
				appPackage: "Shop",
				conditions: ["FLAG"],
			),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + Self.activeAssertion("FLAG")])
			#expect(output.modules["App"]?.generatedFiles == Self.rootFiles(under: integration, constructing: "Outer.Namespace.Helper"))
		case .swiftPackagePlugin:
			#expect(output.modules["App"]?.generatedFiles == Self.rootFiles(under: integration, constructing: "Outer.Namespace.Helper", assertions: ["FLAG"]))
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtMockGeneration_whenTypeWithPublicMockIsInExtensionOfPackageNamespaceDeclaredInsideExtension(integration: MultiModuleIntegration) async {
		// D2.12: a public mock of `Helper` names `Outer.Namespace` in its `public` signature, which the compiler rejects.
		await assertThrowsMultiModuleError(inModule: "Core", diagnostics: { fixtures in
			let helperPath = Self.declarationPath(of: "Helper.swift", in: "Core", fixtures: fixtures, under: integration)
			return """
			\(helperPath):4:76: error: `Outer.Namespace.Helper` cannot have a public mock because `Outer.Namespace` is `package`. Make `Outer.Namespace` `public`, or use `generateMock: .internal`.
			\(helperPath):4:76-4:83: fixit: .internal
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesConstructingHelper(
					declaredInsideExtensionOf: "Outer.Namespace",
					namespaceFiles: ExtensionNamespaceChain.oneLink.namespaceFiles(),
					helperAttribute: "@Instantiable(fulfillingAdditionalTypes: [Helping.self], generateMock: .public)",
					appPackage: "Other",
				),
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – Declarations a mention cannot name

	@Test(arguments: [
		(MultiModuleIntegration.moduleInfo, BrandThemeReach.moduleOfAnotherPackage),
		(.swiftPackagePlugin, .moduleOfAnotherPackage),
		(.swiftPackagePlugin, .moduleNotRead),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypeOnPublicTier_whenOnlyRecordedDeclarationOfExtendedTypesNameIsOneItsExtensionCannotName(integration: MultiModuleIntegration, brandTheme: BrandThemeReach) async throws {
		// `Styles` extends `Lib`'s `Theme`, which SafeDI does not read: `Brand`'s `package` `Theme` is one SafeDI knows `Styles`
		// cannot name – a module of another package, or, under the target graph, a module `Styles` does not depend on – so
		// it does not bound the type `Styles` declares.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.themeModules(brandTheme: brandTheme, stylesDeclaresTheme: false), integration: integration, filesToDelete: &filesToDelete)

		// Without a target graph, the file names the types it counts `public` because SafeDI reads no declaration of them.
		let comment = integration == .moduleInfo
			? "    // SafeDI counts `Theme` as `public`: no module it reads declares it narrower. If `Theme` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.\n"
			: ""
		#expect(output.modules["Feature"]?.generatedFiles == [integration == .moduleInfo ? "Feature.swift" : "Screen+SafeDI.swift": generatedFileHeader + """
		#if canImport(Lib)
		import Lib
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Screen {
		\(comment)    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public convenience init(__safeDI_theme theme: Theme) {
		        let cache = Cache()
		        self.init(theme: theme, cache: cache)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_DD923990A48765D6 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingDeclarationOfModuleItsRunDoesNotList_whenExtendingModuleMayImportThatModule() async {
		// Under module info, `Styles`' run lists no `Brand`, but SafeDI is not told that `Styles` cannot import it, so
		// `Brand`'s `package` `Theme` counts.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: \(Self.screenThemeFromBrandMessage)
			\(fixtures["Brand"]!["Theme.swift"]):1:1: note: `Theme` is declared `package` here.
			\(fixtures["Brand"]!["Theme.swift"]):1:1-1:8: fixit: public
			\(fixtures["Feature"]!["Screen.swift"]):10:5: note: `Screen` receives `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.themeModules(brandTheme: .moduleNotRead, stylesDeclaresTheme: false), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingImportedPackageType_whenExtendingModuleImportsModuleItsRunDoesNotList(integration: MultiModuleIntegration) async {
		// `Styles` lists only `Mid` and imports `Brand`, beneath it, whose `package` `Theme` it extends. Under module info SafeDI
		// is not told that `Styles` cannot import `Brand`; under the target graph `Brand` is among its dependencies.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			func path(of fileName: String, in moduleName: String) -> String {
				switch integration {
				case .moduleInfo:
					fixtures[moduleName]![fileName]
				case .swiftPackagePlugin:
					NormalizedFilePath(fixtures[moduleName]!.compilerPath(of: fileName)).path
				}
			}
			return """
			\(path(of: "Screen.swift", in: "Feature")):3:1: \(Self.screenThemeFromBrandMessage)
			\(path(of: "Theme.swift", in: "Brand")):1:1: note: `Theme` is declared `package` here.
			\(path(of: "Theme.swift", in: "Brand")):1:1-1:8: fixit: public
			\(path(of: "Screen.swift", in: "Feature")):10:5: note: `Screen` receives `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.underListedThemeModules(receivesThemeOnlyIfAvailable: false), integration: integration, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesImportedPackageTypeOnPackageTier_whenExtendingModuleImportsModuleItsRunDoesNotList(integration: MultiModuleIntegration) async throws {
		// As above, with `theme` received only if available: the `public` tier passes `nil` for it.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.underListedThemeModules(receivesThemeOnlyIfAvailable: true), integration: integration, filesToDelete: &filesToDelete)

		#expect(output.modules["Feature"]?.generatedFiles == [integration == .moduleInfo ? "Feature.swift" : "Screen+SafeDI.swift": generatedFileHeader + """
		#if canImport(Brand)
		import Brand
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Screen {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public convenience init() {
		        self.init(__safeDI_theme: nil)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    package convenience init(__safeDI_theme theme: Theme?) {
		        let cache = Cache()
		        self.init(theme: theme, cache: cache)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_27F6F01DC5D0EF8E {}
		}
		"""])
	}

	@Test(arguments: MultiModuleIntegration.allCases, [["Lib", "ModA"], ["ModA", "Lib"]])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesUnreadTypeOnPublicTier_whenOnlyInstantiableDeclarationOfItsNameIsPackageTypeOfAnotherPackage(integration: MultiModuleIntegration, readOrder: [String]) async throws {
		// `Feature` cannot name `ModA`'s `package` `Store`, of another package, so its seam's `Store` is `Lib`'s, which SafeDI
		// does not read.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.storeReceivingModules(featureDependencies: readOrder, receivesStoreOnlyIfAvailable: false), integration: integration, filesToDelete: &filesToDelete)

		#expect(output.modules["Feature"]?.generatedFiles == [integration == .moduleInfo ? "Feature.swift" : "SeamF+SafeDI.swift": generatedFileHeader + """
		#if canImport(Lib)
		import Lib
		#endif

		extension SeamF {
		\(Self.unreadStoreComment(integration: integration))    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public convenience init(__safeDI_store store: Store) {
		        let inner = Inner(store: store)
		        self.init(store: store, inner: inner)
		    }
		}

		extension SeamF {
		    public enum __safeDI_SeamF_19911CF36F34982A {}
		}
		"""])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesForwardedValueToPublicTier_whenSeamReceivesUnreadTypeOnlyIfAvailableBesidePackageInstantiableOfItsName(integration: MultiModuleIntegration) async throws {
		// The `public` tier takes `store`, which `App` forwards.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.storeReceivingModules(featureDependencies: ["Lib", "ModA"], receivesStoreOnlyIfAvailable: true), integration: integration, filesToDelete: &filesToDelete)

		#expect(output.modules["Feature"]?.generatedFiles == [integration == .moduleInfo ? "Feature.swift" : "SeamF+SafeDI.swift": generatedFileHeader + """
		#if canImport(Lib)
		import Lib
		#endif

		extension SeamF {
		\(Self.unreadStoreComment(integration: integration))    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public convenience init(__safeDI_store store: Store?) {
		        let inner = Inner()
		        self.init(store: store, inner: inner)
		    }
		}

		extension SeamF {
		    public enum __safeDI_SeamF_733E17E62B7A3AC5 {}
		}
		"""])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesTypeOnPublicTier_whenItsExtendedTypesOnlyInstantiableDeclarationIsPackageTypeOfAnotherPackage(integration: MultiModuleIntegration) async throws {
		// `Feature` extends `Lib`'s `Outer`: `ModA`'s `package` `Outer`, of another package, does not bound `Outer.Inner`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Lib", packageName: "ThirdParty", swiftFileContentByFilePath: ["Outer.swift": "public enum Outer {}"], isCheckoutPackage: true, runsSafeDI: false),
				ModuleFixture(name: "ModA", packageName: "PackageA", swiftFileContentByFilePath: ["Outer.swift": "@Instantiable\npackage struct Outer: Instantiable {\n    package init() {}\n}"]),
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContentByFilePath: [
						"Inner.swift": "import Lib\n\nextension Outer {\n    @Instantiable\n    public struct Inner: Instantiable {\n        public init() {}\n    }\n}",
						"Screen.swift": """
						import Lib

						@Instantiable(generateDependencyTree: true)
						public final class Screen: Instantiable {
						    init(inner: Outer.Inner, cache: Cache) {
						        self.inner = inner
						        self.cache = cache
						    }

						    @Received let inner: Outer.Inner
						    @Instantiated let cache: Cache
						}

						@Instantiable
						struct Cache: Instantiable {
						    init() {}
						}
						""",
						"UsesModA.swift": "import ModA\n\nenum UsesModA {}",
					],
					dependencies: ["Lib", "ModA"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let comment = integration == .moduleInfo
			? "    // SafeDI counts `Outer` as `public`: no module it reads declares it narrower. If `Outer` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.\n"
			: ""
		#expect(output.modules["Feature"]?.generatedFiles == [integration == .moduleInfo ? "Feature.swift" : "Screen+SafeDI.swift": generatedFileHeader + """
		#if canImport(Lib)
		import Lib
		#endif

		extension Screen {
		\(comment)    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public convenience init(__safeDI_inner inner: Outer.Inner) {
		        let cache = Cache()
		        self.init(inner: inner, cache: cache)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_ECD4BD415105F519 {}
		}
		"""])
	}

	@Test(arguments: MultiModuleIntegration.allCases, BrandThemeReach.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingExtendingModulesDeclaration_whenExtendingModuleDeclaresTypeBesideDeclarationOfItsNameItCannotName(integration: MultiModuleIntegration, brandTheme: BrandThemeReach) async {
		// `Styles`' own `package` `Theme` bounds the type its extension declares, which `Screen`'s `public` tier cannot take.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			func path(of fileName: String, in moduleName: String) -> String {
				switch integration {
				case .moduleInfo:
					fixtures[moduleName]![fileName]
				case .swiftPackagePlugin:
					NormalizedFilePath(fixtures[moduleName]!.compilerPath(of: fileName)).path
				}
			}
			return """
			\(path(of: "Screen.swift", in: "Feature")):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `theme: Theme`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Theme` is declared `package` in module `Styles`. Declare `Theme` `public` in module `Styles`; declare `Screen` `package`; receive `theme` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(path(of: "ThemeInstantiable.swift", in: "Styles")):3:1: note: `Theme` is declared `package` here.
			\(path(of: "ThemeInstantiable.swift", in: "Styles")):3:1-3:8: fixit: public
			\(path(of: "Screen.swift", in: "Feature")):10:5: note: `Screen` receives `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.themeModules(brandTheme: brandTheme, stylesDeclaresTheme: true), integration: integration, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Why `Styles` cannot name `Brand`'s `package` `Theme`.
	enum BrandThemeReach: CaseIterable, CustomTestStringConvertible, Sendable {
		/// `Styles` does not read `Brand`, a module of its package.
		case moduleNotRead
		/// `Styles` reads `Brand`, a module of another package.
		case moduleOfAnotherPackage

		var testDescription: String {
			"\(self)"
		}
	}

	/// `Lib`, a package SwiftPM fetched, which declares a `public` `Theme` SafeDI does not read; `Brand`, which declares a
	/// `package` `Theme` that `Styles` cannot name, as `brandTheme` says; `Styles`, which declares `Theme` `@Instantiable`
	/// by an extension, of `Lib`'s `Theme`, or of its own `package` one when `stylesDeclaresTheme`; and `Feature`, of
	/// `Styles`' package, which reads `Brand` too, whose seam `Screen` receives the `Theme` `Styles` declares.
	private static func themeModules(brandTheme: BrandThemeReach, stylesDeclaresTheme: Bool) -> [ModuleFixture] {
		let themeInstantiable = stylesDeclaresTheme
			? """
			import SafeDI

			package struct Theme {
			    package init() {}
			}

			@Instantiable
			extension Theme: Instantiable {
			    package static func instantiate() -> Theme {
			        Theme()
			    }
			}
			"""
			: """
			import Lib
			import SafeDI

			@Instantiable(conformsElsewhere: true)
			extension Theme {
			    public static func instantiate() -> Theme {
			        Theme()
			    }
			}

			extension Theme: @retroactive Instantiable {}
			"""
		let stylesDependencies = switch brandTheme {
		case .moduleNotRead:
			["Lib"]
		case .moduleOfAnotherPackage:
			["Lib", "Brand"]
		}
		return [
			ModuleFixture(name: "Lib", packageName: "ThirdParty", swiftFileContentByFilePath: ["Theme.swift": "public struct Theme {\n    public init() {}\n}"], isCheckoutPackage: true, runsSafeDI: false),
			ModuleFixture(
				name: "Brand",
				packageName: brandTheme == .moduleNotRead ? "Shop" : "Other",
				swiftFileContentByFilePath: [
					"Theme.swift": "package struct Theme {\n    package init() {}\n}",
					"Palette.swift": "@Instantiable\npublic struct Palette: Instantiable {\n    public init() {}\n}",
				],
			),
			ModuleFixture(name: "Styles", packageName: "Shop", swiftFileContentByFilePath: ["ThemeInstantiable.swift": themeInstantiable], dependencies: stylesDependencies),
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContentByFilePath: [
					"Screen.swift": """
					\(stylesDeclaresTheme ? "import Styles" : "import Lib")

					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    init(theme: Theme, cache: Cache) {
					        self.theme = theme
					        self.cache = cache
					    }

					    @Received let theme: Theme
					    @Instantiated let cache: Cache
					}

					@Instantiable
					struct Cache: Instantiable {
					    init() {}
					}
					""",
					"UsesBrand.swift": "import Brand\n\nenum UsesBrand {}",
				],
				dependencies: ["Lib", "Brand", "Styles"],
			),
		]
	}

	/// The error at `Screen` when the `Theme` it receives is `Brand`'s `package` one.
	private static let screenThemeFromBrandMessage = "error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `theme: Theme`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `Theme` is declared `package` in module `Brand`. Declare `Theme` `public` in module `Brand`; declare `Screen` `package`; receive `theme` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`."

	/// `Brand`, which declares a `package` `Theme`; `Mid`, which depends on `Brand`; `Styles`, which lists only `Mid`,
	/// imports `Brand`, and declares `Brand`'s `Theme` `@Instantiable` by an extension; and `Feature`, which lists `Brand`
	/// and `Styles`, whose seam `Screen` receives `Theme`, only if available when `receivesThemeOnlyIfAvailable`. Every
	/// module is in package `Shop`.
	private static func underListedThemeModules(receivesThemeOnlyIfAvailable: Bool) -> [ModuleFixture] {
		let themeType = receivesThemeOnlyIfAvailable ? "Theme?" : "Theme"
		return [
			ModuleFixture(
				name: "Brand",
				packageName: "Shop",
				swiftFileContentByFilePath: [
					"Theme.swift": "package struct Theme {\n    package init() {}\n}",
					"Palette.swift": "@Instantiable\npublic struct Palette: Instantiable {\n    public init() {}\n}",
				],
			),
			ModuleFixture(name: "Mid", packageName: "Shop", swiftFileContentByFilePath: ["Mid.swift": "import Brand\n\npublic enum Mid {}"], dependencies: ["Brand"]),
			ModuleFixture(
				name: "Styles",
				packageName: "Shop",
				swiftFileContentByFilePath: [
					"ThemeInstantiable.swift": """
					import Brand
					import SafeDI

					@Instantiable
					extension Theme: Instantiable {
					    package static func instantiate() -> Theme {
					        Theme()
					    }
					}
					""",
				],
				dependencies: ["Mid"],
			),
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContentByFilePath: [
					"Screen.swift": """
					import Brand

					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    init(theme: \(themeType), cache: Cache) {
					        self.theme = theme
					        self.cache = cache
					    }

					    @Received\(receivesThemeOnlyIfAvailable ? "(onlyIfAvailable: true)" : "") let theme: \(themeType)
					    @Instantiated let cache: Cache
					}

					@Instantiable
					struct Cache: Instantiable {
					    init() {}
					}
					""",
				],
				dependencies: ["Brand", "Styles"],
			),
		]
	}

	/// `Lib`, a package SwiftPM fetched, which declares a `public` `Store` SafeDI does not read; `ModA`, of package
	/// `PackageA`, which declares an `@Instantiable` `package` `Store` and a seam that holds it; `Feature`, of package
	/// `Shop`, which lists `featureDependencies`, and whose seam `SeamF` receives `Lib`'s `Store`, only if available when
	/// `receivesStoreOnlyIfAvailable`, in a file that imports only `Lib`; and `App`, whose `Holder` forwards `Store` and
	/// instantiates `SeamF`.
	private static func storeReceivingModules(featureDependencies: [String], receivesStoreOnlyIfAvailable: Bool) -> [ModuleFixture] {
		let storeType = receivesStoreOnlyIfAvailable ? "Store?" : "Store"
		let inner = receivesStoreOnlyIfAvailable
			? "@Instantiable\nstruct Inner: Instantiable {\n    init() {}\n}"
			: """
			import Lib

			@Instantiable
			struct Inner: Instantiable {
			    init(store: Store) { self.store = store }
			    @Received let store: Store
			}
			"""
		return [
			ModuleFixture(name: "Lib", packageName: "ThirdParty", swiftFileContentByFilePath: ["Store.swift": "public struct Store {\n    public init() {}\n}"], isCheckoutPackage: true, runsSafeDI: false),
			ModuleFixture(
				name: "ModA",
				packageName: "PackageA",
				swiftFileContentByFilePath: [
					"Store.swift": "@Instantiable\npackage struct Store: Instantiable {\n    package init() {}\n}",
					"SeamA.swift": "@Instantiable(generateDependencyTree: true)\npublic final class SeamA: Instantiable {\n    init(store: Store) { self.store = store }\n    @Instantiated let store: Store\n}",
				],
			),
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContentByFilePath: [
					"SeamF.swift": """
					import Lib

					@Instantiable(generateDependencyTree: true)
					public final class SeamF: Instantiable {
					    init(store: \(storeType), inner: Inner) {
					        self.store = store
					        self.inner = inner
					    }

					    @Received\(receivesStoreOnlyIfAvailable ? "(onlyIfAvailable: true)" : "") public let store: \(storeType)
					    @Instantiated let inner: Inner
					}
					""",
					"Inner.swift": inner,
					"UsesModA.swift": "import ModA\n\nenum UsesModA {}",
				],
				dependencies: featureDependencies,
			),
			ModuleFixture(
				name: "App",
				packageName: "AppPackage",
				swiftFileContentByFilePath: [
					"Holder.swift": """
					import Feature
					import Lib

					@Instantiable
					public struct Holder: Instantiable {
					    public init(store: Store, seamF: SeamF) {
					        self.store = store
					        self.seamF = seamF
					    }

					    @Forwarded let store: Store
					    @Instantiated let seamF: SeamF
					}
					""",
					"Root.swift": """
					import Feature
					import ModA

					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(seamA: SeamA, makeHolder: Instantiator<Holder>) {
					        self.seamA = seamA
					        self.makeHolder = makeHolder
					    }

					    @Instantiated let seamA: SeamA
					    @Instantiated let makeHolder: Instantiator<Holder>
					}
					""",
				],
				dependencies: ["Lib", "ModA", "Feature"],
			),
		]
	}

	/// The comment, under module info, that names `Store` as a type SafeDI counts `public` unread.
	private static func unreadStoreComment(integration: MultiModuleIntegration) -> String {
		integration == .moduleInfo
			? "    // SafeDI counts `Store` as `public`: no module it reads declares it narrower. If `Store` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.\n"
			: ""
	}

	/// `Core`, in package `Shop`, whose `Outer.swift` holds `outerDeclaration`, whose `namespaceFiles` declare namespaces
	/// inside extensions, each in a file without a SafeDI marker, and whose `Helper.swift` holds `helperFilePrefix` and then
	/// `Helper` (`helperSource(declaredInsideExtensionOf:attribute:dependencies:)`); and `App`, in `appPackage`, whose
	/// `Root.swift` holds `appDeclaration`: by default a root that instantiates `any Helping`, so that only the code SafeDI
	/// generates in `App` names `Helper` and the namespaces enclosing it. Both run with `conditions`.
	private static func modulesConstructingHelper(
		declaredInsideExtensionOf extendedType: String,
		outerDeclaration: String = "public enum Outer {}",
		namespaceFiles: [String: String],
		helperAttribute: String = "@Instantiable(fulfillingAdditionalTypes: [Helping.self])",
		helperDependencies: [String] = [],
		helperFilePrefix: String = "",
		appPackage: String,
		appDeclaration: String = rootInstantiatingHelping,
		conditions: [String] = [],
		deletesCoreFiles: Bool = false,
		omitsPackageNames: Bool = false,
	) -> [ModuleFixture] {
		let helperFile: String = helperFilePrefix + helperSource(declaredInsideExtensionOf: extendedType, attribute: helperAttribute, dependencies: helperDependencies)
		let coreFiles: [String: String] = ["Outer.swift": outerDeclaration, "Helper.swift": helperFile].merging(namespaceFiles, uniquingKeysWith: { first, _ in first })
		return [
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: coreFiles, activeCompilationConditions: conditions, deletesSwiftFilesAfterRunning: deletesCoreFiles, omitsPackageName: omitsPackageNames),
			ModuleFixture(name: "App", packageName: appPackage, swiftFileContentByFilePath: ["Root.swift": appDeclaration], dependencies: ["Core"], activeCompilationConditions: conditions, omitsPackageName: omitsPackageNames),
		]
	}

	/// The public `Helping` and, inside an unspelled extension of `extendedType`, the public final class `Helper`,
	/// declared with `attribute`, which fulfills `Helping` and declares `dependencies`, each an `@Instantiated` property its
	/// `public` initializer takes.
	private static func helperSource(
		declaredInsideExtensionOf extendedType: String,
		attribute: String = "@Instantiable(fulfillingAdditionalTypes: [Helping.self])",
		dependencies: [String] = [],
	) -> String {
		let properties = dependencies.map { dependency in
			let property = dependency[dependency.range(of: " let ")!.upperBound...]
			return (label: String(property.prefix { $0 != ":" }), type: property.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces))
		}
		let initializer: String = properties.isEmpty
			? "        public init() {}"
			: "        public init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {\n"
			+ properties.map { "            self.\($0.label) = \($0.label)" }.joined(separator: "\n")
			+ "\n        }\n\n"
			+ dependencies.map { "        \($0)" }.joined(separator: "\n")
		return "public protocol Helping {}\n\nextension \(extendedType) {\n    \(attribute)\n    public final class Helper: Instantiable, Helping {\n\(initializer)\n    }\n}"
	}

	/// `App`'s root, which instantiates `any Helping` at line 9 of its file.
	private static let rootInstantiatingHelping = """
	import Core

	@Instantiable(isRoot: true)
	public struct Root: Instantiable {
	    public init(helping: any Helping) {
	        self.helping = helping
	    }

	    @Instantiated let helping: any Helping
	}
	"""

	/// The code `App` generates for `rootInstantiatingHelping` when `Helping` is fulfilled by `helperType`.
	private static func rootCode(constructing helperType: String) -> String {
		"""
		extension Root {
		    public init() {
		        let helping: any Helping = \(helperType)()
		        self.init(helping: helping)
		    }
		}
		"""
	}

	/// The files `App` generates under `integration` for `rootInstantiatingHelping` when `Helping` is fulfilled by
	/// `helperType`, asserting that each of `assertions` is active.
	private static func rootFiles(under integration: MultiModuleIntegration, constructing helperType: String, assertions: [String] = []) -> [String: String] {
		let code = generatedFileHeader + importBlock("Core") + "\n\n" + assertions.map(activeAssertion).joined() + rootCode(constructing: helperType)
		return [integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": code]
	}

	/// The compile-time assertion a generated file carries for a `#if <condition>` the tool evaluated as active, ending
	/// with the blank line that precedes what follows.
	private static func activeAssertion(_ condition: String) -> String {
		"""
		#if !(\(condition))
		#error("SafeDI scanned this module assuming `#if \(condition)` was active, but it is inactive in this compilation. Report the conditions this target compiles with to SafeDITool, as the \\"Reporting active conditions\\" section of the SafeDI manual describes for your build system.")
		#endif

		""" + "\n"
	}

	/// Expects every module before `module` to compile, and `module`'s generated code to fail to compile alongside its
	/// inputs with an error containing `text`.
	private func expectModuleCompilationFails(_ output: MultiModuleTestOutput, module: String, containing text: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		let failure = try #require(compilation.failure, sourceLocation: sourceLocation)
		#expect(failure.moduleName == module, sourceLocation: sourceLocation)
		#expect(compilation.modules.dropLast().allSatisfy { $0.failure == nil }, sourceLocation: sourceLocation)
		switch failure.failure {
		case .generatedCodeFailedAlongsideInputs:
			break
		case .inputsFailedOnTheirOwn, nil:
			Issue.record("Expected \(module)'s generated code to fail to compile, but its failure is \(String(describing: failure.failure)).", sourceLocation: sourceLocation)
		}
		#expect(failure.standardError.contains(text), "Unexpected compiler output \(failure.standardError)", sourceLocation: sourceLocation)
	}

	/// `Core`, whose `Space.swift` is `space` and whose `Shelf.swift` declares `Space.Shelf` inside an extension of
	/// `Space`, fulfilling `Storage`, and `App`, in another package, whose root instantiates `Storage`; both run with
	/// `conditions`.
	private static func shelfInSpaceModules(space: String, conditions: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: [
				"Space.swift": space,
				"Shelf.swift": "public protocol Storage {}\n\nextension Space {\n    @Instantiable(fulfillingAdditionalTypes: [Storage.self])\n    public final class Shelf: Instantiable, Storage {\n        public init() {}\n    }\n}",
			], activeCompilationConditions: conditions),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Core\n\n@Instantiable(isRoot: true)\npublic struct Root: Instantiable {\n    public init(storage: any Storage) {\n        self.storage = storage\n    }\n\n    @Instantiated let storage: any Storage\n}"], dependencies: ["Core"], activeCompilationConditions: conditions),
		]
	}

	/// An `internal` `Service` with a `package` initializer, so that only the type keeps another module from
	/// constructing it.
	private static let internalServiceWithPackageInitializer = """
	@Instantiable
	final class Service: Instantiable {
	    package init() {}
	}
	"""

	/// An `App` module of package `Shop` depending on `Feature`, with a file at each path of `typeNameByFilePath` that
	/// declares the type it names, decorated with `attribute`, which instantiates `Feature`'s `Service` at line 8.
	private static func appInstantiatingService(in typeNameByFilePath: [String: String], decoratedWith attribute: String) -> ModuleFixture {
		ModuleFixture(
			name: "App",
			packageName: "Shop",
			swiftFileContentByFilePath: typeNameByFilePath.mapValues { typeName in
				"""
				import Feature

				\(attribute)
				final class \(typeName): Instantiable {
				    init(service: Service) {
				        self.service = service
				    }
				    @Instantiated let service: Service
				}
				"""
			},
			dependencies: ["Feature"],
		)
	}

	/// A `Feature` module of package `Shop` whose `internal` enum `Namespace`, at the start of `Namespace.swift`,
	/// declares a public type for each of `typeNames`, in order.
	private static func featureDeclaringNamespace(enclosing typeNames: [String], deletesSwiftFilesAfterRunning: Bool) -> ModuleFixture {
		let typeDeclarations = typeNames.map { typeName in
			"""
			    @Instantiable
			    public final class \(typeName): Instantiable {
			        public init() {}
			    }
			"""
		}
		return ModuleFixture(
			name: "Feature",
			packageName: "Shop",
			swiftFileContentByFilePath: [
				"Namespace.swift": "enum Namespace {\n" + typeDeclarations.joined(separator: "\n\n") + "\n}",
			],
			deletesSwiftFilesAfterRunning: deletesSwiftFilesAfterRunning,
		)
	}

	/// A root in `App` that refers to `Namespace.Alpha` and then to `Namespace.Zulu`, at lines 10 and 11.
	private static let rootReferringToAlphaThenZulu = """
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
	"""

	/// A `public` `User` whose hand-written mock is `package`.
	private static let publicUserWithPackageMock = """
	@Instantiable
	public final class User: Instantiable {
	    public init() {}
	    package static func mock() -> User { User() }
	}
	"""

	/// What an error about a production construction adds when declaring `typeName`, which `moduleName` declares,
	/// with `generateDependencyTree: true` would have that module construct the declaration instead.
	private static func seamRemedy(declaring typeName: String, in moduleName: String) -> String {
		", or declare `\(typeName)` with `generateDependencyTree: true`, so that module `\(moduleName)` generates its tree and this module calls the initializer it generates"
	}

	/// A `Feature` module of package `FeaturePackage` whose `public` `Gate`, at the start of `Gate.swift`, has a
	/// `package` initializer and is instantiated by `Service`, and by `Seam`, which is declared with
	/// `generateDependencyTree: true`.
	private static let featureDeclaringGateBuiltByServiceAndSeam = ModuleFixture(
		name: "Feature",
		packageName: "FeaturePackage",
		swiftFileContent: [
			"""
			@Instantiable
			public final class Gate: Instantiable {
			    package init() {}
			}

			@Instantiable
			public final class Service: Instantiable {
			    public init(gate: Gate) {
			        self.gate = gate
			    }

			    @Instantiated public let gate: Gate
			}

			@Instantiable(generateDependencyTree: true)
			public final class Seam: Instantiable {
			    public init(gate: Gate) {
			        self.gate = gate
			    }

			    @Instantiated public let gate: Gate
			}
			""",
		],
	)

	/// An `App` module of package `AppPackage` depending on `featureDeclaringGateBuiltByServiceAndSeam`, with a file for
	/// each type `attributeByTypeName` names, decorated with its attribute, which instantiates `Service` and `Seam`.
	private static func appInstantiatingServiceAndSeam(in attributeByTypeName: [String: String]) -> ModuleFixture {
		ModuleFixture(
			name: "App",
			packageName: "AppPackage",
			swiftFileContentByFilePath: Dictionary(uniqueKeysWithValues: attributeByTypeName.map { typeName, attribute in
				(
					"\(typeName).swift",
					"""
					import Feature

					\(attribute)
					public final class \(typeName): Instantiable {
					    public init(service: Service, seam: Seam) {
					        self.service = service
					        self.seam = seam
					    }

					    @Instantiated public let service: Service
					    @Instantiated public let seam: Seam
					}
					""",
				)
			}),
			dependencies: ["Feature"],
		)
	}

	/// The modules of package `Shop` that a target the Xcode project plugin builds sees, which SafeDI cannot name:
	/// `Core`, which declares `packageNetworkClient`, `Feature`, which declares `featureViewFile(formatterDeclaration:)`,
	/// and `App`, which declares `rootReferringToFeatureView`.
	private static func modulesOfTargetReachingFeatureView(formatterDeclaration: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: [packageNetworkClient]),
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContentByFilePath: ["FeatureView.swift": featureViewFile(formatterDeclaration: formatterDeclaration)],
				dependencies: ["Core"],
			),
			ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Root.swift": rootReferringToFeatureView], dependencies: ["Feature"]),
		]
	}

	/// A `package` `NetworkClient`.
	private static let packageNetworkClient = """
	@Instantiable
	package final class NetworkClient: Instantiable {
	    package init() {}
	}
	"""

	/// `FeatureView.swift`: `FeatureView`, declared with `generateDependencyTree: true`, with an `internal` initializer at
	/// line 5, which instantiates a `NetworkClient` and the `Formatter` that `formatterDeclaration` declares at line 15.
	private static func featureViewFile(formatterDeclaration: String) -> String {
		"""
		import Core

		@Instantiable(generateDependencyTree: true)
		package struct FeatureView: Instantiable {
		    init(networkClient: NetworkClient, formatter: Formatter) {
		        self.networkClient = networkClient
		        self.formatter = formatter
		    }

		    @Instantiated let networkClient: NetworkClient
		    @Instantiated let formatter: Formatter
		}

		@Instantiable
		\(formatterDeclaration)
		"""
	}

	/// An `internal` `Formatter`, for `featureViewFile(formatterDeclaration:)`.
	private static let internalFormatter = """
	struct Formatter: Instantiable {
	    init() {}
	}
	"""

	/// A root that instantiates `FeatureView` at line 9.
	private static let rootReferringToFeatureView = """
	import Feature

	@Instantiable(isRoot: true)
	struct Root: Instantiable {
	    init(featureView: FeatureView) {
	        self.featureView = featureView
	    }

	    @Instantiated let featureView: FeatureView
	}
	"""

	/// The error a target that names no module gets where it refers to `FeatureView`, whose tree it builds inline,
	/// which says that `reachedDeclaration`, the first declaration in source order in the tree that the target cannot
	/// reach, keeps the tree from compiling, and leads with the remedy every build can apply.
	private static func inlineSeamMessage(reaching reachedDeclaration: String) -> String {
		"`FeatureView` is declared with `generateDependencyTree: true`, but SafeDI does not know which module declares `FeatureView`, so this run builds `FeatureView`’s tree inline. \(reachedDeclaration), so that tree cannot be built here. Make the types in `FeatureView`’s tree and their initializers `package`, which needs both modules compiled with one package name (`SWIFT_PACKAGE_NAME` in an Xcode project), or `public` where their module and this one are in different packages. For this module to call the initializer SafeDI generates for `FeatureView` instead, SafeDI must know `FeatureView`’s module. Under the Xcode project plugin, which cannot name modules, move the modules and the root into a local Swift package that the app target depends on. In a SafeDITool run by hand, list the `.safedi` file of `FeatureView`’s module, written with `--module-name` and `--module-info-output`, in the file you pass to `--dependent-module-info-file-path`."
	}

	/// `Core`, in its own package, declaring with `serviceAttribute` the `public` `Service`, whose `package` initializer
	/// takes `analytics` and `session`, which it receives, and the `package` `TokenCache`, which it instantiates; and the
	/// `public` `Analytics` and `Session`. `TokenCache` receives `session` too when `tokenCacheReceivesSession` is set.
	private static func coreDeclaringServiceBuildingTokenCache(serviceAttribute: String, tokenCacheReceivesSession: Bool) -> ModuleFixture {
		let tokenCache = tokenCacheReceivesSession
			? """
			@Instantiable
			package struct TokenCache: Instantiable {
			    package init(session: Session, capacity: Int = 10) {
			        self.session = session
			        self.capacity = capacity
			    }

			    @Received let session: Session
			    let capacity: Int
			}
			"""
			: """
			@Instantiable
			package struct TokenCache: Instantiable {
			    package init(capacity: Int = 10) { self.capacity = capacity }
			    let capacity: Int
			}
			"""
		return ModuleFixture(
			name: "Core",
			packageName: "CorePackage",
			swiftFileContent: [
				"""
				\(serviceAttribute)
				public struct Service: Instantiable {
				    package init(analytics: LazilyInstantiated<Analytics>, session: Session, tokenCache: TokenCache, retries: Int = 3) {
				        self.analytics = analytics
				        self.session = session
				        self.tokenCache = tokenCache
				        self.retries = retries
				    }

				    @Received private let analytics: LazilyInstantiated<Analytics>
				    @Received private let session: Session
				    @Instantiated private let tokenCache: TokenCache
				    private let retries: Int
				}

				@Instantiable
				public final class Analytics: Instantiable {
				    public init() {}
				}

				@Instantiable
				public final class Session: Instantiable {
				    public init() {}
				}

				\(tokenCache)
				""",
			],
		)
	}

	/// `App`, in another package, whose root instantiates `analytics` and `session` and `Screen`, declared with
	/// `screenAttribute`, which receives both and instantiates `Core`'s `Service`.
	private static func appBuildingServiceThroughScreen(screenAttribute: String) -> ModuleFixture {
		ModuleFixture(
			name: "App",
			packageName: "AppPackage",
			swiftFileContent: [
				"""
				import Core

				@Instantiable(isRoot: true)
				struct AppRoot: Instantiable {
				    init(analytics: LazilyInstantiated<Analytics>, session: Session, screen: Screen) {
				        self.session = session
				        self.analytics = analytics
				        self.screen = screen
				    }

				    @Instantiated let analytics: LazilyInstantiated<Analytics>
				    @Instantiated let session: Session
				    @Instantiated let screen: Screen
				}

				\(screenAttribute)
				struct Screen: Instantiable {
				    init(analytics: LazilyInstantiated<Analytics>, session: Session, service: Service) {
				        self.session = session
				        self.analytics = analytics
				        self.service = service
				    }

				    @Received let analytics: LazilyInstantiated<Analytics>
				    @Received let session: Session
				    @Instantiated let service: Service
				}
				""",
			],
			dependencies: ["Core"],
		)
	}

	/// `Base`, in package `basePackageName`, whose `Formatter.swift` declares `Formatter` with a `package` initializer as
	/// `construction` says; the modules `reach` puts between `Base` and `Core`; `Core`, in package `Toolkit`, whose
	/// `Service.swift` declares, with `serviceAttribute`, the `public` `Service`, which builds `Formatter` as
	/// `construction` says and reaches `Base` as `reach` says; and `App`, in package `Shop`, which depends on each of them
	/// and whose root instantiates `Service`.
	private static func modulesBuildingFormatterThroughService(
		reach: ThirdModuleReach,
		construction: FormatterConstruction = .constant,
		basePackageName: String = "Toolkit",
		serviceAttribute: String,
	) -> [ModuleFixture] {
		let base = ModuleFixture(name: "Base", packageName: basePackageName, swiftFileContentByFilePath: ["Formatter.swift": construction.baseFile])
		let service = TokenCacheConstruction.type(declaredAs: "\(serviceAttribute)\npublic final class Service", initializerModifier: "public ", instantiating: [construction.serviceProperty], importing: nil)
		let core = ModuleFixture(
			name: "Core",
			packageName: "Toolkit",
			swiftFileContentByFilePath: ["Service.swift": ([reach.coreImports, service] + [construction.otherCoreDeclarations].compactMap(\.self)).joined(separator: "\n\n")],
			dependencies: reach.coreDependencies,
		)
		let modules = [base] + reach.intermediateModules + [core]
		return modules + [rootInstantiatingService(dependencies: modules.map(\.name))]
	}

	/// `Feature`, in package `Kit`, whose `Service.swift` declares `UserService`, `Cache`, with a `package` initializer at
	/// line 5, and `Service`, which instantiates an `any UserService`; `FeatureImpl`, in `Kit` too and depending on
	/// `Feature`, whose `DefaultUserService` fulfills `UserService` and instantiates `Cache`; and `App`, in package
	/// `Shop`, whose root instantiates `Service`. Each type `seams` names is declared with
	/// `generateDependencyTree: true`. `App` depends on `FeatureImpl`, or, when
	/// `appReadsImplementationThroughAdditionalDirectory` is set, reads its directory through
	/// `additionalDirectoriesToInclude`, which leaves the module that declares `DefaultUserService` unknown.
	private static func modulesFillingServiceWithImplementationBuildingCache(seams: Set<String>, appReadsImplementationThroughAdditionalDirectory: Bool = false) -> [ModuleFixture] {
		func attribute(of typeName: String, arguments: [String] = []) -> String {
			// Appended rather than joined with `+` around a ternary: Swift 6.2 on Linux can time out type-checking a `+`
			// of arrays with a ternary; later Swift does not.
			var allArguments = [String]()
			if seams.contains(typeName) {
				allArguments.append("generateDependencyTree: true")
			}
			allArguments += arguments
			return allArguments.isEmpty ? "@Instantiable" : "@Instantiable(\(allArguments.joined(separator: ", ")))"
		}
		// Chosen in statements of their own rather than by ternaries around `+` chains in the fixtures below: Swift 6.2
		// on Linux can time out type-checking such an expression; later Swift does not.
		let appFiles: [String: String]
		let appDependencies: [String]
		if appReadsImplementationThroughAdditionalDirectory {
			appFiles = [
				"Root.swift": TokenCacheConstruction.type(declaredAs: "@Instantiable(isRoot: true)\nfinal class Root", initializerModifier: "", instantiating: ["service: Service"], importing: "Feature"),
				"SafeDIConfiguration.swift": "#SafeDIConfiguration(additionalDirectoriesToInclude: [\"$FIXTURE_ROOT/Kit/Sources/FeatureImpl\"])\n",
			]
			appDependencies = ["Feature"]
		} else {
			appFiles = [
				"Root.swift": "import Feature\n" + TokenCacheConstruction.type(declaredAs: "@Instantiable(isRoot: true)\nfinal class Root", initializerModifier: "", instantiating: ["service: Service"], importing: "FeatureImpl"),
			]
			appDependencies = ["Feature", "FeatureImpl"]
		}
		return [
			ModuleFixture(
				name: "Feature",
				packageName: "Kit",
				swiftFileContentByFilePath: [
					"Service.swift": """
					public protocol UserService: AnyObject {}

					@Instantiable
					public final class Cache: Instantiable {
					    package init() {}
					}


					""" + TokenCacheConstruction.type(declaredAs: "\(attribute(of: "Service"))\npublic final class Service", initializerModifier: "public ", instantiating: ["userService: any UserService"], importing: nil),
				],
			),
			ModuleFixture(
				name: "FeatureImpl",
				packageName: "Kit",
				swiftFileContentByFilePath: [
					"DefaultUserService.swift": """
					import Feature

					\(attribute(of: "DefaultUserService", arguments: ["fulfillingAdditionalTypes: [UserService.self]"]))
					public final class DefaultUserService: UserService, Instantiable {
					    public init(cache: Cache) {
					        self.cache = cache
					    }

					    @Instantiated let cache: Cache
					}
					""",
				],
				dependencies: ["Feature"],
			),
			ModuleFixture(
				name: "App",
				packageName: "Shop",
				swiftFileContentByFilePath: appFiles,
				dependencies: appDependencies,
			),
		]
	}

	/// An `App` module of package `Shop` depending on `dependencies`, whose root instantiates `Service`.
	private static func rootInstantiatingService(dependencies: [String]) -> ModuleFixture {
		ModuleFixture(
			name: "App",
			packageName: "Shop",
			swiftFileContent: [
				"""
				import Core

				@Instantiable(isRoot: true)
				final class Root: Instantiable {
				    init(service: Service) {
				        self.service = service
				    }
				    @Instantiated let service: Service
				}
				""",
			],
			dependencies: dependencies,
		)
	}

	/// `Feature`'s `package` `Service`, declared at line 2 with its `package` initializer at line 3.
	private static let packageService = """
	@Instantiable
	package final class Service: Instantiable {
	    package init() {}
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

	/// A `Feature` module of `packageName` whose public `Screen` instantiates the public `<extendedType>.Shelf`, declared
	/// in an extension of `extendedType` that spells no access modifier, through the protocol it conforms to alone, as
	/// fulfilled by a type `fulfilledByType:` names, which no initializer names. `Space.swift` holds `spaceDeclaration`,
	/// when there is one, from its second line, as adopters declare a namespace enum in a file of its own;
	/// `shelfFileDeclaration` sits in `Shelf.swift` above the extension, from its fifth line when the module imports
	/// `importedModuleName`, on which it then depends; and the module holds `otherFiles` too.
	private static func featureExtendingNamespace(
		inPackage packageName: String,
		declaredAs spaceDeclaration: String?,
		extending extendedType: String = "Space",
		importing importedModuleName: String? = nil,
		shelfFileDeclaration: String? = nil,
		alongside otherFiles: [String: String] = [:],
		omitsPackageName: Bool = false,
	) -> ModuleFixture {
		let importLine = importedModuleName.map { "import \($0)\n\n" } ?? ""
		// Split for Swift 6.2 on Linux, which times out type-checking the single expression.
		let screenFile: String = importLine + """
		@Instantiable
		public final class Screen: Instantiable {
		    public init(shelf: any Shelving) {
		        self.shelf = shelf
		    }
		    @Instantiated(fulfilledByType: "\(extendedType).Shelf") let shelf: any Shelving
		}
		"""
		let shelfFileDeclarationLines: String = shelfFileDeclaration.map { $0 + "\n\n" } ?? ""
		let shelfFile: String = [importLine, "public protocol Shelving {}\n\n", shelfFileDeclarationLines, """
		extension \(extendedType) {
		    @Instantiable
		    public final class Shelf: Instantiable, Shelving {
		        public init() {}
		    }
		}
		"""].joined()
		let spaceFile: [String: String] = spaceDeclaration.map { ["Space.swift": "// A namespace enum, in its own file as adopters write it.\n" + $0] } ?? [:]
		let swiftFileContentByFilePath: [String: String] = ["Screen.swift": screenFile, "Shelf.swift": shelfFile]
			.merging(spaceFile, uniquingKeysWith: { first, _ in first })
			.merging(otherFiles, uniquingKeysWith: { first, _ in first })
		let dependencies: [String] = importedModuleName.map { [$0] } ?? []
		return ModuleFixture(
			name: "Feature",
			packageName: packageName,
			swiftFileContentByFilePath: swiftFileContentByFilePath,
			dependencies: dependencies,
			omitsPackageName: omitsPackageName,
		)
	}

	/// A `Kit` module of package `Toolkit` that declares the design system's `public enum Space` in a file that holds no
	/// SafeDI marker, and an `App` module of package `Shop` whose root, which imports `Kit` too, instantiates
	/// `Feature`'s `Screen`.
	private static var kitDeclaringNamespaceAndAppImportingIt: (kit: ModuleFixture, app: ModuleFixture) {
		(
			kit: ModuleFixture(
				name: "Kit",
				packageName: "Toolkit",
				swiftFileContentByFilePath: ["Space.swift": "// The design system's namespace.\npublic enum Space {}"],
			),
			app: ModuleFixture(
				name: "App",
				packageName: "Shop",
				swiftFileContent: ["import Kit\n" + rootInstantiating("Screen")],
				dependencies: ["Feature", "Kit"],
			),
		)
	}

	/// A root that instantiates `serviceType` of `Feature`, which it imports.
	private static func rootInstantiating(_ serviceType: String) -> String {
		"""
		import Feature

		@Instantiable(isRoot: true)
		final class Root: Instantiable {
		    init(service: \(serviceType)) {
		        self.service = service
		    }
		    @Instantiated let service: \(serviceType)
		}
		"""
	}

	/// An `App` module of `packageName` depending on `Feature`, which declares `declaration`: by default, a root that
	/// instantiates `Feature`'s `serviceType`.
	private static func app(inPackage packageName: String, serviceType: String = "Service", declaring declaration: String? = nil) -> ModuleFixture {
		ModuleFixture(
			name: "App",
			packageName: packageName,
			swiftFileContent: [declaration ?? rootInstantiating(serviceType)],
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
}
