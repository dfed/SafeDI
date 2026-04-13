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
			"Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.",
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
	mutating func mock_throwsError_whenProductionHasHandWrittenMockAndMockOnlyAlsoExists() async {
		await assertThrowsError(
			"Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(customMockName: "customMock")
					public struct MyService: Instantiable {
					    public init() {}
					    public static func customMock() -> MyService { MyService() }
					}
					""",
					"""
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
			"Found multiple hand-written mock providers for `ServiceProtocol`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.",
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
			"""
			Property `service: AnyService` on Root has at least one @Forwarded property. Property should instead be of type `Instantiator<MockService>`.
			""",
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
	mutating func mock_throwsError_whenSecondMockOnlyArrivesAfterFirstMerged() async {
		await assertThrowsError(
			"Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.",
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
			"""
			Property `service: ServiceProtocol` on Root has at least one @Forwarded property. Property should instead be of type `Instantiator<MockService>`.
			""",
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
	mutating func mock_throwsError_whenSecondMockOnlyIgnoredAfterProductionWithMock() async {
		await assertThrowsError(
			"Found multiple hand-written mock providers for `MyService`. A type can have at most one hand-written mock — either on the production declaration or via `mockOnly: true`, not both.",
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

	// MARK: Private

	private var filesToDelete = [URL]()
}
