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

/// A module whose `#SafeDIConfiguration` declares `defaultIsolation: MainActor.self` gets `@MainActor` on the initializer
/// SafeDI generates for each root that spells no attribute text, whatever the module's build setting: each test compiles
/// its output with and without `-default-isolation MainActor`.
struct SafeDIToolDeclaredDefaultIsolationTests: ~Copyable {
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
	mutating func generate_spellsMainActorOnRootInitializer_whenModuleDeclaresMainActorAndChildIsMainActorThroughProtocol(buildSettingDefaultIsolation: String?) async throws {
		// #661: `Screen` is main-actor through a protocol of its own module, so `Root`'s generated initializer, which
		// builds it, must be too.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				public protocol Presentable: AnyObject {}
				""",
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated let screen: Screen
				}
				""",
				"""
				@Instantiable
				public final class Screen: Instantiable, Presentable {
				    public init() {}
				}
				""",
			],
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.declaringMainActor],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: buildSettingDefaultIsolation),
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    @MainActor public convenience init() {
			        let screen = Screen()
			        self.init(screen: screen)
			    }
			}
			""",
		])
	}

	@Test(arguments: [nil, "MainActor"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsMainActorOnActorRootInitializer_whenModuleDeclaresMainActor(buildSettingDefaultIsolation: String?) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public actor Root: Instantiable {
				    public init(client: Client) {
				        self.client = client
				    }

				    @Instantiated let client: Client
				}
				""",
				"""
				@Instantiable
				public final class Client: Instantiable, Sendable {
				    public init() {}
				}
				""",
			],
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.declaringMainActor],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: buildSettingDefaultIsolation),
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    @MainActor public init() {
			        let client = Client()
			        self.init(client: client)
			    }
			}
			""",
		])
	}

	@Test(arguments: [nil, "MainActor"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsMainActorOnRootInitializer_whenModuleDeclaresMainActorAndRootIsMainActorThroughProtocol(buildSettingDefaultIsolation: String?) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				public protocol Presentable: AnyObject {}
				""",
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable, Presentable {
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
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.declaringMainActor],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: buildSettingDefaultIsolation),
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    @MainActor public convenience init() {
			        let client = Client()
			        self.init(client: client)
			    }
			}
			""",
		])
	}

	@Test(arguments: [nil, "MainActor"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsMainActorOnRootInitializer_whenModuleDeclaresMainActorAndRootIsSpelledNonisolated(buildSettingDefaultIsolation: String?) async throws {
		// SafeDI reads no isolation a declaration spells: only its attribute text being empty.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				nonisolated public final class Root: Instantiable {
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
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.declaringMainActor],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: buildSettingDefaultIsolation),
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    @MainActor public convenience init() {
			        let client = Client()
			        self.init(client: client)
			    }
			}
			""",
		])
	}

	@Test(arguments: [nil, "MainActor"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsWrittenTextOnRootInitializer_whenModuleDeclaresMainActorAndRootSpellsGeneratedInitializerAttributes(buildSettingDefaultIsolation: String?) async throws {
		// Text the declaration spells replaces the module's default rather than adding to it, even text that states
		// no isolation.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generatedInitializerAttributes: "@available(macOS 10.15, *)")
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
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.declaringMainActor],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: buildSettingDefaultIsolation),
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    @available(macOS 10.15, *) public convenience init() {
			        let client = Client()
			        self.init(client: client)
			    }
			}
			""",
		])
	}

	@Test(arguments: [nil, "MainActor"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsMainActorOnRootInitializer_whenModuleDeclaresMainActorAndRootSpellsOnlyMockAttributes(buildSettingDefaultIsolation: String?) async throws {
		// Each attribute field takes the module's default on its own: text written for the mock leaves the initializer's
		// default in place.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				public protocol Presentable: AnyObject {}
				""",
				"""
				@Instantiable(isRoot: true, mockAttributes: "nonisolated")
				public final class Root: Instantiable {
				    public init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated let screen: Screen
				}
				""",
				"""
				@Instantiable
				public final class Screen: Instantiable, Presentable {
				    public init() {}
				}
				""",
			],
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.declaringMainActor],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: buildSettingDefaultIsolation),
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    @MainActor public convenience init() {
			        let screen = Screen()
			        self.init(screen: screen)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsNoAttributeOnRootInitializer_whenModuleDeclaresNilDefaultIsolation() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
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
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": """
			#SafeDIConfiguration(
			    defaultIsolation: nil
			)
			"""],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let client = Client()
			        self.init(client: client)
			    }
			}
			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let declaringMainActor = """
	#SafeDIConfiguration(
	    defaultIsolation: MainActor.self
	)
	"""
}
