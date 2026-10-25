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

/// Covers where a module's `#SafeDIConfiguration` lives. A configuration in `SafeDIConfiguration.swift` is
/// read before the rest of the module; one in any other file is found by a first walk that assumes the
/// default mock condition, and a non-default mock condition then walks the module again. Each test places
/// its configuration through `swiftFileContentByFilePath` so the path it exercises is explicit.
struct SafeDIToolConfigurationFileTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Configuration in SafeDIConfiguration.swift

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_usesMockOnlyExtensionGuardedByDebug_whenConfigurationInSafeDIConfigurationFileKeepsDefaultMockCondition() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.rootContent,
				Self.featureContent,
				Self.mockOnlyStringExtensionContent(guardedBy: "DEBUG"),
			],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration()
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Feature+SafeDIMock.swift"] == Self.featureMockUsingStringMock(wrappedIn: "DEBUG"), "Unexpected output \(output.mockFiles["Feature+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_skipsMockOnlyExtensionGuardedByDebug_whenConfigurationInSafeDIConfigurationFileMakesMocksUnconditional() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.rootContent,
				Self.featureContent,
				Self.mockOnlyStringExtensionContent(guardedBy: "DEBUG"),
			],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration(mockConditionalCompilation: nil)
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			// The verification compile defines `DEBUG`, so the assertion below fails it on purpose.
			skipCompileVerification: true,
		)

		#expect(output.mockFiles["Feature+SafeDIMock.swift"] == Self.unconditionalFeatureMockSkippingDebugGuardedExtension, "Unexpected output \(output.mockFiles["Feature+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_usesMockOnlyExtensionGuardedByRenamedCondition_whenConfigurationInSafeDIConfigurationFileRenamesMockCondition() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.rootContent,
				Self.featureContent,
				Self.mockOnlyStringExtensionContent(guardedBy: "TESTING"),
			],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration(mockConditionalCompilation: "TESTING")
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Feature+SafeDIMock.swift"] == Self.featureMockUsingStringMock(wrappedIn: "TESTING"), "Unexpected output \(output.mockFiles["Feature+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_ignoresConfiguration_whenConfigurationInSafeDIConfigurationFileIsGuardedByConditionThatIsNotSupplied() async throws {
		// A configuration is production content, so its block is evaluated with the supplied conditions
		// alone: the default mock condition, `DEBUG`, is not assumed active for it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct NetworkService: Instantiable {
				    public init() {}
				}
				""",
			],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#if DEBUG
				#SafeDIConfiguration(mockConditionalCompilation: "TESTING")
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			// The verification compile defines `DEBUG`, so the assertion below fails it on purpose.
			skipCompileVerification: true,
		)

		#expect(output.mockFiles["NetworkService+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		#error("SafeDI scanned this module assuming `#if DEBUG` was inactive, but it is active in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
		#endif

		#if DEBUG
		extension NetworkService {
		    static func mock() -> NetworkService {
		        NetworkService()
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["NetworkService+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_appliesConfiguration_whenConfigurationInSafeDIConfigurationFileIsGuardedByConditionThatIsSupplied() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct NetworkService: Instantiable {
				    public init() {}
				}
				""",
			],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#if DEBUG
				#SafeDIConfiguration(mockConditionalCompilation: "TESTING")
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			activeCompilationConditions: ["DEBUG"],
		)

		#expect(output.mockFiles["NetworkService+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if !(DEBUG)
		#error("SafeDI scanned this module assuming `#if DEBUG` was active, but it is inactive in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
		#endif

		#if TESTING
		extension NetworkService {
		    static func mock() -> NetworkService {
		        NetworkService()
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["NetworkService+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_scansSafeDIConfigurationFileWithModuleMockCondition_whenSafeDIConfigurationFileAlsoDeclaresMockOnlyExtension() async throws {
		// The configuration file is parsed once: its walk to find the configuration assumes the default mock
		// condition, so its other declarations are walked again with the condition the configuration names.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.rootContent,
				Self.featureContent,
			],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration(mockConditionalCompilation: nil)

				\(Self.mockOnlyStringExtensionContent(guardedBy: "DEBUG"))
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			// The verification compile defines `DEBUG`, so the assertion below fails it on purpose.
			skipCompileVerification: true,
		)

		#expect(output.mockFiles["Feature+SafeDIMock.swift"] == Self.unconditionalFeatureMockSkippingDebugGuardedExtension, "Unexpected output \(output.mockFiles["Feature+SafeDIMock.swift"] ?? "")")
	}

	// MARK: Tests – Configuration in another file

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_usesMockOnlyExtensionGuardedByDebug_whenConfigurationInAnotherFileKeepsDefaultMockCondition() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.rootContent,
				Self.featureContent,
				Self.mockOnlyStringExtensionContent(guardedBy: "DEBUG"),
			],
			swiftFileContentByFilePath: [
				"Configuration.swift": """
				#SafeDIConfiguration()
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Feature+SafeDIMock.swift"] == Self.featureMockUsingStringMock(wrappedIn: "DEBUG"), "Unexpected output \(output.mockFiles["Feature+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_skipsMockOnlyExtensionGuardedByDebug_whenConfigurationInAnotherFileMakesMocksUnconditional() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.rootContent,
				Self.featureContent,
				Self.mockOnlyStringExtensionContent(guardedBy: "DEBUG"),
			],
			swiftFileContentByFilePath: [
				"Configuration.swift": """
				#SafeDIConfiguration(mockConditionalCompilation: nil)
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			// The verification compile defines `DEBUG`, so the assertion below fails it on purpose.
			skipCompileVerification: true,
		)

		#expect(output.mockFiles["Feature+SafeDIMock.swift"] == Self.unconditionalFeatureMockSkippingDebugGuardedExtension, "Unexpected output \(output.mockFiles["Feature+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_usesMockOnlyExtensionGuardedByRenamedCondition_whenConfigurationInAnotherFileRenamesMockCondition() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.rootContent,
				Self.featureContent,
				Self.mockOnlyStringExtensionContent(guardedBy: "TESTING"),
			],
			swiftFileContentByFilePath: [
				"Configuration.swift": """
				#SafeDIConfiguration(mockConditionalCompilation: "TESTING")
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Feature+SafeDIMock.swift"] == Self.featureMockUsingStringMock(wrappedIn: "TESTING"), "Unexpected output \(output.mockFiles["Feature+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_scansSafeDIConfigurationFileAgain_whenSafeDIConfigurationFileDeclaresNoConfigurationAndAnotherFileChangesMockCondition() async throws {
		// `SafeDIConfiguration.swift` is read first, assuming the default mock condition, under which its
		// `#if DEBUG` extension is scanned. The configuration in another file makes mocks unconditional, so
		// the second walk must cover that file too and skip the extension.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.rootContent,
				Self.featureContent,
			],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": Self.mockOnlyStringExtensionContent(guardedBy: "DEBUG"),
				"Configuration.swift": """
				#SafeDIConfiguration(mockConditionalCompilation: nil)
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			// The verification compile defines `DEBUG`, so the assertion below fails it on purpose.
			skipCompileVerification: true,
		)

		#expect(output.mockFiles["Feature+SafeDIMock.swift"] == Self.unconditionalFeatureMockSkippingDebugGuardedExtension, "Unexpected output \(output.mockFiles["Feature+SafeDIMock.swift"] ?? "")")
	}

	// MARK: Tests – Multiple configurations

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsError_whenSafeDIConfigurationFileAndAnotherFileBothDeclareConfiguration() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				Found 2 #SafeDIConfiguration declarations in this module. Each module must have at most one #SafeDIConfiguration. Found in:
				\t\(fixtures["Other.swift"])
				\t\(fixtures["SafeDIConfiguration.swift"])
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable
					public struct SimpleType: Instantiable {
					    public init() {}
					}
					""",
				],
				swiftFileContentByFilePath: [
					"SafeDIConfiguration.swift": """
					#SafeDIConfiguration()
					""",
					"Other.swift": """
					#SafeDIConfiguration(mockConditionalCompilation: nil)
					""",
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsError_whenTwoSafeDIConfigurationFilesBothDeclareConfiguration() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				Found 2 #SafeDIConfiguration declarations in this module. Each module must have at most one #SafeDIConfiguration. Found in:
				\t\(fixtures["First/SafeDIConfiguration.swift"])
				\t\(fixtures["Second/SafeDIConfiguration.swift"])
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable
					public struct SimpleType: Instantiable {
					    public init() {}
					}
					""",
				],
				swiftFileContentByFilePath: [
					"First/SafeDIConfiguration.swift": """
					#SafeDIConfiguration(mockConditionalCompilation: "TESTING")
					""",
					"Second/SafeDIConfiguration.swift": """
					#SafeDIConfiguration(mockConditionalCompilation: nil)
					""",
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – Placement warning

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warns_whenConfigurationInAnotherFileMakesMocksUnconditional() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.simpleTypeContent],
			swiftFileContentByFilePath: [
				"Configuration.swift": """
				import SafeDI

				#SafeDIConfiguration(mockConditionalCompilation: nil)
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings.map(\.formatted) == [
			"\(output.fixtures["Configuration.swift"]):3:1: warning: \(Self.placementWarningMessage)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warns_whenConfigurationInAnotherFileRenamesMockCondition() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.simpleTypeContent],
			swiftFileContentByFilePath: [
				"Configuration.swift": """
				#SafeDIConfiguration(mockConditionalCompilation: "TESTING")
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings.map(\.formatted) == [
			"\(output.fixtures["Configuration.swift"]):1:1: warning: \(Self.placementWarningMessage)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotWarn_whenConfigurationInSafeDIConfigurationFileMakesMocksUnconditional() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.simpleTypeContent],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration(mockConditionalCompilation: nil)
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotWarn_whenConfigurationInSafeDIConfigurationFileRenamesMockCondition() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.simpleTypeContent],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration(mockConditionalCompilation: "TESTING")
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotWarn_whenConfigurationInAnotherFileKeepsDefaultMockCondition() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.simpleTypeContent],
			swiftFileContentByFilePath: [
				"Configuration.swift": """
				#SafeDIConfiguration(additionalImportedModules: ["Foundation"])
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotWarn_whenConfigurationThatMakesMocksUnconditionalBelongsToAnotherModule() async throws {
		// The additional directory's files are scanned but are not this module's own files, so their
		// configuration does not apply to this module and is not this module's to move.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [Self.simpleTypeContent],
			additionalDirectorySwiftFileContent: [
				"""
				#SafeDIConfiguration(mockConditionalCompilation: nil)
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warns_whenModuleIsLoadedFromScanCache() async throws {
		let projectRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
		let simpleTypeFile = projectRoot.appendingPathComponent("SimpleType.swift")
		try Self.simpleTypeContent.write(to: simpleTypeFile, atomically: true, encoding: .utf8)
		let configurationFile = projectRoot.appendingPathComponent("Configuration.swift")
		try """
		#SafeDIConfiguration(mockConditionalCompilation: nil)
		""".write(to: configurationFile, atomically: true, encoding: .utf8)

		let swiftFileCSV = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try "\(simpleTypeFile.path),\(configurationFile.path)"
			.write(to: swiftFileCSV, atomically: true, encoding: .utf8)
		let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
		let manifestFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
		filesToDelete += [projectRoot, swiftFileCSV, outputDirectory, manifestFile, scannedModuleInfoURL(forManifestPath: manifestFile.path)]

		try await Scan.parse([
			"--input-sources-file", swiftFileCSV.path,
			"--project-root", projectRoot.path,
			"--output-directory", outputDirectory.path,
			"--manifest-file", manifestFile.path,
		]).run()

		// Remove the configuration but backdate the file, so only scan's cache still holds the configuration:
		// a warning proves `generate` reported it from the cached module rather than from a fresh parse.
		try "".write(to: configurationFile, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes(
			[.modificationDate: Date(timeIntervalSince1970: 0)],
			ofItemAtPath: configurationFile.path,
		)

		let warnings = try await Generate.parse([
			swiftFileCSV.path,
			"--swift-manifest", manifestFile.path,
		]).generate()

		#expect(warnings.map(\.formatted) == [
			"\(configurationFile.path):1:1: warning: \(Self.placementWarningMessage)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_writesGeneratedCode_whenGenerateWarns() async throws {
		let projectRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
		let helperFile = projectRoot.appendingPathComponent("Helper.swift")
		try """
		@Instantiable
		public struct Helper: Instantiable {
		    public init() {}
		}
		""".write(to: helperFile, atomically: true, encoding: .utf8)
		let rootFile = projectRoot.appendingPathComponent("Root.swift")
		try """
		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init(helper: Helper) {
		        self.helper = helper
		    }
		    @Instantiated let helper: Helper
		}
		""".write(to: rootFile, atomically: true, encoding: .utf8)
		let configurationFile = projectRoot.appendingPathComponent("Configuration.swift")
		try """
		#SafeDIConfiguration(mockConditionalCompilation: nil)
		""".write(to: configurationFile, atomically: true, encoding: .utf8)

		let swiftFileCSV = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try "\(helperFile.path),\(rootFile.path),\(configurationFile.path)"
			.write(to: swiftFileCSV, atomically: true, encoding: .utf8)
		let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
		filesToDelete += [projectRoot, swiftFileCSV, outputDirectory]

		try await Generate.parse([
			swiftFileCSV.path,
			"--output-directory", outputDirectory.path,
		]).run()

		let generatedRoot = try String(contentsOf: outputDirectory.appendingPathComponent("Root+SafeDI.swift"), encoding: .utf8)
		#expect(generatedRoot == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public init() {
		        let helper = Helper()
		        self.init(helper: helper)
		    }
		}
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let placementWarningMessage = "This #SafeDIConfiguration sets `mockConditionalCompilation` and is not in a file named `SafeDIConfiguration.swift`, so SafeDI had to scan this module’s files twice. Move it to a file named `SafeDIConfiguration.swift` so SafeDI can read it first. A #SafeDIConfiguration outside `SafeDIConfiguration.swift` will be an error in SafeDI 3.0."

	private static let simpleTypeContent = """
	@Instantiable
	public struct SimpleType: Instantiable {
	    public init() {}
	}
	"""

	private static let rootContent = """
	@Instantiable(isRoot: true, generateMock: true)
	public struct Root: Instantiable {
	    public init(featureBuilder: Instantiator<Feature>) {
	        self.featureBuilder = featureBuilder
	    }
	    @Instantiated let featureBuilder: Instantiator<Feature>
	}
	"""

	private static let featureContent = """
	@Instantiable(generateMock: true)
	public struct Feature: Instantiable {
	    public init(name: String) {
	        self.name = name
	    }
	    @Forwarded let name: String
	}
	"""

	private static func mockOnlyStringExtensionContent(guardedBy condition: String) -> String {
		"""
		#if \(condition)
		@Instantiable(mockOnly: true)
		extension String: Instantiable {
		    public static func mock() -> String { "" }
		}
		#endif
		"""
	}

	private static func featureMockUsingStringMock(wrappedIn condition: String) -> String {
		"""
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if \(condition)
		extension Feature {
		    static func mock(
		        name: String = String.mock()
		    ) -> Feature {
		        return Feature(name: name)
		    }
		}
		#endif
		"""
	}

	private static let unconditionalFeatureMockSkippingDebugGuardedExtension = """
	// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
	// Any modifications made to this file will be overwritten on subsequent builds.
	// Please refrain from editing this file directly.

	#if DEBUG
	#error("SafeDI scanned this module assuming `#if DEBUG` was inactive, but it is active in this compilation. SafeDI's build integration must report the compilation conditions the compiler uses; see the \\"Conditional compilation\\" section of the SafeDI manual.")
	#endif

	extension Feature {
	    static func mock(
	        name: String
	    ) -> Feature {
	        return Feature(name: name)
	    }
	}
	"""
}
