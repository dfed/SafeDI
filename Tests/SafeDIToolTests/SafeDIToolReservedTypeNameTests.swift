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

/// Types the `@Instantiable` macro does not see whose names begin with a prefix SafeDI reserves for the types it
/// generates: declared in a plain extension of a seam or of a type with a public mock, or a plain type anywhere in the
/// module's own files, in any clause of any `#if` block. Generated code declares types of those names beside the person’s,
/// so `generate` rejects each such declaration before it builds any tree. Every fixture is one the macro accepts, since
/// the macro sees none of these declarations.
struct SafeDIToolReservedTypeNameTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: A plain extension of a type whose code SafeDI generates

	@Test(arguments: [[String](), ["DEBUG"]])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtName_whenPlainExtensionOfPublicMockTypeDeclaresMockScopeNamedType(activeCompilationConditions: [String]) async {
		// A public mock of `Panel` declares `Panel.SafeDIMockScope_Service` for its hole of type `Service`, which this
		// declaration redeclares. A reserved name is reserved under every condition, as the macro reserves it, so it is
		// reported where the mock condition is inactive too.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Panel.swift"]):11:17: error: The type name `SafeDIMockScope_Service` begins with `SafeDIMockScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIMockScope_`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: .public)
					public final class Panel: Instantiable {
					    public init(service: Service) {
					        self.service = service
					    }

					    @Instantiated let service: Service
					}

					extension Panel {
					    public enum SafeDIMockScope_Service {}
					}
					""",
					"""
					@Instantiable
					public final class Service: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				activeCompilationConditions: activeCompilationConditions,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesPublicMock_whenPlainExtensionOfPublicMockTypeDeclaresRenamedType() async throws {
		// The remedy: the type renamed so that its name begins with no reserved prefix.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public final class Panel: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}

				extension Panel {
				    public enum ServiceScope {}
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles.keys.sorted() == ["Panel+SafeDIMock.swift"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtEachNameInSourceOrder_whenPlainExtensionOfSeamDeclaresScopeAndBuilderNamedTypes() async {
		// A seam declares `SafeDIScope_<Stem>` enums in its extension, and `__safeDI_Builder` structs inside them.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Api.swift"]):11:17: error: The type name `SafeDIScope_Client` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.
			\(fixtures["Api.swift"]):12:19: error: The type name `__safeDI_Builder` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `__safeDI_`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Api: Instantiable {
					    public init(client: Client) {
					        self.client = client
					    }

					    @Instantiated let client: Client
					}

					extension Api {
					    public enum SafeDIScope_Client {}
					    public struct __safeDI_Builder {}
					}
					""",
					"""
					@Instantiable
					public final class Client: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesSeam_whenPlainExtensionOfSeamDeclaresRenamedTypes() async throws {
		// The remedy: each type renamed so that its name begins with no reserved prefix.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Api: Instantiable {
				    public init(client: Client) {
				        self.client = client
				    }

				    @Instantiated let client: Client
				}

				extension Api {
				    public enum ClientScope {}
				    public struct Builder {}
				}
				""",
				"""
				@Instantiable
				public final class Client: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles?.keys.sorted() == ["Api+SafeDI.swift"])
	}

	// MARK: A plain type

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtDeclaration_whenTopLevelPlainTypeIsNamedWithSeamScopePrefix() async {
		// A seam’s enum `SafeDIScope_Service` would hide this type inside the seam’s extension. The seam mentions it
		// through a type alias, which the macro accepts; a mention spelled with the reserved name is the macro’s to report.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):10:15: error: The type name `SafeDIScope_Service` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    public init(service: ServiceAlias) {
					        self.service = service
					    }

					    @Forwarded let service: ServiceAlias
					}

					public struct SafeDIScope_Service {}

					public typealias ServiceAlias = SafeDIScope_Service
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtEachDeclaration_whenPlainTypesOfEveryKindNestedTwoDeepBeginWithReservedPrefixes() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Root.swift"]):8:16: error: The type name `SafeDIScope_A` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.
			\(fixtures["Root.swift"]):9:15: error: The type name `SafeDISendableScope_B` begins with `SafeDISendableScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDISendableScope_`.
			\(fixtures["Root.swift"]):10:15: error: The type name `SafeDIMockScope_C` begins with `SafeDIMockScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIMockScope_`.
			\(fixtures["Root.swift"]):11:14: error: The type name `SafeDISendableMockScope_D` begins with `SafeDISendableMockScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDISendableMockScope_`.
			\(fixtures["Root.swift"]):12:18: error: The type name `__safeDI_E` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `__safeDI_`.
			\(fixtures["Root.swift"]):13:19: error: The type name `SafeDIScope_F` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.
			\(fixtures["Root.swift"]):18:15: error: The type name `SafeDIMockScope_G` begins with `SafeDIMockScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIMockScope_`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init() {}
					}

					enum Outer {
					    enum Middle {
					        struct SafeDIScope_A {}
					        class SafeDISendableScope_B {}
					        actor SafeDIMockScope_C {}
					        enum SafeDISendableMockScope_D {}
					        protocol __safeDI_E {}
					        typealias SafeDIScope_F = Int
					    }
					}

					protocol Holder {
					    typealias SafeDIMockScope_G = Int
					    func hold()
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesRoot_whenPlainTypesOfEveryKindAreRenamed() async throws {
		// The remedy: each type renamed so that its name begins with no reserved prefix.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init() {}
				}

				enum Outer {
				    enum Middle {
				        struct ScopeA {}
				        class SendableScopeB {}
				        actor MockScopeC {}
				        enum SendableMockScopeD {}
				        protocol BuilderE {}
				        typealias ScopeF = Int
				    }
				}

				protocol Holder {
				    typealias MockScopeG = Int
				    func hold()
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles?.keys.sorted() == ["Root+SafeDI.swift"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtEachDeclaration_whenProtocolsDeclareAssociatedTypesWithReservedNames() async {
		// An associated type is declared directly in a protocol's body, in each clause of an `#if` block in that body,
		// and in a protocol inside an outermost `#if` block, which a walk of the block's clauses records.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Root.swift"]):7:20: error: The type name `SafeDIScope_Value` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.
			\(fixtures["Root.swift"]):9:20: error: The type name `SafeDIMockScope_Element` begins with `SafeDIMockScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIMockScope_`.
			\(fixtures["Root.swift"]):11:20: error: The type name `__safeDI_Element` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `__safeDI_`.
			\(fixtures["Root.swift"]):17:20: error: The type name `SafeDISendableScope_Item` begins with `SafeDISendableScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDISendableScope_`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init() {}
					}

					protocol Holder {
					    associatedtype SafeDIScope_Value
					    #if DEBUG
					    associatedtype SafeDIMockScope_Element
					    #else
					    associatedtype __safeDI_Element
					    #endif
					}

					#if FOO
					protocol Store {
					    associatedtype SafeDISendableScope_Item
					}
					#endif
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesRoot_whenProtocolsDeclareRenamedAssociatedTypes() async throws {
		// The remedy: each associated type renamed so that its name begins with no reserved prefix.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init() {}
				}

				protocol Holder {
				    associatedtype Value
				    #if DEBUG
				    associatedtype MockElement
				    #else
				    associatedtype Element
				    #endif
				}

				#if FOO
				protocol Store {
				    associatedtype Item
				}
				#endif
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles?.keys.sorted() == ["Root+SafeDI.swift"])
	}

	@Test(arguments: ReservedTypeNameRun.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtDeclaration_whenFileWithoutSafeDIMarkerDeclaresReservedNameInPlainExtension(run: ReservedTypeNameRun) async {
		// The file holds no SafeDI marker, and names no type the module keeps after a type keyword, so only the reserved
		// name gets it parsed.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(run.path(in: fixtures, of: "Panel+Scope.swift")):2:10: error: The type name `SafeDIMockScope_X` begins with `SafeDIMockScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIMockScope_`.
			"""
		}) {
			try await run.generate(
				swiftFileContent: [
					"""
					@Instantiable
					public final class Panel: Instantiable {
					    public init() {}
					}
					""",
				],
				swiftFileContentByFilePath: [
					"Panel+Scope.swift": """
					extension Panel {
					    enum SafeDIMockScope_X {}
					}
					""",
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: ReservedTypeNameRun.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_succeeds_whenFileWithoutSafeDIMarkerDeclaresRenamedTypeInPlainExtension(run: ReservedTypeNameRun) async throws {
		// The remedy: the type renamed so that its name begins with no reserved prefix.
		let output = try await run.generate(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Panel: Instantiable {
				    public init() {}
				}
				""",
			],
			swiftFileContentByFilePath: [
				"Panel+Scope.swift": """
				extension Panel {
				    enum MockScopeX {}
				}
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings.isEmpty)
	}

	@Test(arguments: ReservedTypeNameRun.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtDeclaration_whenFileWithoutSafeDIMarkerDeclaresAssociatedTypeWithReservedName(run: ReservedTypeNameRun) async {
		// The file holds no SafeDI marker, and names no type the module keeps after a type keyword, so only the reserved
		// name of the associated type gets it parsed.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(run.path(in: fixtures, of: "Holder.swift")):2:20: error: The type name `SafeDIScope_Value` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.
			"""
		}) {
			try await run.generate(
				swiftFileContent: [
					"""
					@Instantiable
					public final class Panel: Instantiable {
					    public init() {}
					}
					""",
				],
				swiftFileContentByFilePath: [
					"Holder.swift": """
					protocol Holder {
					    associatedtype SafeDIScope_Value
					}
					""",
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: ReservedTypeNameRun.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_succeeds_whenFileWithoutSafeDIMarkerDeclaresRenamedAssociatedType(run: ReservedTypeNameRun) async throws {
		// The remedy: the associated type renamed so that its name begins with no reserved prefix.
		let output = try await run.generate(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Panel: Instantiable {
				    public init() {}
				}
				""",
			],
			swiftFileContentByFilePath: [
				"Holder.swift": """
				protocol Holder {
				    associatedtype Value
				}
				""",
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.warnings.isEmpty)
	}

	// MARK: Conditional compilation

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtDeclarationInEveryClause_whenClausesTheConditionsSkipDeclareReservedNames() async {
		// `FOO` and `BAR` are inactive, and the `#else` beside mock-only content is skipped where the mock condition is
		// active as where it is not: a reserved name is reserved under every condition, as the macro reserves it.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Root.swift"]):7:8: error: The type name `SafeDIScope_A` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.
			\(fixtures["Root.swift"]):11:12: error: The type name `SafeDISendableScope_B` begins with `SafeDISendableScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDISendableScope_`.
			\(fixtures["Root.swift"]):24:8: error: The type name `SafeDIMockScope_C` begins with `SafeDIMockScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIMockScope_`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init() {}
					}

					#if FOO
					struct SafeDIScope_A {}
					#else
					enum Space {
					    #if BAR
					    struct SafeDISendableScope_B {}
					    #endif
					}
					#endif

					#if DEBUG
					@Instantiable(mockOnly: true)
					public final class Preview: Instantiable {
					    public static func mock() -> Preview {
					        Preview()
					    }
					}
					#else
					struct SafeDIMockScope_C {}
					#endif
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: ReservedTypeNameRun.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSameError_whenGenerateConditionsSelectOtherClausesThanScanConditions(run: ReservedTypeNameRun) async {
		// Scan reads the file with `FOO` inactive and caches what it found; `generate`, told by the build settings that
		// `FOO` is active, walks the file again, and reports the declaration scan recorded in the clause it now skips.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(run.path(in: fixtures, of: "Root.swift")):21:8: error: The type name `SafeDIScope_Screen` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.
			"""
		}) {
			try await run.generate(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(screen: Screen) {
					        self.screen = screen
					    }

					    @Instantiated let screen: Screen
					}

					#if FOO
					@Instantiable
					public final class Screen: Instantiable {
					    public init() {}
					}
					#else
					@Instantiable
					public final class Screen: Instantiable {
					    public init() {}
					}

					struct SafeDIScope_Screen {}
					#endif
					""",
				],
				buildSettingArguments: ["--build-setting-active-compilation-conditions=[FOO]", "--build-setting-other-swift-flags=[]"],
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Spelling

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSpellingNameWithoutBackticks_whenReservedNameIsWrittenInBackticks() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Root.swift"]):6:8: error: The type name `SafeDIScope_Api` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init() {}
					}

					struct `SafeDIScope_Api` {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_succeeds_whenPlainTypeNamesOnlyResembleReservedPrefixes() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init() {}
				}

				struct SafeDIScopeX {}
				struct SafeDIScope {}
				struct SafeDISendableScopeApi {}
				struct _safeDI_Builder {}
				struct __SafeDI_Builder {}
				struct safeDIScope_Api {}
				struct MySafeDIScope_Api {}
				struct Detail_Scope {}
				struct detailBuilder_Values {}
				struct SafeDIMockScopeX {}
				struct SafeDISendableMockScopeApi {}
				struct SAFEDIMOCKSCOPE_Api {}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles?.keys.sorted() == ["Root+SafeDI.swift"])
	}

	// MARK: Order

	@Test(arguments: ReservedTypeNameRun.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorsInPathLineAndColumnOrder_whenFilesDeclareReservedNamesOutOfNameAndLineOrder(run: ReservedTypeNameRun) async {
		// Path order, name order and line order are three different permutations of the six declarations, and the files
		// are parsed in parallel: only the source order of path, line and column decides the order of the errors.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(run.path(in: fixtures, of: "A.swift")):1:8: error: The type name `SafeDIScope_F` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.
			\(run.path(in: fixtures, of: "A.swift")):1:33: error: The type name `SafeDIScope_C` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.
			\(run.path(in: fixtures, of: "B.swift")):1:8: error: The type name `SafeDIScope_E` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.
			\(run.path(in: fixtures, of: "B.swift")):2:8: error: The type name `SafeDIScope_A` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.
			\(run.path(in: fixtures, of: "C.swift")):1:8: error: The type name `SafeDIScope_D` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.
			\(run.path(in: fixtures, of: "C.swift")):2:8: error: The type name `SafeDIScope_B` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.
			"""
		}) {
			try await run.generate(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init() {}
					}
					""",
				],
				swiftFileContentByFilePath: [
					"A.swift": "struct SafeDIScope_F {}; struct SafeDIScope_C {}\n",
					"B.swift": "struct SafeDIScope_E {}\nstruct SafeDIScope_A {}\n",
					"C.swift": "struct SafeDIScope_D {}\nstruct SafeDIScope_B {}\n",
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Another module

	@Test(arguments: [MultiModuleIntegration.moduleInfo, .swiftPackagePlugin])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorInDeclaringModuleOnly_whenModuleDeclaresReservedName(integration: MultiModuleIntegration) async {
		// `Feature`’s run reports its own declaration; `App`, which depends on it, never runs.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let path = switch integration {
			case .moduleInfo:
				fixtures["Feature"]!["Service.swift"]
			case .swiftPackagePlugin:
				NormalizedFilePath(fixtures["Feature"]!.compilerPath(of: "Service.swift")).path
			}
			return """
			\(path):6:15: error: The type name `SafeDIScope_Service` begins with `SafeDIScope_`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `SafeDIScope_`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
					@Instantiable(generateMock: true)
					public final class Service: Instantiable {
					    public init() {}
					}

					public struct SafeDIScope_Service {}
					"""]),
					ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Root.swift": """
					import Feature

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(service: Service) {
					        self.service = service
					    }

					    @Instantiated let service: Service
					}
					"""], dependencies: ["Feature"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [MultiModuleIntegration.moduleInfo, .swiftPackagePlugin])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNothingInDependentModule_whenModuleItDependsOnDeclaresReservedNameWithoutRunningSafeDI(integration: MultiModuleIntegration) async throws {
		// `Feature` runs no SafeDI. Under the SwiftPM plugin, `App`’s run reads `Feature`’s files, among them the
		// declaration, and reports nothing: a declaration is reported only by its own module’s run. Under Bazel and Tuist,
		// `App` reads no `.safedi` of `Feature`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
				@Instantiable
				public final class Service: Instantiable {
				    public init() {}
				}

				public struct SafeDIScope_Service {}
				"""], runsSafeDI: false),
				ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Root.swift": """
				import Feature

				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init() {}
				}
				"""], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["App"]?.generateRan == true)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesModuleInfoOfDeclarationsWithoutReservedNameOnlyFile_whenOwnFileNamesReservedPrefixOnlyInComment() async throws {
		// The file holds no SafeDI marker, and names a reserved prefix after a type keyword only in a comment, so it is
		// parsed for a reserved name and declares none. It contributes nothing else: `Service.Nested`, which a parse for the
		// module’s kept names would read, stays out of the `.safedi`, which is what it would hold without the reserved word.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "pkg", swiftFileContentByFilePath: [
					"Service.swift": """
					@Instantiable
					public final class Service: Instantiable {
					    public init() {}
					}
					""",
					"Service+Nested.swift": """
					// Naming a struct SafeDIScope_Service would collide with a seam’s enum.
					extension Service {
					    public struct Nested {}
					}
					""",
				]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["Feature"]?.moduleInfoFile?.module.plainTypeDeclarations.map(\.typeDescription.asSource) == [])
	}

	// MARK: Private

	private var filesToDelete: [URL]
}

/// How a test runs `generate`: parsing every file itself, as Bazel and Tuist run it; reading scan's cache, as the SwiftPM
/// plugin does; or reading the cache of a scan the plugin ran while it planned the build, which names files as the build
/// system reported them.
enum ReservedTypeNameRun: CaseIterable, Sendable {
	case freshParse
	case scanCache
	case scanWhilePlanning

	/// Runs `generate` on the fixtures this way.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate(
		swiftFileContent: [String],
		swiftFileContentByFilePath: [String: String] = [:],
		buildSettingArguments: [String] = [],
		filesToDelete: inout [URL],
	) async throws -> TestOutput {
		switch self {
		case .freshParse:
			try await executeSafeDIToolTest(swiftFileContent: swiftFileContent, swiftFileContentByFilePath: swiftFileContentByFilePath, buildCombinedOutput: true, filesToDelete: &filesToDelete, buildSettingArguments: buildSettingArguments)
		case .scanCache:
			try await executeSafeDIToolTest(swiftFileContent: swiftFileContent, swiftFileContentByFilePath: swiftFileContentByFilePath, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete, buildSettingArguments: buildSettingArguments)
		case .scanWhilePlanning:
			try await executeSafeDIToolTest(swiftFileContent: swiftFileContent, swiftFileContentByFilePath: swiftFileContentByFilePath, pluginInvocation: .scanWhilePlanning(reportsFixtureDirectoryThroughSymbolicLink: false), filesToDelete: &filesToDelete, buildSettingArguments: buildSettingArguments)
		}
	}

	/// The path of the fixture `fileName` as `generate`'s diagnostics spell it this way.
	func path(in fixtures: FixturePaths, of fileName: String) -> String {
		switch self {
		case .freshParse, .scanCache:
			fixtures[fileName]
		case .scanWhilePlanning:
			NormalizedFilePath(fixtures.compilerPath(of: fileName)).path
		}
	}
}
