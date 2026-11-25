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

/// The `mock()` SafeDI generates in a module whose `#SafeDIConfiguration` declares `defaultIsolation: MainActor.self`,
/// compiled with and without `-default-isolation MainActor`.
struct SafeDIToolMockDeclaredDefaultIsolationTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test(arguments: [nil, "MainActor"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsMainActor_whenModuleDeclaresMainActorAndClassSpellsNoAttributes(buildSettingDefaultIsolation: String?) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Client: Instantiable {
				    public init(timeout: Int = 30) {
				        self.timeout = timeout
				    }

				    public let timeout: Int
				}
				""",
			],
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.declaringMainActor],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: buildSettingDefaultIsolation),
		)

		#expect(output.generatedFiles == [
			"Client+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Client {
			    @MainActor static func mock(
			        timeout: Int = 30
			    ) -> Client {
			        return Client(timeout: timeout)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test(arguments: [nil, "MainActor"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsMainActor_whenModuleDeclaresMainActorAndActorSpellsNoAttributes(buildSettingDefaultIsolation: String?) async throws {
		// #1016: an actor's mock in a main-actor module.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public actor Store: Instantiable {
				    public init(limit: Int = 10) {
				        self.limit = limit
				    }

				    let limit: Int
				}
				""",
			],
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.declaringMainActor],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: buildSettingDefaultIsolation),
		)

		#expect(output.generatedFiles == [
			"Store+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Store {
			    @MainActor static func mock(
			        limit: Int = 10
			    ) -> Store {
			        return Store(limit: limit)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test(arguments: [nil, "MainActor"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsWrittenText_whenModuleDeclaresMainActorAndTypeSpellsMockAttributes(buildSettingDefaultIsolation: String?) async throws {
		// Written text replaces the module's default: `nonisolated` opts one type's mock out of it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(mockAttributes: "nonisolated", generateMock: true)
				public final class Formatter: Instantiable, Sendable {
				    public nonisolated init(locale: String = "en") {
				        self.locale = locale
				    }

				    public let locale: String
				}
				""",
			],
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.declaringMainActor],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: buildSettingDefaultIsolation),
		)

		#expect(output.generatedFiles == [
			"Formatter+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Formatter {
			    nonisolated static func mock(
			        locale: String = "en"
			    ) -> Formatter {
			        return Formatter(locale: locale)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test(arguments: [nil, "MainActor"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsMainActor_whenModuleDeclaresMainActorAndTypeSpellsOnlyGeneratedInitializerAttributes(buildSettingDefaultIsolation: String?) async throws {
		// Each attribute field takes the module's default on its own: text written for the initializers leaves the mock's
		// default in place.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				public protocol Presentable: AnyObject {}
				""",
				"""
				@Instantiable(generatedInitializerAttributes: "@MainActor", generateMock: true)
				public final class Screen: Instantiable, Presentable {
				    public init(limit: Int = 10) {
				        self.limit = limit
				    }

				    let limit: Int
				}
				""",
			],
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.declaringMainActor],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: buildSettingDefaultIsolation),
		)

		#expect(output.generatedFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    @MainActor static func mock(
			        limit: Int = 10
			    ) -> Screen {
			        return Screen(limit: limit)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsMainActorOnAdditionalMock_whenOnlyDeclaringModuleDeclaresMainActor(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.additionalMockModules(featureDeclares: true, testsDeclare: false),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let expectedMock = generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            client: (() -> Client)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                client: client
		            )
		        }

		        var client: (() -> Client)? { __safeDI_storage.client }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                client: (() -> Client)?
		            ) {
		                self.client = client
		            }

		            let client: (() -> Client)?
		        }
		    }

		    @MainActor static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let client = if let safeDIBuilder = safeDIOverrides.client { safeDIBuilder() } else { Client() }
		        return Root(client: client)
		    }
		}
		#endif
		"""
		#expect(try #require(output.modules["Tests"]).generatedFiles == (integration == .moduleInfo
				? ["Tests.swift": expectedMock]
				: ["Root+SafeDIMock.swift": expectedMock, "SafeDIMockConfiguration.swift": generatedFileHeader]))
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsMainActorOnAdditionalMock_whenOnlyGeneratingModuleDeclaresMainActor(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.additionalMockModules(featureDeclares: false, testsDeclare: true),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let expectedMock = generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            client: (() -> Client)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                client: client
		            )
		        }

		        var client: (() -> Client)? { __safeDI_storage.client }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                client: (() -> Client)?
		            ) {
		                self.client = client
		            }

		            let client: (() -> Client)?
		        }
		    }

		    @MainActor static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let client = if let safeDIBuilder = safeDIOverrides.client { safeDIBuilder() } else { Client() }
		        return Root(client: client)
		    }
		}
		#endif
		"""
		#expect(try #require(output.modules["Tests"]).generatedFiles == (integration == .moduleInfo
				? ["Tests.swift": expectedMock]
				: ["Root+SafeDIMock.swift": expectedMock, "SafeDIMockConfiguration.swift": generatedFileHeader]))
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let declaringMainActor = """
	#SafeDIConfiguration(
	    defaultIsolation: MainActor.self
	)
	"""

	/// `Feature`, which declares `Root`, and `Tests`, which generates `Root`'s mock through `additionalMocksToGenerate`.
	/// A module that declares the main actor as its default isolation is compiled with `-default-isolation MainActor`.
	private static func additionalMockModules(featureDeclares: Bool, testsDeclare: Bool) -> [ModuleFixture] {
		[
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"""
					@Instantiable
					public final class Root: Instantiable {
					    public init(client: Client) {
					        self.client = client
					    }

					    @Instantiated let client: Client
					}
					""",
					"""
					@Instantiable
					public final class Client: Instantiable {
					    public init() {}
					}
					""",
				],
				swiftFileContentByFilePath: featureDeclares ? ["SafeDIConfiguration.swift": declaringMainActor] : [:],
				compilerSettings: VerificationCompilerSettings(defaultIsolation: featureDeclares ? "MainActor" : nil),
			),
			ModuleFixture(
				name: "Tests",
				packageName: "Shop",
				swiftFileContentByFilePath: ["SafeDIConfiguration.swift": """
				#SafeDIConfiguration(
				    additionalMocksToGenerate: ["Root"]\(testsDeclare ? ",\n    defaultIsolation: MainActor.self" : "")
				)
				"""],
				dependencies: ["Feature"],
				compilerSettings: VerificationCompilerSettings(defaultIsolation: testsDeclare ? "MainActor" : nil),
			),
		]
	}
}
