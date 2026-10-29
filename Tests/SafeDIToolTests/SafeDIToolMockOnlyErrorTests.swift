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
				\(fixtures["File.swift"]):1:1: error: Found multiple hand-written mocks for `MyService`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.
				\(fixtures["File_2.swift"]):1:1: error: Found multiple hand-written mocks for `MyService`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.
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
				\(fixtures["MyService.swift"]):1:1: error: Found multiple hand-written mocks for `MyService`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.
				\(fixtures["MyService.swift"]):6:1: error: Found multiple hand-written mocks for `MyService`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.
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
				\(fixtures["MyService.swift"]):1:1: error: Found multiple hand-written mocks for `MyService`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.
				\(fixtures["MyService.swift"]):7:1: error: Found multiple hand-written mocks for `MyService`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.
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
				\(fixtures["MockServiceA.swift"]):1:1: error: Found multiple hand-written mocks for `ServiceProtocol`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.
				\(fixtures["MockServiceB.swift"]):1:1: error: Found multiple hand-written mocks for `ServiceProtocol`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.
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
				\(fixtures["Root.swift"]):6:5: error: `service: AnyService` on `Root` cannot build `MockService`, which has @Forwarded properties that only an instantiator is passed. Declare it as `ErasedInstantiator<String, AnyService>`.
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
	mutating func run_throwsError_whenRootInstantiatesTypeThatOnlyMockOnlyDeclarationFulfills() async {
		// `ServiceProtocol` and `DefaultService` share a concrete type, so the dependency tree
		// was built from whichever declaration a set iteration reached first: the production
		// declaration, leaving `service` unbuilt, or the mockOnly one, which cannot be built.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Root.swift"]):7:5: error: No production @Instantiable declaration fulfills `ServiceProtocol`, which @Instantiated property `service: ServiceProtocol` instantiates. A `mockOnly: true` declaration fulfills it, but is used only to generate mocks. Add a production @Instantiable declaration that fulfills `ServiceProtocol`.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(service: ServiceProtocol, defaultService: DefaultService) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let service: ServiceProtocol
					    @Instantiated let defaultService: DefaultService
					}
					""",
					"""
					public protocol ServiceProtocol {}

					@Instantiable
					public struct DefaultService: Instantiable, ServiceProtocol {
					    public init() {}
					}

					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true)
					extension DefaultService {
					    public static func mock() -> DefaultService {
					        DefaultService()
					    }
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
				\(fixtures["MyService.swift"]):6:1: error: Found multiple hand-written mocks for `MyService`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.
				\(fixtures["ZzzFakeService.swift"]):1:1: error: Found multiple hand-written mocks for `MyService`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.
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
				\(fixtures["FakeService.swift"]):1:1: error: Found multiple hand-written mocks for `MyService`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.
				\(fixtures["File.swift"]):1:1: error: Found multiple hand-written mocks for `MyService`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.
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
				\(fixtures["Root.swift"]):6:5: error: `service: ServiceProtocol` on `Root` cannot build `MockService`, which has @Forwarded properties that only an instantiator is passed. Declare it as `Instantiator<MockService>`.
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
				\(fixtures["FakeService.swift"]):1:1: error: Found multiple hand-written mocks for `MyService`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.
				\(fixtures["File.swift"]):1:1: error: Found multiple hand-written mocks for `MyService`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.
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
				\(fixtures["File.swift"]):1:1: error: Found multiple hand-written mocks for `MyService`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.
				\(fixtures["ServiceProtocol.swift"]):5:1: error: Found multiple hand-written mocks for `MyService`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsErrorSuggestingRemovalFromAdditionalMocks_whenAdditionalMockIsGenerateMockInDependentModule() async throws {
		// One dependent module declares MyService with `generateMock: true`, and
		// another declares the mockOnly extension, so each is valid on its own.
		// This module generates a `mock()` for MyService only because it lists the
		// type in `additionalMocksToGenerate`, so removing it from the list is a fix.
		let productionModuleOutput = try await executeSafeDIToolTest(
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
			],
			filesToDelete: &filesToDelete,
		)
		let mockModuleOutput = try await executeSafeDIToolTest(
			swiftFileContent: [
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
				\(mockModuleOutput.fixtures["File.swift"]):3:5: error: `MyService` cannot have a hand-written `mock()` method because this module generates a `mock()` method for it (it is listed in `additionalMocksToGenerate`), and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@Instantiable` that declares it, or remove `MyService` from `additionalMocksToGenerate`.
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
				dependentModuleInfoPaths: [productionModuleOutput.moduleInfoOutputPath, mockModuleOutput.moduleInfoOutputPath],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenTypeIsBuiltByHandWrittenMockAndByInitializerThatTakeDifferentDependencies() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File.swift"]):3:5: error: Generated mocks build `MyService` with its hand-written `mock` method for `service: ServiceProtocol` on `Parent` in `Parent.mock()`, and with its initializer for `concreteService: MyService` on `Parent` in `Parent.mock()`. The two take different parameters, but both properties are configured with one `MyService.SafeDIMockConfiguration`. Make `mock` return `MyService`, so that it builds both properties, or give `mock` exactly the parameters of `MyService`’s initializer, in the same order.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Parent: Instantiable {
					    public init(service: ServiceProtocol, concreteService: MyService) {
					        self.service = service
					        self.concreteService = concreteService
					    }
					    @Instantiated let service: ServiceProtocol
					    @Instantiated let concreteService: MyService
					}
					""",
					"""
					public protocol ServiceProtocol {}
					""",
					"""
					@Instantiable
					public struct Database: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Logger: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
					public struct MyService: ServiceProtocol, Instantiable {
					    public init(database: Database, logger: Logger) {
					        self.database = database
					        self.logger = logger
					    }
					    @Instantiated let database: Database
					    @Instantiated let logger: Logger
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true)
					extension MyService {
					    public static func mock(database: Database = Database()) -> ServiceProtocol { MyService(database: database, logger: Logger()) }
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
	mutating func mock_throwsError_whenTypeIsBuiltByHandWrittenMockWithDefaultParameterAndByInitializer() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File.swift"]):3:5: error: Generated mocks build `MyService` with its hand-written `mock` method for `service: ServiceProtocol` on `Parent` in `Parent.mock()`, and with its initializer for `concreteService: MyService` on `Parent` in `Parent.mock()`. The two take different parameters, but both properties are configured with one `MyService.SafeDIMockConfiguration`. Make `mock` return `MyService`, so that it builds both properties, or give `mock` exactly the parameters of `MyService`’s initializer, in the same order.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Parent: Instantiable {
					    public init(service: ServiceProtocol, concreteService: MyService) {
					        self.service = service
					        self.concreteService = concreteService
					    }
					    @Instantiated let service: ServiceProtocol
					    @Instantiated let concreteService: MyService
					}
					""",
					"""
					public protocol ServiceProtocol {}
					""",
					"""
					@Instantiable
					public struct Database: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
					public struct MyService: ServiceProtocol, Instantiable {
					    public init(database: Database) {
					        self.database = database
					    }
					    @Instantiated let database: Database
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true)
					extension MyService {
					    public static func mock(database: Database = Database(), name: String = "mock") -> ServiceProtocol { MyService(database: database) }
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
	mutating func mock_throwsError_whenTypeIsBuiltByHandWrittenMockAndByInitializerThatTakeDependenciesInDifferentOrder() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File.swift"]):3:5: error: Generated mocks build `MyService` with its hand-written `preview` method for `service: ServiceProtocol` on `Parent` in `Parent.mock()`, and with its initializer for `concreteService: MyService` on `Parent` in `Parent.mock()`. The two take different parameters, but both properties are configured with one `MyService.SafeDIMockConfiguration`. Make `preview` return `MyService`, so that it builds both properties, or give `preview` exactly the parameters of `MyService`’s initializer, in the same order.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Parent: Instantiable {
					    public init(service: ServiceProtocol, concreteService: MyService) {
					        self.service = service
					        self.concreteService = concreteService
					    }
					    @Instantiated let service: ServiceProtocol
					    @Instantiated let concreteService: MyService
					}
					""",
					"""
					public protocol ServiceProtocol {}
					""",
					"""
					@Instantiable
					public struct Database: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Logger: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
					public struct MyService: ServiceProtocol, Instantiable {
					    public init(database: Database, logger: Logger) {
					        self.database = database
					        self.logger = logger
					    }
					    @Instantiated let database: Database
					    @Instantiated let logger: Logger
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true, customMockName: "preview")
					extension MyService {
					    public static func preview(logger: Logger = Logger(), database: Database = Database()) -> ServiceProtocol { MyService(database: database, logger: logger) }
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
	mutating func mock_throwsError_whenTypeIsBuiltByInitializerInRootThatSortsFirstAndByHandWrittenMockInRootThatSortsLast() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File.swift"]):3:5: error: Generated mocks build `MyService` with its hand-written `mock` method for `service: ServiceProtocol` on `ZParent` in `ZParent.mock()`, and with its initializer for `concreteService: MyService` on `AParent` in `AParent.mock()`. The two take different parameters, but both properties are configured with one `MyService.SafeDIMockConfiguration`. Make `mock` return `MyService`, so that it builds both properties, or give `mock` exactly the parameters of `MyService`’s initializer, in the same order.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct AParent: Instantiable {
					    public init(concreteService: MyService) {
					        self.concreteService = concreteService
					    }
					    @Instantiated let concreteService: MyService
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct ZParent: Instantiable {
					    public init(service: ServiceProtocol) {
					        self.service = service
					    }
					    @Instantiated let service: ServiceProtocol
					}
					""",
					"""
					public protocol ServiceProtocol {}
					""",
					"""
					@Instantiable
					public struct Database: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Logger: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
					public struct MyService: ServiceProtocol, Instantiable {
					    public init(database: Database, logger: Logger) {
					        self.database = database
					        self.logger = logger
					    }
					    @Instantiated let database: Database
					    @Instantiated let logger: Logger
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true)
					extension MyService {
					    public static func mock(database: Database = Database()) -> ServiceProtocol { MyService(database: database, logger: Logger()) }
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
	mutating func mock_throwsError_whenTypeIsBuiltByHandWrittenMockInRootThatSortsFirstAndByInitializerInRootThatSortsLast() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File.swift"]):3:5: error: Generated mocks build `MyService` with its hand-written `mock` method for `service: ServiceProtocol` on `AParent` in `AParent.mock()`, and with its initializer for `concreteService: MyService` on `ZParent` in `ZParent.mock()`. The two take different parameters, but both properties are configured with one `MyService.SafeDIMockConfiguration`. Make `mock` return `MyService`, so that it builds both properties, or give `mock` exactly the parameters of `MyService`’s initializer, in the same order.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct AParent: Instantiable {
					    public init(service: ServiceProtocol) {
					        self.service = service
					    }
					    @Instantiated let service: ServiceProtocol
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct ZParent: Instantiable {
					    public init(concreteService: MyService) {
					        self.concreteService = concreteService
					    }
					    @Instantiated let concreteService: MyService
					}
					""",
					"""
					public protocol ServiceProtocol {}
					""",
					"""
					@Instantiable
					public struct Database: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Logger: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
					public struct MyService: ServiceProtocol, Instantiable {
					    public init(database: Database, logger: Logger) {
					        self.database = database
					        self.logger = logger
					    }
					    @Instantiated let database: Database
					    @Instantiated let logger: Logger
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self], mockOnly: true)
					extension MyService {
					    public static func mock(database: Database = Database()) -> ServiceProtocol { MyService(database: database, logger: Logger()) }
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
	mutating func mock_throwsErrorNamingInstantiateMethod_whenExtensionTypeIsBuiltByHandWrittenMockAndByInstantiateWithDifferentDefaultParameters() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File.swift"]):4:5: error: Generated mocks build `MyService` with its hand-written `mock` method for `service: ServiceProtocol` on `Parent` in `Parent.mock()`, and with its `instantiate(…)` method for `concreteService: MyService` on `Parent` in `Parent.mock()`. The two take different parameters, but both properties are configured with one `MyService.SafeDIMockConfiguration`. Make `mock` return `MyService`, so that it builds both properties, or give `mock` exactly the parameters of `MyService`’s `instantiate(…)` method, in the same order.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Parent: Instantiable {
					    public init(service: ServiceProtocol, concreteService: MyService) {
					        self.service = service
					        self.concreteService = concreteService
					    }
					    @Instantiated let service: ServiceProtocol
					    @Instantiated let concreteService: MyService
					}
					""",
					"""
					public protocol ServiceProtocol {}
					""",
					"""
					public struct MyService: ServiceProtocol {
					    public init(title: String) {
					        self.title = title
					    }
					    public let title: String
					}
					""",
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
					extension MyService: Instantiable {
					    public static func instantiate(title: String = "production") -> MyService { MyService(title: title) }
					    public static func mock(name: String = "mock") -> ServiceProtocol { MyService(title: name) }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private static let generateMockNameCollisionMessage = "`MyService` cannot have a hand-written `mock()` method because it is decorated with `@Instantiable(generateMock: true)`, and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@Instantiable` that declares it."

	private var filesToDelete = [URL]()
}
