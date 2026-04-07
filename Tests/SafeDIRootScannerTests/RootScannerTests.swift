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
import SafeDIRootScannerCore
import Testing
@testable import SafeDIRootScanner

struct RootScannerTests {
	@Test
	func scan_writesExactManifestAndOutputList_forDuplicateBasenamesInDifferentDirectories() throws {
		let fixture = try ScannerFixture()
		defer { fixture.delete() }

		let rootA = try fixture.writeFile(
			relativePath: "Sources/FeatureA/Root.swift",
			content: """
			@Instantiable(isRoot: true)
			struct Root {
			    init(dep: Dep) {
			        self.dep = dep
			    }
			    @Instantiated let dep: Dep
			}
			@Instantiable
			struct Dep {
			    init() {}
			}
			""",
		)
		let rootB = try fixture.writeFile(
			relativePath: "Sources/FeatureB/Root.swift",
			content: """
			@Instantiable(isRoot: true)
			struct Root {
			    init(dep: Dep) {
			        self.dep = dep
			    }
			    @Instantiated let dep: Dep
			}
			@Instantiable
			struct Dep {
			    init() {}
			}
			""",
		)

		let outputDirectory = fixture.rootDirectory.appendingPathComponent("Output")
		let featureAOutputPath = outputDirectory.appendingPathComponent("FeatureA_Root+SafeDI.swift").path
		let featureBOutputPath = outputDirectory.appendingPathComponent("FeatureB_Root+SafeDI.swift").path
		let result = try RootScanner().scan(
			swiftFiles: [rootB, rootA],
			relativeTo: fixture.rootDirectory,
			outputDirectory: outputDirectory,
		)

		#expect(result.manifest == RootScanner.Manifest(
			dependencyTreeGeneration: [
				RootScanner.Manifest.InputOutputMap(
					inputFilePath: "Sources/FeatureA/Root.swift",
					outputFilePath: featureAOutputPath,
				),
				RootScanner.Manifest.InputOutputMap(
					inputFilePath: "Sources/FeatureB/Root.swift",
					outputFilePath: featureBOutputPath,
				),
			],
			mockGeneration: [],
		))

		// Verify outputFiles includes only DI tree outputs (no mock outputs without config).
		#expect(result.outputFiles.count == 2)
		#expect(result.outputFiles.contains(URL(fileURLWithPath: featureAOutputPath)))

		let manifestData = try JSONEncoder().encode(result.manifest)
		let decodedManifest = try JSONDecoder().decode(SafeDIToolManifest.self, from: manifestData)
		#expect(decodedManifest.dependencyTreeGeneration.map(\.inputFilePath) == [
			"Sources/FeatureA/Root.swift",
			"Sources/FeatureB/Root.swift",
		])
		#expect(decodedManifest.dependencyTreeGeneration.map(\.outputFilePath) == [
			featureAOutputPath,
			featureBOutputPath,
		])
		#expect(decodedManifest.mockGeneration.isEmpty)
	}

	@Test
	func scan_ignoresRootsThatOnlyAppearInsideCommentsAndStrings() throws {
		let fixture = try ScannerFixture()
		defer { fixture.delete() }

		let actualRoot = try fixture.writeFile(
			relativePath: "Sources/ActualRoot.swift",
			content: """
			@Instantiable(
			    fulfillingAdditionalTypes: [Foo<Bar, Baz>.self],
			    nestedArgument: .factory(makeValue(label: "example", value: 1)),
			    isRoot: true
			)
			struct ActualRoot {
			    init(dep: Dep) {
			        self.dep = dep
			    }
			    @Instantiated let dep: Dep
			}
			@Instantiable
			struct Dep {
			    init() {}
			}
			""",
		)
		_ = try fixture.writeFile(
			relativePath: "Sources/Comment.swift",
			content: """
			// @Instantiable(isRoot: true)
			@Instantiable
			struct CommentOnly {
			    init() {}
			}
			""",
		)
		_ = try fixture.writeFile(
			relativePath: "Sources/BlockComment.swift",
			content: """
			/*
			@Instantiable(isRoot: true)
			*/
			@Instantiable
			struct BlockCommentOnly {
			    init() {}
			}
			""",
		)
		_ = try fixture.writeFile(
			relativePath: "Sources/StringLiteral.swift",
			content: """
			let documentation = "@Instantiable(isRoot: true)"
			@Instantiable
			struct StringLiteralOnly {
			    init() {}
			}
			""",
		)
		_ = try fixture.writeFile(
			relativePath: "Sources/MultilineString.swift",
			content: #"""
			let documentation = """
			@Instantiable(isRoot: true)
			"""
			@Instantiable
			struct MultilineStringOnly {
			    init() {}
			}
			"""#,
		)
		_ = try fixture.writeFile(
			relativePath: "Sources/RawString.swift",
			content: ##"""
			let documentation = #"""
			@Instantiable(isRoot: true)
			"""#
			@Instantiable
			struct RawStringOnly {
			    init() {}
			}
			"""##,
		)

		let outputDirectory = fixture.rootDirectory.appendingPathComponent("Output")
		let result = try RootScanner().scan(
			swiftFiles: fixture.swiftFiles.shuffled(),
			relativeTo: fixture.rootDirectory,
			outputDirectory: outputDirectory,
		)

		#expect(result.manifest.dependencyTreeGeneration == [
			RootScanner.Manifest.InputOutputMap(
				inputFilePath: "Sources/ActualRoot.swift",
				outputFilePath: outputDirectory.appendingPathComponent("ActualRoot+SafeDI.swift").path,
			),
		])
		// No #SafeDIConfiguration exists, so no mock entries are created.
		#expect(result.manifest.mockGeneration.isEmpty)
		#expect(try RootScanner.fileContainsRoot(at: actualRoot))
	}

	@Test
	func scan_usesCSVInputPaths_forProjectRootFilesAndDeepParentQualification() throws {
		let fixture = try ScannerFixture()
		defer { fixture.delete() }

		_ = try fixture.writeFile(
			relativePath: "Root.swift",
			content: rootSource(typeName: "TopLevelRoot"),
		)
		_ = try fixture.writeFile(
			relativePath: "Features/A/Root.swift",
			content: rootSource(typeName: "FeatureRoot"),
		)
		_ = try fixture.writeFile(
			relativePath: "Modules/A/Root.swift",
			content: rootSource(typeName: "ModuleRoot"),
		)

		let csvURL = fixture.rootDirectory.appendingPathComponent("InputSwiftFiles.csv")
		try "Modules/A/Root.swift,Root.swift,Features/A/Root.swift".write(
			to: csvURL,
			atomically: true,
			encoding: .utf8,
		)

		let outputDirectory = fixture.rootDirectory.appendingPathComponent("Output")
		let inputFilePaths = try RootScanner.inputFilePaths(from: csvURL)
		let result = try RootScanner().scan(
			inputFilePaths: inputFilePaths,
			relativeTo: fixture.rootDirectory,
			outputDirectory: outputDirectory,
		)

		#expect(result.manifest.dependencyTreeGeneration == [
			.init(
				inputFilePath: "Features/A/Root.swift",
				outputFilePath: outputDirectory.appendingPathComponent("Features_A_Root+SafeDI.swift").path,
			),
			.init(
				inputFilePath: "Modules/A/Root.swift",
				outputFilePath: outputDirectory.appendingPathComponent("Modules_A_Root+SafeDI.swift").path,
			),
			.init(
				inputFilePath: "Root.swift",
				outputFilePath: outputDirectory.appendingPathComponent("Root+SafeDI.swift").path,
			),
		])
		// No #SafeDIConfiguration exists, so no mock entries are created.
		#expect(result.manifest.mockGeneration.isEmpty)
	}

	@Test
	func containsInstantiable_detectsInstantiableAttribute() {
		#expect(RootScanner.containsInstantiable(in: """
		@Instantiable
		struct MyType {}
		"""))
		#expect(RootScanner.containsInstantiable(in: """
		@Instantiable(isRoot: true)
		struct MyRoot {}
		"""))
		#expect(!RootScanner.containsInstantiable(in: """
		struct NotInstantiable {}
		"""))
		#expect(!RootScanner.containsInstantiable(in: """
		// @Instantiable
		struct CommentedOut {}
		"""))
		#expect(!RootScanner.containsInstantiable(in: """
		let docs = "@Instantiable"
		struct StringOnly {}
		"""))
		#expect(!RootScanner.containsInstantiable(in: """
		@InstantiableFactory
		struct WrongName {}
		"""))
	}

	@Test
	func containsRoot_handlesMalformedAttributesAndNestedArguments() {
		#expect(!RootScanner.containsRoot(in: """
		@InstantiableFactory(isRoot: true)
		struct NotARoot {}
		"""))
		#expect(!RootScanner.containsRoot(in: """
		@Instantiable
		struct NotARoot {}
		"""))
		#expect(!RootScanner.containsRoot(in: """
		@Instantiable(isRoot true)
		struct NotARoot {}
		"""))
		#expect(!RootScanner.containsRoot(in: """
		@Instantiable(isRooted: true)
		struct NotARoot {}
		"""))
		#expect(!RootScanner.containsRoot(in: """
		@Instantiable(isRoot: trueish)
		struct NotARoot {}
		"""))
		#expect(!RootScanner.containsRoot(in: """
		@Instantiable(isRoot: true
		struct NotARoot {}
		"""))
		#expect(RootScanner.containsRoot(in: """
		@Instantiable(
		    makeDependency: { value in Dependency.make(value) },
		    options: ["primary": { true }],
		    isRoot: true
		)
		struct ActualRoot {}
		"""))
		#expect(RootScanner.containsRoot(in: """
		@Instantiable(
		    isRoot: true,
		    scope: .shared
		)
		struct EarlyRootClause {}
		"""))
	}

	@Test
	func containsRoot_ignoresNestedCommentsAndEscapedStringDelimiters() {
		let source = [
			"/*",
			"    outer comment",
			"    /* @Instantiable(isRoot: true) */",
			"*/",
			#"let singleLine = "escaped quote: \" @Instantiable(isRoot: true)""#,
			##"let rawString = #"quoted " @Instantiable(isRoot: true) " still raw"#"##,
			#"""
			let multiLine = """
			escaped triple quote: \"""
			@Instantiable(isRoot: true)
			"""
			"""#,
			##"""
			let rawMultiline = #"""
			"""
			@Instantiable(isRoot: true)
			"""#
			"""##,
			"@Instantiable(isRoot: true)",
			"struct ActualRoot {}",
		].joined(separator: "\n")

		#expect(RootScanner.containsRoot(in: source))
	}

	@Test
	func extractAdditionalDirectoriesToInclude_extractsDirectoryPaths() {
		let source = """
		#SafeDIConfiguration(
		    additionalDirectoriesToInclude: ["../OtherModule/Sources", "/absolute/path"]
		)
		"""
		#expect(RootScanner.extractAdditionalDirectoriesToInclude(in: source) == ["../OtherModule/Sources", "/absolute/path"])
	}

	@Test
	func extractAdditionalDirectoriesToInclude_returnsEmpty_whenNoConfiguration() {
		let source = """
		@Instantiable(isRoot: true)
		struct Root {
		    init() {}
		}
		"""
		#expect(RootScanner.extractAdditionalDirectoriesToInclude(in: source).isEmpty)
	}

	@Test
	func extractAdditionalDirectoriesToInclude_returnsEmpty_whenEmptyArray() {
		let source = """
		#SafeDIConfiguration(
		    additionalDirectoriesToInclude: []
		)
		"""
		#expect(RootScanner.extractAdditionalDirectoriesToInclude(in: source).isEmpty)
	}

	@Test
	func extractAdditionalDirectoriesToInclude_ignoresCommentedOutConfig() {
		let source = """
		// #SafeDIConfiguration(
		//     additionalDirectoriesToInclude: ["should/not/match"]
		// )
		"""
		#expect(RootScanner.extractAdditionalDirectoriesToInclude(in: source).isEmpty)
	}

	@Test
	func extractAdditionalDirectoriesToInclude_returnsEmpty_whenConfigHasNoDirectoriesArgument() {
		let source = """
		#SafeDIConfiguration(
		    additionalImportedModules: ["SomeModule"]
		)
		"""
		#expect(RootScanner.extractAdditionalDirectoriesToInclude(in: source).isEmpty)
	}

	@Test
	func extractAdditionalDirectoriesToInclude_returnsEmpty_whenTruncatedBeforeColon() {
		let source = """
		#SafeDIConfiguration(
		    additionalDirectoriesToInclude
		"""
		#expect(RootScanner.extractAdditionalDirectoriesToInclude(in: source).isEmpty)
	}

	@Test
	func extractAdditionalDirectoriesToInclude_returnsEmpty_whenTruncatedBeforeArrayLiteral() {
		let source = """
		#SafeDIConfiguration(
		    additionalDirectoriesToInclude:
		"""
		#expect(RootScanner.extractAdditionalDirectoriesToInclude(in: source).isEmpty)
	}

	@Test
	func extractAdditionalDirectoriesToInclude_returnsEmpty_whenUnmatchedBracket() {
		let source = """
		#SafeDIConfiguration(
		    additionalDirectoriesToInclude: ["unclosed
		"""
		#expect(RootScanner.extractAdditionalDirectoriesToInclude(in: source).isEmpty)
	}

	@Test
	func extractAdditionalDirectoriesToInclude_returnsEmpty_whenMalformedStringLiteral() {
		// The unclosed string literal means the array value cannot be properly extracted.
		let source = """
		#SafeDIConfiguration(
		    additionalDirectoriesToInclude: ["good", "unclosed]
		)
		"""
		#expect(RootScanner.extractAdditionalDirectoriesToInclude(in: source).isEmpty)
	}

	@Test
	func extractAdditionalDirectoriesToInclude_returnsEmpty_whenBracketIsUnmatchedInsideMacroCall() {
		let source = """
		#SafeDIConfiguration(
		    additionalDirectoriesToInclude: [
		)
		"""
		#expect(RootScanner.extractAdditionalDirectoriesToInclude(in: source).isEmpty)
	}

	@Test
	func extractAdditionalDirectoriesToInclude_returnsEmpty_whenArrayHasNoStringLiterals() {
		// Brackets matched but content has no quotes at all.
		let source = """
		#SafeDIConfiguration(
		    additionalDirectoriesToInclude: [someVariable]
		)
		"""
		#expect(RootScanner.extractAdditionalDirectoriesToInclude(in: source).isEmpty)
	}

	@Test
	func extractAdditionalDirectoriesToInclude_ignoresNonMacroText() {
		// Text containing "additionalDirectoriesToInclude" outside the macro call is ignored.
		let source = """
		let additionalDirectoriesToInclude = ["../Wrong/Path"]

		#SafeDIConfiguration(
		    additionalDirectoriesToInclude: ["../Correct/Path"]
		)
		"""
		#expect(RootScanner.extractAdditionalDirectoriesToInclude(in: source) == ["../Correct/Path"])
	}

	@Test
	func extractAdditionalDirectoriesToInclude_returnsEmpty_whenNoDirectoriesArgument() {
		let source = """
		#SafeDIConfiguration()
		"""
		#expect(RootScanner.extractAdditionalDirectoriesToInclude(in: source).isEmpty)
	}

	@Test
	func extractAdditionalDirectoriesToInclude_extractsDirectoryPaths_whenOtherArgumentsPresent() {
		let source = """
		#SafeDIConfiguration(
		    additionalImportedModules: ["SomeModule"],
		    additionalDirectoriesToInclude: ["../Correct/Path"],
		    mockConditionalCompilation: "DEBUG"
		)
		"""
		#expect(RootScanner.extractAdditionalDirectoriesToInclude(in: source) == ["../Correct/Path"])
	}

	@Test
	func extractAdditionalDirectoriesToInclude_returnsEmpty_whenMacroNameIsPrefixOfLongerName() {
		let source = """
		#SafeDIConfigurationHelper(
		    additionalDirectoriesToInclude: ["../Wrong/Path"]
		)
		"""
		#expect(RootScanner.extractAdditionalDirectoriesToInclude(in: source).isEmpty)
	}

	@Test
	func extractAdditionalDirectoriesToInclude_doesNotMatchArgumentLabelPrefix() {
		let source = """
		#SafeDIConfiguration(
		    additionalDirectoriesToIncludeHelper: ["../Wrong/Path"],
		    additionalDirectoriesToInclude: ["../Correct/Path"]
		)
		"""
		#expect(RootScanner.extractAdditionalDirectoriesToInclude(in: source) == ["../Correct/Path"])
	}

	@Test
	func containsGenerateMockTrue_detectsGenerateMockArgument() {
		#expect(RootScanner.containsGenerateMockTrue(in: """
		@Instantiable(generateMock: true)
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_returnsFalse_whenGenerateMockIsFalse() {
		#expect(!RootScanner.containsGenerateMockTrue(in: """
		@Instantiable(generateMock: false)
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_returnsFalse_whenNoGenerateMockArgument() {
		#expect(!RootScanner.containsGenerateMockTrue(in: """
		@Instantiable
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_ignoresCommentsAndStrings() {
		#expect(!RootScanner.containsGenerateMockTrue(in: """
		// @Instantiable(generateMock: true)
		struct MyType {}
		"""))
		#expect(!RootScanner.containsGenerateMockTrue(in: """
		let docs = "@Instantiable(generateMock: true)"
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_ignoresSimilarNames() {
		#expect(!RootScanner.containsGenerateMockTrue(in: """
		@InstantiableFactory(generateMock: true)
		struct MyType {}
		"""))
		#expect(!RootScanner.containsGenerateMockTrue(in: """
		@Instantiable(generateMockery: true)
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_returnsFalse_whenValueIsTrueish() {
		#expect(!RootScanner.containsGenerateMockTrue(in: """
		@Instantiable(generateMock: trueish)
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_handlesClosureBracesInArguments() {
		#expect(RootScanner.containsGenerateMockTrue(in: """
		@Instantiable(
		    someArg: { value in value },
		    generateMock: true
		)
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_returnsFalse_whenLabelHasNoColon() {
		// "generateMock true" without a colon separator.
		#expect(!RootScanner.containsGenerateMockTrue(in: """
		@Instantiable(generateMock true)
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_detectsWhenNotLastArgument() {
		#expect(RootScanner.containsGenerateMockTrue(in: """
		@Instantiable(generateMock: true, isRoot: true)
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_handlesNoSpaceAfterColon() {
		#expect(RootScanner.containsGenerateMockTrue(in: """
		@Instantiable(generateMock:true)
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_returnsFalse_whenValueIsTypeName() {
		#expect(!RootScanner.containsGenerateMockTrue(in: """
		@Instantiable(generateMock: Bool)
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_returnsFalse_whenEqualsUsedInsteadOfColon() {
		#expect(!RootScanner.containsGenerateMockTrue(in: """
		@Instantiable(generateMock = true)
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_returnsFalse_whenClauseIsJustLabel() {
		#expect(!RootScanner.containsGenerateMockTrue(in: """
		@Instantiable(generateMock)
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_detectsMultilineArguments() {
		#expect(RootScanner.containsGenerateMockTrue(in: """
		@Instantiable(
		    generateMock: true
		)
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_detectsMultilineWithOtherArguments() {
		#expect(RootScanner.containsGenerateMockTrue(in: """
		@Instantiable(
		    fulfillingAdditionalTypes: [Foo.self],
		    generateMock: true,
		    mockAttributes: "@MainActor"
		)
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_handlesWhitespaceInsideParens() {
		#expect(RootScanner.containsGenerateMockTrue(in: """
		@Instantiable( generateMock: true )
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_handlesTabSeparator() {
		#expect(RootScanner.containsGenerateMockTrue(in: "@Instantiable(generateMock:\ttrue)\nstruct MyType {}"))
	}

	@Test
	func containsGenerateMockTrue_detectsInFileWithMultipleInstantiables() {
		#expect(RootScanner.containsGenerateMockTrue(in: """
		@Instantiable
		struct TypeA {}
		@Instantiable(generateMock: true)
		struct TypeB {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_returnsFalse_whenOnlyOtherInstantiablesExist() {
		#expect(!RootScanner.containsGenerateMockTrue(in: """
		@Instantiable
		struct TypeA {}
		@Instantiable(isRoot: true)
		struct TypeB {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_ignoresCommentedGenerateMockNextToRealInstantiable() {
		#expect(!RootScanner.containsGenerateMockTrue(in: """
		// @Instantiable(generateMock: true)
		@Instantiable
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_detectsRealOneAfterCommentedOne() {
		#expect(RootScanner.containsGenerateMockTrue(in: """
		// @Instantiable(generateMock: true)
		@Instantiable(generateMock: true)
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_ignoresStringLiteralContainingGenerateMock() {
		#expect(!RootScanner.containsGenerateMockTrue(in: """
		let docs = "@Instantiable(generateMock: true)"
		@Instantiable
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_detectsAfterBlockComment() {
		#expect(RootScanner.containsGenerateMockTrue(in: """
		/*
		@Instantiable(generateMock: true)
		*/
		@Instantiable(generateMock: true)
		struct MyType {}
		"""))
	}

	@Test
	func containsGenerateMockTrue_returnsFalse_whenOnlyInBlockComment() {
		#expect(!RootScanner.containsGenerateMockTrue(in: """
		/*
		@Instantiable(generateMock: true)
		*/
		@Instantiable
		struct MyType {}
		"""))
	}

	@Test
	func scan_createsMockEntryForOptedInType_whenNoConfigExists() throws {
		let fixture = try ScannerFixture()
		defer { fixture.delete() }

		_ = try fixture.writeFile(
			relativePath: "OptedIn.swift",
			content: """
			@Instantiable(generateMock: true)
			struct OptedIn {
			    init() {}
			}
			""",
		)
		_ = try fixture.writeFile(
			relativePath: "Regular.swift",
			content: """
			@Instantiable
			struct Regular {
			    init() {}
			}
			""",
		)

		let outputDirectory = fixture.rootDirectory.appendingPathComponent("Output")
		let result = try RootScanner().scan(
			swiftFiles: fixture.swiftFiles,
			relativeTo: fixture.rootDirectory,
			outputDirectory: outputDirectory,
		)

		// No config exists. Only the opted-in type gets a mock entry.
		#expect(result.manifest.mockGeneration.count == 1)
		#expect(result.manifest.mockGeneration.first?.inputFilePath == "OptedIn.swift")
	}

	@Test
	func containsConfiguration_returnsTrue_whenConfigExistsOutsideComment() {
		#expect(RootScanner.containsConfiguration(in: """
		#SafeDIConfiguration()
		"""))
	}

	@Test
	func containsConfiguration_returnsFalse_whenConfigIsOnlyInComment() {
		#expect(!RootScanner.containsConfiguration(in: """
		// #SafeDIConfiguration()
		struct NotAConfig {}
		"""))
	}

	@Test
	func containsConfiguration_returnsFalse_whenMacroNameIsPrefixOfLongerName() {
		#expect(!RootScanner.containsConfiguration(in: """
		#SafeDIConfigurationHelper()
		"""))
	}

	@Test
	func containsConfiguration_returnsTrue_whenRealConfigAppearsAfterPrefixMatch() {
		#expect(RootScanner.containsConfiguration(in: """
		#SafeDIConfigurationHelper()

		#SafeDIConfiguration()
		"""))
	}

	@Test
	func extractAdditionalDirectoriesToInclude_findsConfigAfterPrefixMatch() {
		let source = """
		#SafeDIConfigurationHelper()

		#SafeDIConfiguration(
		    additionalDirectoriesToInclude: ["../Correct/Path"]
		)
		"""
		#expect(RootScanner.extractAdditionalDirectoriesToInclude(in: source) == ["../Correct/Path"])
	}

	@Test
	func containsConfiguration_returnsFalse_whenNoConfigExists() {
		#expect(!RootScanner.containsConfiguration(in: """
		@Instantiable
		public struct MyType: Instantiable {
		    public init() {}
		}
		"""))
	}

	@Test
	func fileContainsConfiguration_returnsFalse_whenConfigIsOnlyInComment() throws {
		let fixture = try ScannerFixture()
		defer { fixture.delete() }
		let file = try fixture.writeFile(
			relativePath: "CommentOnly.swift",
			content: """
			// #SafeDIConfiguration
			// This file references the config but doesn't declare one.
			struct NotAConfig {}
			""",
		)
		#expect(try !RootScanner.fileContainsConfiguration(at: file))
	}

	@Test
	func scan_includesConfigurationFilePathInManifest() throws {
		let fixture = try ScannerFixture()
		defer { fixture.delete() }

		let configFile = try fixture.writeFile(
			relativePath: "SafeDIConfiguration.swift",
			content: """
			#SafeDIConfiguration()
			""",
		)
		let rootFile = try fixture.writeFile(
			relativePath: "Root.swift",
			content: rootSource(typeName: "ConfigRoot"),
		)

		let outputDirectory = fixture.rootDirectory.appendingPathComponent("Output")
		let result = try RootScanner().scan(
			swiftFiles: [configFile, rootFile],
			relativeTo: fixture.rootDirectory,
			outputDirectory: outputDirectory,
		)

		#expect(result.manifest.configurationFilePaths == ["SafeDIConfiguration.swift"])
	}

	@Test
	func containsRoot_returnsFalse_whenParenIsUnmatched() {
		#expect(!RootScanner.containsRoot(in: "@Instantiable(isRoot: true"))
	}

	@Test
	func scan_inputFilePaths_appliesDirectoryBaseURL_whenBaseURLIsNotDirectory() throws {
		let fixture = try ScannerFixture()
		defer { fixture.delete() }

		_ = try fixture.writeFile(
			relativePath: "Root.swift",
			content: rootSource(typeName: "BaseURLRoot"),
		)

		let outputDirectory = fixture.rootDirectory.appendingPathComponent("Output")

		// Construct a URL that is NOT marked as a directory (using string init,
		// not fileURLWithPath which auto-detects directories on disk).
		let nonDirectoryBaseURL = try #require(URL(string: "file://\(fixture.rootDirectory.path)"))
		#expect(!nonDirectoryBaseURL.hasDirectoryPath)
		let result = try RootScanner().scan(
			inputFilePaths: ["Root.swift"],
			relativeTo: nonDirectoryBaseURL,
			outputDirectory: outputDirectory,
		)
		#expect(!result.manifest.dependencyTreeGeneration.isEmpty)
	}

	@Test
	func scan_relativeToFilesystemRoot_writesAbsolutePathsWithoutLeadingSlash() throws {
		let fixture = try ScannerFixture()
		defer { fixture.delete() }

		let rootFile = try fixture.writeFile(
			relativePath: "Nested/Root.swift",
			content: rootSource(typeName: "NestedRoot"),
		)
		let outputDirectory = fixture.rootDirectory.appendingPathComponent("Output")
		let result = try RootScanner().scan(
			swiftFiles: [rootFile],
			relativeTo: URL(fileURLWithPath: "/"),
			outputDirectory: outputDirectory,
		)

		#expect(result.manifest.dependencyTreeGeneration == [
			.init(
				inputFilePath: String(rootFile.path.dropFirst()),
				outputFilePath: outputDirectory.appendingPathComponent("Root+SafeDI.swift").path,
			),
		])
		// No #SafeDIConfiguration exists, so no mock entries are created.
		#expect(result.manifest.mockGeneration.isEmpty)
	}

	@Test
	func scan_relativeToUnrelatedBase_writesAbsoluteInputPath() throws {
		let fixture = try ScannerFixture()
		defer { fixture.delete() }

		let rootFile = try fixture.writeFile(
			relativePath: "Nested/Root.swift",
			content: rootSource(typeName: "NestedRoot"),
		)
		let unrelatedBase = fixture.rootDirectory
			.deletingLastPathComponent()
			.appendingPathComponent("Unrelated")
		let outputDirectory = fixture.rootDirectory.appendingPathComponent("Output")
		let result = try RootScanner().scan(
			swiftFiles: [rootFile],
			relativeTo: unrelatedBase,
			outputDirectory: outputDirectory,
		)

		#expect(result.manifest.dependencyTreeGeneration == [
			.init(
				inputFilePath: rootFile.path,
				outputFilePath: outputDirectory.appendingPathComponent("Root+SafeDI.swift").path,
			),
		])
		// No #SafeDIConfiguration exists, so no mock entries are created.
		#expect(result.manifest.mockGeneration.isEmpty)
	}

	@Test
	func command_run_writesManifest() throws {
		let fixture = try ScannerFixture()
		defer { fixture.delete() }

		_ = try fixture.writeFile(
			relativePath: "Root.swift",
			content: rootSource(typeName: "CommandRoot"),
		)

		let inputSourcesFile = fixture.rootDirectory.appendingPathComponent("InputSwiftFiles.csv")
		try "Root.swift".write(to: inputSourcesFile, atomically: true, encoding: .utf8)
		let outputDirectory = fixture.rootDirectory.appendingPathComponent("Output")
		let manifestFile = fixture.rootDirectory.appendingPathComponent("SafeDIManifest.json")

		var command = SafeDIRootScannerCommand()
		command.inputSourcesFile = inputSourcesFile.path
		command.projectRoot = fixture.rootDirectory.path
		command.outputDirectory = outputDirectory.path
		command.manifestFile = manifestFile.path
		try command.run()

		let manifestContent = try String(contentsOf: manifestFile, encoding: .utf8)
		#expect(manifestContent.contains("\"dependencyTreeGeneration\""))
		#expect(manifestContent.contains("\"mockGeneration\""))
		#expect(manifestContent.contains("Root+SafeDI.swift"))
		// No #SafeDIConfiguration exists, so no mock entries are created.
		#expect(!manifestContent.contains("Root+SafeDIMock.swift"))
	}
}

private func rootSource(typeName: String) -> String {
	"""
	@Instantiable(isRoot: true)
	struct \(typeName) {
	    init(dep: Dep) {
	        self.dep = dep
	    }
	    @Instantiated let dep: Dep
	}
	@Instantiable
	struct Dep {
	    init() {}
	}
	"""
}

private final class ScannerFixture {
	init() throws {
		rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
	}

	let rootDirectory: URL
	private(set) var swiftFiles = [URL]()

	@discardableResult
	func writeFile(
		relativePath: String,
		content: String,
	) throws -> URL {
		let fileURL = rootDirectory.appendingPathComponent(relativePath)
		try FileManager.default.createDirectory(
			at: fileURL.deletingLastPathComponent(),
			withIntermediateDirectories: true,
		)
		try content.write(to: fileURL, atomically: true, encoding: .utf8)
		swiftFiles.append(fileURL)
		return fileURL
	}

	func delete() {
		try? FileManager.default.removeItem(at: rootDirectory)
	}
}
