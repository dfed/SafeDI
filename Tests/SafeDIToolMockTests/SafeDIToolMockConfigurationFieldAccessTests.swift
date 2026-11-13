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

/// The fields of the generated configuration structs are read-only outside the file that declares them, so code in the
/// mock's own module builds a configuration only through its generated initializers. How the fields are stored is not
/// API: an initializer that assigned them one by one would break when that changes.
struct SafeDIToolMockConfigurationFieldAccessTests: ~Copyable {
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mockConfiguration_failsToCompile_whenExtensionInitializerInAnotherFileAssignsField() async throws {
		guard let standardError = try await standardErrorOfFailedCompile(
			generateMock: "true",
			extensionFileContent: """
			#if DEBUG
			extension Leaf.SafeDIMockConfiguration {
			    init(uppercasedName name: String) {
			        self.name = name.uppercased()
			        self.safeDIBuilder = nil
			    }
			}
			#endif
			""",
		) else { return }
		#expect(standardError.contains("error: cannot assign to property: 'name' setter is inaccessible"), "Unexpected compiler output \(standardError)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func safeDIOverrides_failsToCompile_whenExtensionInitializerInAnotherFileAssignsField() async throws {
		guard let standardError = try await standardErrorOfFailedCompile(
			generateMock: "true",
			extensionFileContent: """
			#if DEBUG
			extension Root.SafeDIOverrides {
			    init(leafNamed name: String) {
			        self.leaf = .init(name: name)
			    }
			}
			#endif
			""",
		) else { return }
		#expect(standardError.contains("error: cannot assign to property: 'leaf' setter is inaccessible"), "Unexpected compiler output \(standardError)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func publicMockConfiguration_failsToCompile_whenExtensionInitializerInAnotherFileAssignsField() async throws {
		guard let standardError = try await standardErrorOfFailedCompile(
			generateMock: ".public",
			extensionFileContent: """
			#if DEBUG
			extension __safeDI_Feed_Leaf_MockConfiguration {
			    init(uppercasedName name: String) {
			        self.name = name.uppercased()
			        self.safeDIBuilder = nil
			    }
			}
			#endif
			""",
		) else { return }
		#expect(standardError.contains("error: cannot assign to property: 'name' setter is inaccessible"), "Unexpected compiler output \(standardError)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mockConfiguration_compiles_whenExtensionInitializerInAnotherFileDelegatesToGeneratedInitializer() async throws {
		_ = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(generateMock: "true", extensionFileContent: """
			#if DEBUG
			extension Leaf.SafeDIMockConfiguration {
			    init(uppercasedName name: String) {
			        self.init(name: name.uppercased())
			    }
			}
			#endif
			"""),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Module `Feed`: `Root`, whose mock is generated as `generateMock` says, builds a `Leaf` with a default-valued
	/// parameter, and a file named apart from the generated files holds `extensionFileContent`.
	private static func modules(generateMock: String, extensionFileContent: String) -> [ModuleFixture] {
		[
			ModuleFixture(
				name: "Feed",
				packageName: "Feed",
				swiftFileContent: [
					"""
					@Instantiable(generateMock: \(generateMock))
					public struct Root: Instantiable {
					    public init(leaf: Leaf) {
					        self.leaf = leaf
					    }

					    @Instantiated let leaf: Leaf
					}
					""",
					"""
					@Instantiable
					public struct Leaf: Instantiable {
					    public init(name: String = "leaf") {
					        self.name = name
					    }

					    let name: String
					}
					""",
				],
				swiftFileContentByFilePath: ["ConfigurationExtension.swift": extensionFileContent],
			),
		]
	}

	/// What the compiler reported when module `Feed` failed to compile, or `nil` when compile verification is disabled.
	/// Throws when the module compiled.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func standardErrorOfFailedCompile(generateMock: String, extensionFileContent: String) async throws -> String? {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(generateMock: generateMock, extensionFileContent: extensionFileContent),
			integration: .moduleInfo,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)
		guard compileVerificationIsEnabled else { return nil }
		let failure = try #require(output.compilation?.failure)
		#expect(failure.moduleName == "Feed")
		return failure.standardError
	}
}
