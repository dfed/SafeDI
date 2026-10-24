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

struct SafeDIToolMockOnlyErrorTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Error Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenTwoMockOnlyExistForSameType() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File.swift"]):1:1: error: Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.
				\(fixtures["File_2.swift"]):1:1: error: Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(mockOnly: true)
					extension MyService {
					    public static func mock() -> MyService { fatalError() }
					}
					""",
					"""
					@Instantiable(mockOnly: true)
					extension MyService {
					    public static func mock() -> MyService { fatalError() }
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
	mutating func mock_throwsError_whenProductionHasHandWrittenMockAndMockOnlyAlsoExists_mockOnlyFirst() async {
		// Both declarations in the same file guarantees mockOnly extension is
		// parsed first (FileVisitor processes top-to-bottom), hitting the
		// (true, false) branch regardless of TaskGroup ordering.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["MyService.swift"]):1:1: error: Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.
				\(fixtures["MyService.swift"]):6:1: error: Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(mockOnly: true, customMockName: "preview")
					extension MyService {
					    public static func preview() -> MyService { MyService() }
					}

					@Instantiable(customMockName: "customMock")
					public struct MyService: Instantiable {
					    public init() {}
					    public static func customMock() -> MyService { MyService() }
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
	mutating func mock_throwsError_whenProductionHasHandWrittenMockAndMockOnlyAlsoExists_productionFirst() async {
		// Both declarations in the same file guarantees production is parsed
		// first (FileVisitor processes top-to-bottom), hitting the (false, true)
		// branch regardless of TaskGroup ordering.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["MyService.swift"]):1:1: error: Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.
				\(fixtures["MyService.swift"]):7:1: error: Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(customMockName: "customMock")
					public struct MyService: Instantiable {
					    public init() {}
					    public static func customMock() -> MyService { MyService() }
					}

					@Instantiable(mockOnly: true, customMockName: "preview")
					extension MyService {
					    public static func preview() -> MyService { MyService() }
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
	mutating func mock_throwsError_whenTwoDifferentMockOnlyConcreteTypesFulfillSameAdditionalType() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["MockServiceA.swift"]):1:1: error: Found multiple hand-written mock providers for `ServiceProtocol`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.
				\(fixtures["MockServiceB.swift"]):1:1: error: Found multiple hand-written mock providers for `ServiceProtocol`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public protocol ServiceProtocol {}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true)
					public struct MockServiceA: Instantiable, ServiceProtocol {
					    public init() {}
					    public static func mock() -> MockServiceA { MockServiceA() }
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true)
					public struct MockServiceB: Instantiable, ServiceProtocol {
					    public init() {}
					    public static func mock() -> MockServiceB { MockServiceB() }
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
	mutating func mock_throwsError_whenFulfilledByTypeFallbackChildHasForwardedProperty() async {
		// When fulfilledByType is not visible and mock generation falls back to
		// the declared type (via mockOnly), the forwarded-property validation
		// must still fire for constant @Instantiated dependencies.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Root.swift"]):6:5: error: Property `service: AnyService` on Root has at least one @Forwarded property. Property should instead be of type `Instantiator<MockService>`.
				\(fixtures["MockService.swift"]):6:5: note: @Forwarded property `name: String` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public class AnyService {
					    public init(_ value: some Any) {}
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Root: Instantiable {
					    public init(service: AnyService) {
					        self.service = service
					    }
					    @Instantiated(fulfilledByType: "ConcreteService", erasedToConcreteExistential: true) let service: AnyService
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [AnyService.self], mockOnly: true)
					public struct MockService: Instantiable {
					    public init(name: String) {
					        self.name = name
					    }
					    @Forwarded let name: String
					    public static func mock(name: String) -> MockService { MockService(name: name) }
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
	mutating func mock_throwsError_whenSecondMockOnlyArrivesAfterFirstMockOnlyMergedIntoProduction() async {
		// Instantiables are processed in source file path order, keeping each file's
		// declaration order. `MyService.swift` sorts before `ZzzFakeService.swift`, so the
		// production declaration is seen first, its same-file mockOnly extension merges
		// into it, and the second mockOnly then hits the already-merged guard.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["MyService.swift"]):6:1: error: Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.
				\(fixtures["ZzzFakeService.swift"]):1:1: error: Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable
					public struct MyService: Instantiable {
					    public init() {}
					}

					@Instantiable(mockOnly: true)
					extension MyService {
					    public static func mock() -> MyService { MyService() }
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [MyService.self], mockOnly: true)
					public struct ZzzFakeService: Instantiable {
					    public init() {}
					    public static func mock() -> ZzzFakeService { ZzzFakeService() }
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
	mutating func mock_throwsError_whenTwoMockOnlyTypesAndProductionAllClaimSameType() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["FakeService.swift"]):1:1: error: Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.
				\(fixtures["File.swift"]):1:1: error: Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable
					public struct MyService: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable(mockOnly: true)
					extension MyService {
					    public static func mock() -> MyService { MyService() }
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [MyService.self], mockOnly: true)
					public struct FakeService: Instantiable {
					    public init() {}
					    public static func mock() -> FakeService { FakeService() }
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
	mutating func mock_throwsError_whenMockOnlyWinsAdditionalTypeSlotAndChildHasForwardedProperty() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Root.swift"]):6:5: error: Property `service: ServiceProtocol` on Root has at least one @Forwarded property. Property should instead be of type `Instantiator<MockService>`.
				\(fixtures["MockService.swift"]):6:5: note: @Forwarded property `name: String` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public protocol ServiceProtocol {}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Root: Instantiable {
					    public init(service: ServiceProtocol) {
					        self.service = service
					    }
					    @Instantiated let service: ServiceProtocol
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
					public struct RealService: Instantiable, ServiceProtocol {
					    public init() {}
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true)
					public struct MockService: Instantiable, ServiceProtocol {
					    public init(name: String) {
					        self.name = name
					    }
					    @Forwarded let name: String
					    public static func mock(name: String) -> MockService { MockService(name: name) }
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
	mutating func mock_throwsError_whenTwoMockOnlyTypesClaimSameTypeAsProductionWithGenerateMock() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["FakeService.swift"]):1:1: error: Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.
				\(fixtures["File.swift"]):1:1: error: Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct MyService: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable(mockOnly: true)
					extension MyService {
					    public static func mock() -> MyService { MyService() }
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [MyService.self], mockOnly: true)
					public struct FakeService: Instantiable {
					    public init() {}
					    public static func mock() -> FakeService { FakeService() }
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
	mutating func mock_reportsDuplicateProviderAtInstantiableDeclaration_whenDeclarationIsNotAtTopOfFile() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File.swift"]):1:1: error: Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.
				\(fixtures["ServiceProtocol.swift"]):5:1: error: Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public protocol ServiceProtocol {
					    func perform()
					}

					@Instantiable(mockOnly: true)
					extension MyService {
					    public static func mock() -> MyService { fatalError() }
					}
					""",
					"""
					@Instantiable(mockOnly: true)
					extension MyService {
					    public static func mock() -> MyService { fatalError() }
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
	mutating func mock_throwsError_whenMockOnlyMockSharesGeneratedMockSignature() async {
		// The generated `mock(engine: Engine) -> MyService` would redeclare the
		// hand-written `mock(engine:) -> MyService`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File.swift"]):3:5: error: \(Self.generateMockNameCollisionMessage)
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public struct Engine {
					    public init() {}
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct MyService: Instantiable {
					    public init(engine: Engine) {
					        self.engine = engine
					    }
					    @Received let engine: Engine
					}
					""",
					"""
					@Instantiable(mockOnly: true)
					extension MyService {
					    public static func mock(engine: Engine = Engine()) -> MyService { MyService(engine: engine) }
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
	mutating func mock_throwsError_whenMockOnlyMockReturningAdditionalTypeSharesNameWithGeneratedMock() async {
		// MyService generates `mock(engine:) -> MyService` and the mockOnly
		// extension declares `mock(engine:) -> ServiceProtocol`. Root's
		// `MyService.mock(engine: engine)` call would be ambiguous between the two.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File.swift"]):3:5: error: \(Self.generateMockNameCollisionMessage)
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public protocol ServiceProtocol {}
					public struct Engine {
					    public init() {}
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Root: Instantiable {
					    public init(engine: Engine, service: ServiceProtocol) {
					        self.engine = engine
					        self.service = service
					    }
					    @Received let engine: Engine
					    @Instantiated let service: ServiceProtocol
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], generateMock: true)
					public struct MyService: Instantiable, ServiceProtocol {
					    public init(engine: Engine) {
					        self.engine = engine
					    }
					    @Received let engine: Engine
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true)
					extension MyService {
					    public static func mock(engine: Engine = Engine()) -> ServiceProtocol { MyService(engine: engine) }
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
	mutating func mock_throwsError_whenMockOnlyMockWithExtraParameterSharesNameWithGeneratedMock() async {
		// SafeDI calls the hand-written mock as `MyService.mock(engine: engine)`,
		// leaving `verbose` to its default. Swift resolves that call to the
		// generated `mock(engine:)`, which needs no defaults, and silently skips
		// the hand-written mock.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File.swift"]):3:5: error: \(Self.generateMockNameCollisionMessage)
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public protocol ServiceProtocol {}
					public struct Engine {
					    public init() {}
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], generateMock: true)
					public struct MyService: Instantiable, ServiceProtocol {
					    public init(engine: Engine) {
					        self.engine = engine
					    }
					    @Received let engine: Engine
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true)
					extension MyService {
					    public static func mock(engine: Engine = Engine(), _ verbose: Bool = false) -> ServiceProtocol { MyService(engine: engine) }
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
	mutating func mock_throwsError_whenMockOnlyMockSharesNameWithGeneratedMockTakingOnlyOverrides() async {
		// The generated `mock(safeDIOverrides: SafeDIOverrides = .init())` and the
		// hand-written `mock(engine: Engine = Engine())` take different labels, but
		// every parameter of each has a default, so `MyService.mock()` is ambiguous.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File.swift"]):3:5: error: \(Self.generateMockNameCollisionMessage)
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable
					public struct Engine: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct MyService: Instantiable {
					    public init(engine: Engine) {
					        self.engine = engine
					    }
					    @Instantiated let engine: Engine
					}
					""",
					"""
					@Instantiable(mockOnly: true)
					extension MyService {
					    public static func mock(engine: Engine = Engine()) -> MyService { MyService(engine: engine) }
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
	mutating func mock_throwsErrorSuggestingRemovalFromAdditionalMocks_whenAdditionalMockSharesNameWithHandWrittenMockFromDependentModule() async throws {
		// The dependent module declares MyService without `generateMock` plus a
		// mockOnly extension. This module generates `mock(engine:) -> MyService`
		// through `additionalMocksToGenerate`, so Root's
		// `MyService.mock(engine: engine)` would be ambiguous.
		let dependentModuleOutput = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol ServiceProtocol {}
				public struct Engine {
				    public init() {}
				}
				""",
				"""
				@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
				public struct MyService: Instantiable, ServiceProtocol {
				    public init(engine: Engine) {
				        self.engine = engine
				    }
				    @Received let engine: Engine
				}
				""",
				"""
				@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true)
				extension MyService {
				    public static func mock(engine: Engine = Engine()) -> ServiceProtocol { MyService(engine: engine) }
				}
				""",
			],
			filesToDelete: &filesToDelete,
		)

		await assertThrowsError(
			diagnostics: { _ in
				"""
				\(dependentModuleOutput.fixtures["File.swift"]):3:5: error: `MyService` cannot have a hand-written `mock()` method because this module generates a `mock()` method for it (it is listed in `additionalMocksToGenerate`), and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@Instantiable` that declares it, or remove `MyService` from `additionalMocksToGenerate`.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					#SafeDIConfiguration(
					    additionalMocksToGenerate: [
					        "MyService",
					    ]
					)
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Root: Instantiable {
					    public init(engine: Engine, service: ServiceProtocol) {
					        self.engine = engine
					        self.service = service
					    }
					    @Received let engine: Engine
					    @Instantiated let service: ServiceProtocol
					}
					""",
				],
				dependentModuleInfoPaths: [dependentModuleOutput.moduleInfoOutputPath],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private static let generateMockNameCollisionMessage = "`MyService` cannot have a hand-written `mock()` method because it is decorated with `@Instantiable(generateMock: true)`, and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@Instantiable` that declares it."

	private var filesToDelete = [URL]()
}
