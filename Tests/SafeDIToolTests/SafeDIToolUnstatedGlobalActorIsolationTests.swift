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

/// A declaration SafeDI generates – a root’s `init()`, a seam’s initializers, a `mock()` – has the type’s isolation, the
/// one its attribute text spells, or, where that text is empty in a module whose `#SafeDIConfiguration` declares
/// `defaultIsolation: MainActor.self`, `@MainActor`. A `@MainActor` callee of a type that states no isolation makes
/// generated code that does not compile, so `generate` reports each generated declaration whose isolation nothing states,
/// at the type’s `@Instantiable` attribute, with a fix-it that adds `@MainActor` to the text. The module’s setting
/// decides it, so the check is the tool’s.
struct SafeDIToolUnstatedGlobalActorIsolationTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – A module that declares no default isolation

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAddingGeneratedInitializerAttributes_whenRootInitializerIsMainActor() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Root.swift"]):1:1: error: `Root`’s initializer is `@MainActor`, and the `init()` SafeDI generates for this root calls it, so that `init()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedInitializerAttributes`.
			\(fixtures["Root.swift"]):1:1-1:28: fixit: @Instantiable(isRoot: true, generatedInitializerAttributes: \\"@MainActor\\")
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @MainActor public init(presenter: Presenter) {
					        self.presenter = presenter
					    }

					    @Instantiated private let presenter: Presenter
					}
					""",
					Self.presenter,
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorForEachDeclarationWithOneFixItAddingToBothTexts_whenRootInitializerIsMainActorAndAttributesStateNoIsolation() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Root.swift"]):1:1: error: `Root`’s initializer is `@MainActor`, and the `init()` SafeDI generates for this root calls it, so that `init()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedInitializerAttributes`.
			\(fixtures["Root.swift"]):1:1-1:107: fixit: @Instantiable(isRoot: true, generatedInitializerAttributes: \\"@MainActor @available(macOS 14, *)\\", mockAttributes: \\"@MainActor\\", generateMock: true)
			\(fixtures["Root.swift"]):1:1: error: `Root`’s initializer is `@MainActor`, and the `mock()` SafeDI generates calls it, so that `mock()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `mockAttributes`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true, generatedInitializerAttributes: "@available(macOS 14, *)", generateMock: true)
					public final class Root: Instantiable {
					    @MainActor public init(presenter: Presenter) {
					        self.presenter = presenter
					    }

					    @Instantiated private let presenter: Presenter
					}
					""",
					Self.presenter,
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorReplacingNonisolated_whenGeneratedInitializerAttributesStateNonisolated() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Root.swift"]):1:1: error: `Root`’s initializer is `@MainActor`, and the `init()` SafeDI generates for this root calls it, so that `init()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedInitializerAttributes`.
			\(fixtures["Root.swift"]):1:1-1:75: fixit: @Instantiable(isRoot: true, generatedInitializerAttributes: \\"@MainActor\\")
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true, generatedInitializerAttributes: "nonisolated")
					public final class Root: Instantiable {
					    @MainActor public init(presenter: Presenter) {
					        self.presenter = presenter
					    }

					    @Instantiated private let presenter: Presenter
					}
					""",
					Self.presenter,
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: ["nonisolated public final class", "@preconcurrency public final class"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenRootTypeStatesIsolationInitializerCannotBeCalledFrom(declarationIntroducer: String) async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Root.swift"]):1:1: error: `Root`’s initializer is `@MainActor`, and the `init()` SafeDI generates for this root calls it, so that `init()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedInitializerAttributes`.
			\(fixtures["Root.swift"]):1:1-1:28: fixit: @Instantiable(isRoot: true, generatedInitializerAttributes: \\"@MainActor\\")
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					\(declarationIntroducer) Root: Instantiable {
					    @MainActor public init(presenter: Presenter) {
					        self.presenter = presenter
					    }

					    @Instantiated private let presenter: Presenter
					}
					""",
					Self.presenter,
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenRootInitializerSpellsModuleQualifiedMainActor() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Root.swift"]):1:1: error: `Root`’s initializer is `@MainActor`, and the `init()` SafeDI generates for this root calls it, so that `init()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedInitializerAttributes`.
			\(fixtures["Root.swift"]):1:1-1:28: fixit: @Instantiable(isRoot: true, generatedInitializerAttributes: \\"@MainActor\\")
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @_Concurrency.MainActor public init(presenter: Presenter) {
					        self.presenter = presenter
					    }

					    @Instantiated private let presenter: Presenter
					}
					""",
					Self.presenter,
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorForSeamInitializersAndMock_whenSeamInitializerIsMainActor() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Feature.swift"]):1:1: error: `Feature`’s initializer is `@MainActor`, and the initializers SafeDI generates for this type with `generateDependencyTree: true` call it, so they must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedInitializerAttributes`.
			\(fixtures["Feature.swift"]):1:1-1:64: fixit: @Instantiable(generateDependencyTree: true, generatedInitializerAttributes: \\"@MainActor\\", mockAttributes: \\"@MainActor\\", generateMock: true)
			\(fixtures["Feature.swift"]):1:1: error: `Feature`’s initializer is `@MainActor`, and the `mock()` SafeDI generates calls it, so that `mock()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `mockAttributes`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateDependencyTree: true, generateMock: true)
					public final class Feature: Instantiable {
					    @MainActor public init(presenter: Presenter) {
					        self.presenter = presenter
					    }

					    @Instantiated private let presenter: Presenter
					}
					""",
					Self.presenter,
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorsWithOneFixItAddingGeneratedAttributesOnce_whenSeamInitializerAndMockAreMainActorAndGeneratedAttributesStateNoIsolation() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Feature.swift"]):1:1: error: `Feature`’s initializer is `@MainActor`, and the initializers SafeDI generates for this type with `generateDependencyTree: true` call it, so they must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedAttributes`.
			\(fixtures["Feature.swift"]):1:1-1:112: fixit: @Instantiable(generateDependencyTree: true, generatedAttributes: \\"@MainActor @available(macOS 14, *)\\", generateMock: true)
			\(fixtures["Feature.swift"]):1:1: error: `Feature`’s initializer is `@MainActor`, and the `mock()` SafeDI generates calls it, so that `mock()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedAttributes`.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateDependencyTree: true, generatedAttributes: "@available(macOS 14, *)", generateMock: true)
					public final class Feature: Instantiable {
					    @MainActor public init(presenter: Presenter) {
					        self.presenter = presenter
					    }

					    @Instantiated private let presenter: Presenter
					}
					""",
					Self.presenter,
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAddingMockAttributesBeforeGenerateMock_whenMockedInitializerIsMainActor() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Presenter.swift"]):1:1: error: `Presenter`’s initializer is `@MainActor`, and the `mock()` SafeDI generates calls it, so that `mock()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `mockAttributes`.
			\(fixtures["Presenter.swift"]):1:1-1:34: fixit: @Instantiable(mockAttributes: \\"@MainActor\\", generateMock: true)
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Presenter: Instantiable {
					    @MainActor public init() {}
					}
					""",
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAddingToGeneratedAttributes_whenPublicMockedInitializerIsMainActorAndGeneratedAttributesStateNoIsolation() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Presenter.swift"]):1:1: error: `Presenter`’s initializer is `@MainActor`, and the `mock()` SafeDI generates calls it, so that `mock()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedAttributes`.
			\(fixtures["Presenter.swift"]):1:1-1:85: fixit: @Instantiable(generatedAttributes: \\"@MainActor @available(macOS 14, *)\\", generateMock: .public)
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generatedAttributes: "@available(macOS 14, *)", generateMock: .public)
					public struct Presenter: Instantiable {
					    @MainActor public init() {}
					}
					""",
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingHandWrittenMock_whenCustomMockIsMainActor() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Presenter.swift"]):1:1: error: The hand-written mock `customMock(…)` is `@MainActor`, and the `mock()` SafeDI generates calls it, so that `mock()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `mockAttributes`.
			\(fixtures["Presenter.swift"]):1:1-1:64: fixit: @Instantiable(mockAttributes: \\"@MainActor\\", generateMock: true, customMockName: \\"customMock\\")
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true, customMockName: "customMock")
					public struct Presenter: Instantiable {
					    public init() {}

					    @MainActor public static func customMock() -> Presenter { Presenter() }
					}
					""",
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsErrorsOfEveryTypeInSourceOrder_whenTwoTypesAreMainActorWithoutStatedIsolation() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Presenter.swift"]):1:1: error: `Presenter`’s initializer is `@MainActor`, and the `mock()` SafeDI generates calls it, so that `mock()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `mockAttributes`.
			\(fixtures["Presenter.swift"]):1:1-1:34: fixit: @Instantiable(mockAttributes: \\"@MainActor\\", generateMock: true)
			\(fixtures["Root.swift"]):1:1: error: `Root`’s initializer is `@MainActor`, and the `init()` SafeDI generates for this root calls it, so that `init()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedInitializerAttributes`.
			\(fixtures["Root.swift"]):1:1-1:28: fixit: @Instantiable(isRoot: true, generatedInitializerAttributes: \\"@MainActor\\")
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @MainActor public init(presenter: Presenter) {
					        self.presenter = presenter
					    }

					    @Instantiated private let presenter: Presenter
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Presenter: Instantiable {
					    @MainActor public init() {}
					}
					""",
				],
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – Declarations whose isolation something may state

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesRootInitializer_whenRootTypeIsBoundToInitializersGlobalActor() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true) @MainActor
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				Self.presenter,
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let presenter = Presenter()
			        self.init(presenter: presenter)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            presenter: (() -> Presenter)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                presenter: presenter
			            )
			        }

			        var presenter: (() -> Presenter)? { __safeDI_storage.presenter }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                presenter: (() -> Presenter)?
			            ) {
			                self.presenter = presenter
			            }

			            let presenter: (() -> Presenter)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let presenter = if let safeDIBuilder = safeDIOverrides.presenter { safeDIBuilder() } else { Presenter() }
			        return Root(presenter: presenter)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesRootInitializer_whenGeneratedInitializerAttributesSpellModuleQualifiedMainActor() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generatedInitializerAttributes: "@_Concurrency.MainActor")
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				Self.presenter,
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    @_Concurrency.MainActor public convenience init() {
			        let presenter = Presenter()
			        self.init(presenter: presenter)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesRootInitializer_whenConformanceListNamesProtocolThatBindsTheGlobalActor() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				public protocol Screen: AnyObject {}
				""",
				"""
				@Instantiable(isRoot: true)
				public final class Root: Screen, Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				Self.presenter,
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let presenter = Presenter()
			        self.init(presenter: presenter)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesRootInitializer_whenRootTypeSpellsItsGlobalActorInsideIfConfig() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				#if DEBUG
				@MainActor
				#endif
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				Self.presenter,
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let presenter = Presenter()
			        self.init(presenter: presenter)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesRootInitializer_whenRootInitializerIsPreconcurrencyMainActor() async throws {
		// A `@preconcurrency` callee adds no isolation to what calls it, so the check finds nothing; the generated
		// `init()` calling it is the compiler's to judge, so this test does not compile it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    @preconcurrency @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				Self.presenter,
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let presenter = Presenter()
			        self.init(presenter: presenter)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesNoInitializer_whenRootAndSeamWithMainActorInitializersInstantiateNothing() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    @MainActor public init() {}
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Feature: Instantiable {
				    @MainActor public init(name: String) {
				        self.name = name
				    }

				    @Received private let name: String
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Feature+SafeDI.swift": generatedFileHeader,
			"Root+SafeDI.swift": generatedFileHeader,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesMock_whenInitializerIsMainActorAndGeneratedMockCallsNonisolatedCustomMock() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct Presenter: Instantiable {
				    @MainActor public init() {}

				    public static func customMock() -> Presenter { fatalError() }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Presenter+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Presenter {
			    static func mock() -> Presenter {
			        Presenter.customMock()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesNothing_whenMockOnlyMockIsMainActorAndTypeWithMainActorInitializerGeneratesNothing() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(mockOnly: true)
				public struct Fake {
				    @MainActor public static func mock() -> Fake { Fake() }
				}
				""",
				"""
				@Instantiable
				public struct Presenter: Instantiable {
				    @MainActor public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [:])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesMock_whenExtensionOfMainActorTypeHasMainActorInstantiate() async throws {
		// An `@Instantiable` extension shows no isolation of the type it extends, so nothing is reported for it; the
		// mock, declared in an extension of the type, takes the type's isolation.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				public final class Presenter {}
				""",
				"""
				@Instantiable(generateMock: true)
				extension Presenter: Instantiable {
				    @MainActor public static func instantiate() -> Presenter { Presenter() }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"File+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Presenter {
			    static func mock() -> Presenter {
			        Presenter.instantiate()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	// MARK: Tests – A module that declares `defaultIsolation: MainActor.self`

	@Test(arguments: [nil, "MainActor"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesMainActorDeclarations_whenModuleDeclaresMainActorAndAttributesSpellNoText(buildSettingDefaultIsolation: String?) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true, generateMock: true)
				public final class Feature: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
				Self.presenter,
			],
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.declaringMainActor],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: buildSettingDefaultIsolation),
		)

		#expect(output.generatedFiles == [
			"Feature+SafeDI.swift": generatedFileHeader + """
			extension Feature {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    @MainActor public convenience init() {
			        let presenter = Presenter()
			        self.init(presenter: presenter)
			    }
			}

			extension Feature {
			    public enum __safeDI_Feature_CBF29CE484222325 {}
			}
			""",
			"Feature+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Feature {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            presenter: (() -> Presenter)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                presenter: presenter
			            )
			        }

			        var presenter: (() -> Presenter)? { __safeDI_storage.presenter }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                presenter: (() -> Presenter)?
			            ) {
			                self.presenter = presenter
			            }

			            let presenter: (() -> Presenter)?
			        }
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Feature {
			        let presenter = if let safeDIBuilder = safeDIOverrides.presenter { safeDIBuilder() } else { Presenter() }
			        return Feature(presenter: presenter)
			    }
			}
			#endif
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    @MainActor public convenience init() {
			        let presenter = Presenter()
			        self.init(presenter: presenter)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            presenter: (() -> Presenter)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                presenter: presenter
			            )
			        }

			        var presenter: (() -> Presenter)? { __safeDI_storage.presenter }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                presenter: (() -> Presenter)?
			            ) {
			                self.presenter = presenter
			            }

			            let presenter: (() -> Presenter)?
			        }
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let presenter = if let safeDIBuilder = safeDIOverrides.presenter { safeDIBuilder() } else { Presenter() }
			        return Root(presenter: presenter)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test(arguments: [nil, "MainActor"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesMock_whenModuleDeclaresMainActorAndExtensionHasMainActorInstantiate(buildSettingDefaultIsolation: String?) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public final class Presenter {
				    public init() {}
				}
				""",
				"""
				@Instantiable(generateMock: true)
				extension Presenter: Instantiable {
				    @MainActor public static func instantiate() -> Presenter { Presenter() }
				}
				""",
			],
			swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.declaringMainActor],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: buildSettingDefaultIsolation),
		)

		#expect(output.generatedFiles == [
			"File+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Presenter {
			    @MainActor static func mock() -> Presenter {
			        Presenter.instantiate()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorForInitializerAloneWithFixItAddingToItsText_whenModuleDeclaresMainActorAndOnlyInitializerAttributesSpellText() async {
		// The module's default fills the mock's empty text, so only the root's `init()` is reported, and its fix-it
		// leaves `mockAttributes` unwritten.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Root.swift"]):1:1: error: `Root`’s initializer is `@MainActor`, and the `init()` SafeDI generates for this root calls it, so that `init()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedInitializerAttributes`.
			\(fixtures["Root.swift"]):1:1-1:107: fixit: @Instantiable(isRoot: true, generatedInitializerAttributes: \\"@MainActor @available(macOS 14, *)\\", generateMock: true)
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true, generatedInitializerAttributes: "@available(macOS 14, *)", generateMock: true)
					public final class Root: Instantiable {
					    @MainActor public init(presenter: Presenter) {
					        self.presenter = presenter
					    }

					    @Instantiated private let presenter: Presenter
					}
					""",
					Self.presenter,
				],
				swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.declaringMainActor],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorForMockAlone_whenModuleDeclaresMainActorAndOnlyMockAttributesSpellText() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Feature.swift"]):1:1: error: `Feature`’s initializer is `@MainActor`, and the `mock()` SafeDI generates calls it, so that `mock()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `mockAttributes`.
			\(fixtures["Feature.swift"]):1:1-1:107: fixit: @Instantiable(generateDependencyTree: true, mockAttributes: \\"@MainActor @available(macOS 14, *)\\", generateMock: true)
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateDependencyTree: true, mockAttributes: "@available(macOS 14, *)", generateMock: true)
					public final class Feature: Instantiable {
					    @MainActor public init(presenter: Presenter) {
					        self.presenter = presenter
					    }

					    @Instantiated private let presenter: Presenter
					}
					""",
					Self.presenter,
				],
				swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.declaringMainActor],
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorForEveryDeclaration_whenModuleDeclaresMainActorAndGeneratedAttributesSpellText() async {
		// `generatedAttributes` is text both declarations read, so the module's default fills neither.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Presenter.swift"]):1:1: error: `Presenter`’s initializer is `@MainActor`, and the `mock()` SafeDI generates calls it, so that `mock()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedAttributes`.
			\(fixtures["Presenter.swift"]):1:1-1:85: fixit: @Instantiable(generatedAttributes: \\"@MainActor @available(macOS 14, *)\\", generateMock: .public)
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generatedAttributes: "@available(macOS 14, *)", generateMock: .public)
					public struct Presenter: Instantiable {
					    @MainActor public init() {}
					}
					""",
				],
				swiftFileContentByFilePath: ["SafeDIConfiguration.swift": Self.declaringMainActor],
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – Modules generated one at a time

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_throwsErrorInModuleThatDeclaresRoot_whenModuleDeclaresNoDefaultIsolation(integration: MultiModuleIntegration) async {
		await assertThrowsMultiModuleError(
			inModule: "App",
			diagnostics: { fixtures in
				let rootPath = Self.path(of: "Root.swift", in: "App", fixtures: fixtures, integration: integration)
				return """
				\(rootPath):3:1: error: `Root`’s initializer is `@MainActor`, and the `init()` SafeDI generates for this root calls it, so that `init()` must be `@MainActor` too. SafeDI does not infer the isolation of the code it generates: add `@MainActor` to `generatedInitializerAttributes`.
				\(rootPath):3:1-3:28: fixit: @Instantiable(isRoot: true, generatedInitializerAttributes: \\"@MainActor\\")
				"""
			},
			block: {
				try await executeSafeDIToolMultiModuleTest(
					modules: [
						Self.core,
						Self.app(declaresDefaultIsolation: false, rootIsMainActor: false),
					],
					integration: integration,
					filesToDelete: &filesToDelete,
				)
			},
		)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_generatesMainActorRootInitializer_whenModuleDeclaresMainActor(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.core,
				Self.app(declaresDefaultIsolation: true, rootIsMainActor: false),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		switch integration {
		case .moduleInfo:
			#expect(output.modules["App"]?.generatedFiles == [
				"App.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif

				extension Root {
				    @MainActor public convenience init() {
				        let presenter = Presenter()
				        self.init(presenter: presenter)
				    }
				}
				""",
			])
		case .swiftPackagePlugin:
			#expect(output.modules["App"]?.generatedFiles == [
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif

				extension Root {
				    @MainActor public convenience init() {
				        let presenter = Presenter()
				        self.init(presenter: presenter)
				    }
				}
				""",
			])
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func multiModuleTest_reportsNothingInDependentModule_whenDependencyDeclaresMainActorForItsMainActorMock(integration: MultiModuleIntegration) async throws {
		// `Core`'s default fills its mock's empty text. Under the SwiftPM plugin `App`'s run reads `Core`'s files too,
		// and reports only what its own files declare.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.coreDeclaringMainActorWithMainActorMock,
				Self.app(declaresDefaultIsolation: false, rootIsMainActor: true),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		switch integration {
		case .moduleInfo:
			#expect(output.modules["Core"]?.generatedFiles == [
				"Core.swift": generatedFileHeader + """
				#if DEBUG
				extension Presenter {
				    @MainActor static func mock() -> Presenter {
				        Presenter()
				    }
				}
				#endif
				""",
			])
			#expect(output.modules["App"]?.generatedFiles == [
				"App.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif

				extension Root {
				    public convenience init() {
				        let presenter = Presenter()
				        self.init(presenter: presenter)
				    }
				}
				""",
			])
		case .swiftPackagePlugin:
			#expect(output.modules["Core"]?.generatedFiles == [
				"Presenter+SafeDIMock.swift": generatedFileHeader + """
				#if DEBUG
				extension Presenter {
				    @MainActor static func mock() -> Presenter {
				        Presenter()
				    }
				}
				#endif
				""",
				"SafeDIMockConfiguration.swift": generatedFileHeader,
			])
			#expect(output.modules["App"]?.generatedFiles == [
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif

				extension Root {
				    public convenience init() {
				        let presenter = Presenter()
				        self.init(presenter: presenter)
				    }
				}
				""",
			])
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let presenter = """
	@Instantiable
	public struct Presenter: Instantiable {
	    public init() {}
	}
	"""

	private static let declaringMainActor = """
	#SafeDIConfiguration(
	    defaultIsolation: MainActor.self
	)
	"""

	/// A module whose `Presenter` has a plain initializer.
	private static let core = ModuleFixture(
		name: "Core",
		packageName: "App",
		swiftFileContent: [presenter],
	)

	/// A module that declares `defaultIsolation: MainActor.self` and whose `Presenter` has a `@MainActor` initializer
	/// and a generated mock.
	private static let coreDeclaringMainActorWithMainActorMock = ModuleFixture(
		name: "Core",
		packageName: "App",
		swiftFileContent: [
			"""
			@Instantiable(generateMock: true)
			public struct Presenter: Instantiable {
			    @MainActor public init() {}
			}
			""",
		],
		swiftFileContentByFilePath: ["SafeDIConfiguration.swift": declaringMainActor],
	)

	/// A module whose root has a `@MainActor` initializer and builds `Core`'s `Presenter`.
	private static func app(declaresDefaultIsolation: Bool, rootIsMainActor: Bool) -> ModuleFixture {
		ModuleFixture(
			name: "App",
			packageName: "App",
			swiftFileContent: [
				"""
				import Core

				@Instantiable(isRoot: true)\(rootIsMainActor ? " @MainActor" : "")
				public final class Root: Instantiable {
				    @MainActor public init(presenter: Presenter) {
				        self.presenter = presenter
				    }

				    @Instantiated private let presenter: Presenter
				}
				""",
			],
			swiftFileContentByFilePath: declaresDefaultIsolation ? ["SafeDIConfiguration.swift": declaringMainActor] : [:],
			dependencies: ["Core"],
		)
	}

	private static func path(of fileName: String, in moduleName: String, fixtures: [String: FixturePaths], integration: MultiModuleIntegration) -> String {
		switch integration {
		case .moduleInfo:
			fixtures[moduleName]![fileName]
		case .swiftPackagePlugin:
			NormalizedFilePath(fixtures[moduleName]!.compilerPath(of: fileName)).path
		}
	}
}
