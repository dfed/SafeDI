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

/// Covers the `#SafeDIConfiguration` entries SafeDI can tell are mistakes: an `additionalDirectoriesToInclude` entry
/// from which SafeDI can read no Swift file, which `generate` warns about, and an `additionalMocksToGenerate` entry
/// that names no `@Instantiable` type, which fails `generate`. Only the configuration `generate` selects is judged.
///
/// `executeSafeDIToolTest` enumerates directories with a stub, while `generate` judges whether an entry names
/// something on disk, so the directories and files these tests list are real or certainly absent.
struct SafeDIToolConfigurationEntryTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – additionalDirectoriesToInclude

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warns_whenAdditionalDirectoryDoesNotExist() async throws {
		let missingDirectory = Self.missingPath()

		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.serviceContent],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration(additionalDirectoriesToInclude: ["\(missingDirectory)"])
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings.map(\.formatted) == [
			"\(output.fixtures["SafeDIConfiguration.swift"]):1:1: warning: This #SafeDIConfiguration lists `\(missingDirectory)` in additionalDirectoriesToInclude, but nothing exists at `\(missingDirectory)`, so SafeDI reads no Swift files from it. Correct the path, or remove it from additionalDirectoriesToInclude.",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warnsNamingWorkingDirectory_whenRelativeAdditionalDirectoryDoesNotExist() async throws {
		let missingDirectory = "SafeDIToolTestsMissingDirectory-\(UUID().uuidString)"

		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.serviceContent],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration(additionalDirectoriesToInclude: ["\(missingDirectory)"])
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings.map(\.formatted) == [
			"\(output.fixtures["SafeDIConfiguration.swift"]):1:1: warning: This #SafeDIConfiguration lists `\(missingDirectory)` in additionalDirectoriesToInclude, but nothing exists at `\(FileManager.default.currentDirectoryPath)/\(missingDirectory)`, so SafeDI reads no Swift files from it. SafeDI resolves a relative path against the directory SafeDITool runs in. Correct the path, or remove it from additionalDirectoriesToInclude.",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warns_whenAdditionalDirectoryIsFileThatIsNotSwiftFile() async throws {
		let textFile = try makeTemporaryDirectory().appendingPathComponent("Notes.txt")
		try "Notes".write(to: textFile, atomically: true, encoding: .utf8)

		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.serviceContent],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration(additionalDirectoriesToInclude: ["\(textFile.path)"])
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings.map(\.formatted) == [
			"\(output.fixtures["SafeDIConfiguration.swift"]):1:1: warning: This #SafeDIConfiguration lists `\(textFile.path)` in additionalDirectoriesToInclude, but `\(textFile.path)` is neither a directory nor a Swift file, so SafeDI reads no Swift files from it. List a directory or a Swift file, or remove it from additionalDirectoriesToInclude.",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warns_whenAdditionalDirectoryEntryIsSwiftFileThatDoesNotExist() async throws {
		let missingSwiftFile = "\(Self.missingPath())/Missing.swift"

		// Scan reads the entry too, and must not fail on it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.serviceContent],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration(additionalDirectoriesToInclude: ["\(missingSwiftFile)"])
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings.map(\.formatted) == [
			"\(output.fixtures["SafeDIConfiguration.swift"]):1:1: warning: This #SafeDIConfiguration lists `\(missingSwiftFile)` in additionalDirectoriesToInclude, but nothing exists at `\(missingSwiftFile)`, so SafeDI reads no Swift files from it. Correct the path, or remove it from additionalDirectoriesToInclude.",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotWarn_whenOnlyInactiveConfigurationListsSwiftFileThatDoesNotExist() async throws {
		let missingSwiftFile = "\(Self.missingPath())/Missing.swift"

		// Scan reads the directories of every configuration, and must not fail on an inactive one's entry.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.serviceContent],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#if INACTIVE_CONDITION
				#SafeDIConfiguration(additionalDirectoriesToInclude: ["\(missingSwiftFile)"])
				#else
				#SafeDIConfiguration()
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotWarn_whenAdditionalDirectoryIsEmpty() async throws {
		let emptyDirectory = try makeTemporaryDirectory()

		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.serviceContent],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration(additionalDirectoriesToInclude: ["\(emptyDirectory.path)"])
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotWarn_whenAdditionalDirectoryIsSwiftFile() async throws {
		let swiftFile = try makeTemporaryDirectory().appendingPathComponent("Helper.swift")
		try """
		@Instantiable
		public struct Helper: Instantiable {
		    public init() {}
		}
		""".write(to: swiftFile, atomically: true, encoding: .utf8)

		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.serviceContent],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration(additionalDirectoriesToInclude: ["\(swiftFile.path)"])
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warnsOncePerEntryInEntryOrder_whenSeveralAdditionalDirectoriesDoNotExist() async throws {
		let missingDirectory = Self.missingPath()
		let firstEntry = "\(missingDirectory)/B"
		let secondEntry = "\(missingDirectory)/A"

		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.serviceContent],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration(additionalDirectoriesToInclude: ["\(firstEntry)", "\(secondEntry)", "\(firstEntry)"])
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings.map(\.formatted) == [
			"\(output.fixtures["SafeDIConfiguration.swift"]):1:1: warning: This #SafeDIConfiguration lists `\(firstEntry)` in additionalDirectoriesToInclude, but nothing exists at `\(firstEntry)`, so SafeDI reads no Swift files from it. Correct the path, or remove it from additionalDirectoriesToInclude.",
			"\(output.fixtures["SafeDIConfiguration.swift"]):1:1: warning: This #SafeDIConfiguration lists `\(secondEntry)` in additionalDirectoriesToInclude, but nothing exists at `\(secondEntry)`, so SafeDI reads no Swift files from it. Correct the path, or remove it from additionalDirectoriesToInclude.",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warns_whenAdditionalDirectoryDoesNotExistAndModuleIsLoadedFromScanCache() async throws {
		let missingDirectory = Self.missingPath()

		// The configuration is rewritten after scan, keeping the modification time scan recorded, so only scan's
		// cache still lists the directory: the warning proves `generate` judged the directories scan read.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				#SafeDIConfiguration(additionalDirectoriesToInclude: ["\(missingDirectory)"])
				""",
				Self.serviceContent,
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			swiftFileContentAfterScan: [
				"""
				#SafeDIConfiguration()
				""",
				Self.serviceContent,
			],
		)

		#expect(output.warnings.map(\.formatted) == [
			"\(output.fixtures["File.swift"]):1:1: warning: This #SafeDIConfiguration lists `\(missingDirectory)` in additionalDirectoriesToInclude, but nothing exists at `\(missingDirectory)`, so SafeDI reads no Swift files from it. Correct the path, or remove it from additionalDirectoriesToInclude.",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warns_whenAdditionalDirectoryDoesNotExistAndGenerateScansForItself() async throws {
		let missingDirectory = Self.missingPath()

		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.serviceContent],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration(additionalDirectoriesToInclude: ["\(missingDirectory)"])
				""",
			],
			pluginInvocation: .scanDuringGenerate(reportsFixtureDirectoryThroughSymbolicLink: false),
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings.map(\.formatted) == [
			"\(output.fixtures.compilerPath(of: "SafeDIConfiguration.swift")):1:1: warning: This #SafeDIConfiguration lists `\(missingDirectory)` in additionalDirectoriesToInclude, but nothing exists at `\(missingDirectory)`, so SafeDI reads no Swift files from it. Correct the path, or remove it from additionalDirectoriesToInclude.",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warns_whenAdditionalDirectoryDoesNotExistAndOutputIsCombined() async throws {
		let missingDirectory = Self.missingPath()

		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.serviceContent],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration(additionalDirectoriesToInclude: ["\(missingDirectory)"])
				""",
			],
			buildCombinedOutput: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings.map(\.formatted) == [
			"\(output.fixtures["SafeDIConfiguration.swift"]):1:1: warning: This #SafeDIConfiguration lists `\(missingDirectory)` in additionalDirectoriesToInclude, but nothing exists at `\(missingDirectory)`, so SafeDI reads no Swift files from it. Correct the path, or remove it from additionalDirectoriesToInclude.",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotWarn_whenOnlyInactiveConfigurationListsMissingAdditionalDirectory() async throws {
		let missingDirectory = Self.missingPath()

		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.serviceContent],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#if INACTIVE_CONDITION
				#SafeDIConfiguration(additionalDirectoriesToInclude: ["\(missingDirectory)"])
				#else
				#SafeDIConfiguration()
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings == [])
	}

	// MARK: Tests – additionalMocksToGenerate

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenAdditionalMockNamesNoInstantiableType() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"\(fixtures["SafeDIConfiguration.swift"]):1:1: error: This #SafeDIConfiguration lists `Unknown` in additionalMocksToGenerate, but no @Instantiable declaration SafeDI read declares `Unknown`, so SafeDI cannot generate its mock. Correct the name to that of an @Instantiable type, or remove `Unknown` from additionalMocksToGenerate."
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.serviceContent],
				swiftFileContentByFilePath: [
					"SafeDIConfiguration.swift": """
					#SafeDIConfiguration(additionalMocksToGenerate: ["Unknown"])
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorForEachEntryInNameOrder_whenSeveralAdditionalMocksNameNoInstantiableType() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["SafeDIConfiguration.swift"]):1:1: error: This #SafeDIConfiguration lists `First` in additionalMocksToGenerate, but no @Instantiable declaration SafeDI read declares `First`, so SafeDI cannot generate its mock. Correct the name to that of an @Instantiable type, or remove `First` from additionalMocksToGenerate.
				\(fixtures["SafeDIConfiguration.swift"]):1:1: error: This #SafeDIConfiguration lists `Second` in additionalMocksToGenerate, but no @Instantiable declaration SafeDI read declares `Second`, so SafeDI cannot generate its mock. Correct the name to that of an @Instantiable type, or remove `Second` from additionalMocksToGenerate.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.serviceContent],
				swiftFileContentByFilePath: [
					"SafeDIConfiguration.swift": """
					#SafeDIConfiguration(additionalMocksToGenerate: ["Second", "Service", "First", "Second"])
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingNestedType_whenAdditionalMockOmitsEnclosingType() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"\(fixtures["SafeDIConfiguration.swift"]):1:1: error: This #SafeDIConfiguration lists `Inner` in additionalMocksToGenerate, but no @Instantiable declaration SafeDI read declares `Inner`, so SafeDI cannot generate its mock. SafeDI read @Instantiable types with similar names: `Outer.Inner`. Correct the name to that of an @Instantiable type, or remove `Inner` from additionalMocksToGenerate."
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public enum Outer {
					    @Instantiable
					    public struct Inner: Instantiable {
					        public init() {}
					    }
					}
					""",
				],
				swiftFileContentByFilePath: [
					"SafeDIConfiguration.swift": """
					#SafeDIConfiguration(additionalMocksToGenerate: ["Inner"])
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingEveryTypeWithMatchingName_whenSeveralNestedTypesShareName() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"\(fixtures["SafeDIConfiguration.swift"]):1:1: error: This #SafeDIConfiguration lists `Inner` in additionalMocksToGenerate, but no @Instantiable declaration SafeDI read declares `Inner`, so SafeDI cannot generate its mock. SafeDI read @Instantiable types with similar names: `First.Inner`, `Second.Inner`. Correct the name to that of an @Instantiable type, or remove `Inner` from additionalMocksToGenerate."
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public enum Second {
					    @Instantiable
					    public struct Inner: Instantiable {
					        public init() {}
					    }
					}
					""",
					"""
					public enum First {
					    @Instantiable
					    public struct Inner: Instantiable {
					        public init() {}
					    }
					}
					""",
				],
				swiftFileContentByFilePath: [
					"SafeDIConfiguration.swift": """
					#SafeDIConfiguration(additionalMocksToGenerate: ["Inner"])
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingUnqualifiedType_whenAdditionalMockIsQualifiedWithModuleName() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"\(fixtures["SafeDIConfiguration.swift"]):1:1: error: This #SafeDIConfiguration lists `ServiceModule.Service` in additionalMocksToGenerate, but no @Instantiable declaration SafeDI read declares `ServiceModule.Service`, so SafeDI cannot generate its mock. SafeDI read @Instantiable types with similar names: `Service`. Correct the name to that of an @Instantiable type, or remove `ServiceModule.Service` from additionalMocksToGenerate."
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.serviceContent],
				swiftFileContentByFilePath: [
					"SafeDIConfiguration.swift": """
					#SafeDIConfiguration(additionalMocksToGenerate: ["ServiceModule.Service"])
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingFulfillingType_whenAdditionalMockNamesTypeAnInstantiableFulfills() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"\(fixtures["SafeDIConfiguration.swift"]):1:1: error: This #SafeDIConfiguration lists `ServiceProtocol` in additionalMocksToGenerate, but no @Instantiable declaration SafeDI read declares `ServiceProtocol`, so SafeDI cannot generate its mock. `ServiceProtocol` is fulfilled by the @Instantiable type `DefaultService`. Correct the name to that of an @Instantiable type, or remove `ServiceProtocol` from additionalMocksToGenerate."
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public protocol ServiceProtocol {}

					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
					public struct DefaultService: ServiceProtocol, Instantiable {
					    public init() {}
					}
					""",
				],
				swiftFileContentByFilePath: [
					"SafeDIConfiguration.swift": """
					#SafeDIConfiguration(additionalMocksToGenerate: ["ServiceProtocol"])
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenAdditionalMockNamesNoInstantiableTypeAndOutputIsCombined() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"\(fixtures["SafeDIConfiguration.swift"]):1:1: error: This #SafeDIConfiguration lists `Unknown` in additionalMocksToGenerate, but no @Instantiable declaration SafeDI read declares `Unknown`, so SafeDI cannot generate its mock. Correct the name to that of an @Instantiable type, or remove `Unknown` from additionalMocksToGenerate."
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.serviceContent],
				swiftFileContentByFilePath: [
					"SafeDIConfiguration.swift": """
					#SafeDIConfiguration(additionalMocksToGenerate: ["Unknown"])
					""",
				],
				buildCombinedOutput: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenAdditionalMockNamesNoInstantiableTypeAndGenerateScansForItself() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"\(fixtures.compilerPath(of: "SafeDIConfiguration.swift")):1:1: error: This #SafeDIConfiguration lists `Unknown` in additionalMocksToGenerate, but no @Instantiable declaration SafeDI read declares `Unknown`, so SafeDI cannot generate its mock. Correct the name to that of an @Instantiable type, or remove `Unknown` from additionalMocksToGenerate."
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [Self.serviceContent],
				swiftFileContentByFilePath: [
					"SafeDIConfiguration.swift": """
					#SafeDIConfiguration(additionalMocksToGenerate: ["Unknown"])
					""",
				],
				pluginInvocation: .scanDuringGenerate(reportsFixtureDirectoryThroughSymbolicLink: false),
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesMockWithoutCode_whenOnlyInactiveConfigurationListsAdditionalMockThatNamesNoInstantiableType() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.serviceContent],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#if INACTIVE_CONDITION
				#SafeDIConfiguration(additionalMocksToGenerate: ["Unknown"])
				#else
				#SafeDIConfiguration()
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles == [
			"Unknown+SafeDIMock.swift": """
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if INACTIVE_CONDITION
			#error("SafeDI scanned this module assuming `#if INACTIVE_CONDITION` was inactive, but it is active in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
			#endif


			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let serviceContent = """
	@Instantiable
	public struct Service: Instantiable {
	    public init() {}
	}
	"""

	/// An absolute path at which nothing exists.
	private static func missingPath() -> String {
		URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SafeDIToolTestsMissing-\(UUID().uuidString)").path
	}

	/// A new, empty directory that the test deletes.
	private mutating func makeTemporaryDirectory() throws -> URL {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		filesToDelete.append(directory)
		return directory
	}
}
