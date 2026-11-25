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

	// MARK: Private

	private var filesToDelete: [URL]

	private static let declaringMainActor = """
	#SafeDIConfiguration(
	    defaultIsolation: MainActor.self
	)
	"""
}
