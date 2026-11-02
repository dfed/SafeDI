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
import Testing
@testable import SafeDITool

/// SafeDITool keys a declaration's dependencies by label where it generates code for a production root's tree or a
/// mock root's tree. Every build runs it before the compiler expands the `@Instantiable` macro, which rejects the ways
/// one clause can repeat a label, so SafeDITool reports a repeated label in a declaration a tree reaches with a plain
/// error at the declaration rather than trap. These fixtures are rejected by the macro, or, for a dependency declared
/// in each clause of a platform `#if`, accepted by the macro and the compiler alike.
struct SafeDIToolRepeatedDependencyLabelTests: ~Copyable {
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
	mutating func generate_throwsErrorAtLaterParameter_whenInstantiateNamesTwoDependencyParametersUnderscore() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Service.swift"]):3:52: error: `Service` has more than one dependency named `_`. SafeDI names an `instantiate(…)` dependency by its parameter’s name, and the @Instantiable macro rejects a dependency parameter named `_`. Name the parameter.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable
					public final class First: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Second: Instantiable {
					    public init() {}
					}
					""",
				],
				swiftFileContentByFilePath: [
					"Service.swift": """
					@Instantiable(generateMock: true)
					extension Service: Instantiable {
					    public static func instantiate(first _: First, second _: Second) -> Service { Service() }
					}

					public final class Service {
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
	mutating func generate_throwsErrorAtLaterProperty_whenTwoDependencyNamesAreEncodedDifferently() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Service.swift"]):8:5: error: `Service` has dependencies `caf\u{E9}` (U+0063 U+0061 U+0066 U+00E9) and `cafe\u{301}` (U+0063 U+0061 U+0066 U+0065 U+0301), which look the same but are encoded differently, so SafeDI cannot tell them apart. The @Instantiable macro rejects such names. Rename one of them.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Service: Instantiable {
					    public init(caf\u{E9}: First, cafe\u{301}: Second) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let caf\u{E9}: First
					    @Instantiated let cafe\u{301}: Second
					}
					""",
					"""
					@Instantiable
					public final class First: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Second: Instantiable {
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
	mutating func generate_throwsErrorAtLaterDeclaration_whenDependencyIsDeclaredInEachClauseOfPlatformCondition() async {
		// Both the compiler and the macro accept this, because each compilation sees one clause.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Feature.swift"]):10:5: error: `Feature` declares the dependency `tracker` more than once. SafeDI reads every clause of an `#if` that only the compiler decides, such as `#if os(iOS)`, so a dependency declared in each clause counts twice. Declare it once, outside the `#if`.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true, generateMock: true)
					public final class Root: Instantiable {
					    public init(feature: Feature, tracker: Tracker) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let feature: Feature
					    @Instantiated let tracker: Tracker
					}
					""",
					"""
					@Instantiable
					public final class Feature: Instantiable {
					    public init(tracker: Tracker) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    #if os(macOS)
					    @Received nonisolated let tracker: Tracker
					    #else
					    @Received let tracker: Tracker
					    #endif
					}
					""",
					"""
					@Instantiable
					public final class Tracker: Instantiable {
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
	mutating func generate_throwsErrorAtEachRepeatedLabel_whenOneDeclarationRepeatsTwoLabels() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Feature.swift"]):10:5: error: `Feature` declares the dependency `tracker` more than once. SafeDI reads every clause of an `#if` that only the compiler decides, such as `#if os(iOS)`, so a dependency declared in each clause counts twice. Declare it once, outside the `#if`.
				\(fixtures["Feature.swift"]):14:5: error: `Feature` has dependencies `caf\u{E9}` (U+0063 U+0061 U+0066 U+00E9) and `cafe\u{301}` (U+0063 U+0061 U+0066 U+0065 U+0301), which look the same but are encoded differently, so SafeDI cannot tell them apart. The @Instantiable macro rejects such names. Rename one of them.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public final class Feature: Instantiable {
					    public init(tracker: Tracker, caf\u{E9}: First, cafe\u{301}: Second) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    #if os(macOS)
					    @Received nonisolated let tracker: Tracker
					    #else
					    @Received let tracker: Tracker
					    #endif

					    @Instantiated let caf\u{E9}: First
					    @Instantiated let cafe\u{301}: Second
					}
					""",
					"""
					@Instantiable
					public final class First: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Second: Instantiable {
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
	mutating func generate_throwsErrorsInSourceOrder_whenDeclarationsInTwoFilesEachRepeatALabel() async {
		// The file that sorts first declares the type whose name sorts last, so the order is not the names' order.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["A.swift"]):8:5: error: `Zebra` has dependencies `caf\u{E9}` (U+0063 U+0061 U+0066 U+00E9) and `cafe\u{301}` (U+0063 U+0061 U+0066 U+0065 U+0301), which look the same but are encoded differently, so SafeDI cannot tell them apart. The @Instantiable macro rejects such names. Rename one of them.
				\(fixtures["B.swift"]):3:52: error: `Alpha` has more than one dependency named `_`. SafeDI names an `instantiate(…)` dependency by its parameter’s name, and the @Instantiable macro rejects a dependency parameter named `_`. Name the parameter.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable
					public final class First: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Second: Instantiable {
					    public init() {}
					}
					""",
				],
				swiftFileContentByFilePath: [
					"A.swift": """
					@Instantiable(generateMock: true)
					public final class Zebra: Instantiable {
					    public init(caf\u{E9}: First, cafe\u{301}: Second) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let caf\u{E9}: First
					    @Instantiated let cafe\u{301}: Second
					}
					""",
					"B.swift": """
					@Instantiable(generateMock: true)
					extension Alpha: Instantiable {
					    public static func instantiate(first _: First, second _: Second) -> Alpha { Alpha() }
					}

					public final class Alpha {
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
	mutating func generate_succeeds_whenNoTreeReachesDeclarationThatRepeatsALabel() async throws {
		// Only hand-written code constructs `Feature`, so no generated code keys its dependencies, and nothing traps.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(tracker: Tracker) {
				        self.tracker = tracker
				    }

				    @Instantiated let tracker: Tracker
				}
				""",
				"""
				@Instantiable
				public final class Feature: Instantiable {
				    public init(tracker: Tracker) {
				        self.tracker = tracker
				    }

				    #if os(macOS)
				    /// The tracker, which macOS reports to.
				    @Received let tracker: Tracker
				    #else
				    @Received let tracker: Tracker
				    #endif
				}
				""",
				"""
				@Instantiable
				public final class Tracker: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles?["Root+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        let tracker = Tracker()
		        self.init(tracker: tracker)
		    }
		}
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
