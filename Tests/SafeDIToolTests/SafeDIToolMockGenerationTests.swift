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

struct SafeDIToolMockGenerationTests: ~Copyable {
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
	mutating func mock_generatedForTypeWithNoDependencies() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public struct SimpleType: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		let mockContent = try #require(output.mockFiles["SimpleType+SafeDIMock.swift"])
		#expect(mockContent.contains("extension SimpleType"))
		#expect(mockContent.contains("public static func mock() -> SimpleType"))
		#expect(mockContent.contains("SimpleType()"))
		#expect(mockContent.contains("#if DEBUG"))
		#expect(mockContent.contains("#endif"))
	}

	@Test
	mutating func mock_generatedForTypeWithInstantiatedDependency() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(dep: Dep) {
				        self.dep = dep
				    }
				    @Instantiated let dep: Dep
				}
				""",
				"""
				@Instantiable
				public struct Dep: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		let rootMock = try #require(output.mockFiles["Root+SafeDIMock.swift"])
		#expect(rootMock.contains("public enum SafeDIMockPath"))
		#expect(rootMock.contains("public enum Dep { case root }"))
		#expect(rootMock.contains("dep: ((SafeDIMockPath.Dep) -> Dep)? = nil"))
		#expect(rootMock.contains("let dep = dep?(.root) ?? Dep.mock()"))

		let depMock = try #require(output.mockFiles["Dep+SafeDIMock.swift"])
		#expect(depMock.contains("public static func mock() -> Dep"))
	}

	@Test
	mutating func mock_generatedForTypeWithReceivedDependency() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(child: Child, shared: SharedThing) {
				        self.child = child
				        self.shared = shared
				    }
				    @Instantiated let child: Child
				    @Instantiated let shared: SharedThing
				}
				""",
				"""
				@Instantiable
				public struct Child: Instantiable {
				    public init(shared: SharedThing) {
				        self.shared = shared
				    }
				    @Received let shared: SharedThing
				}
				""",
				"""
				@Instantiable
				public struct SharedThing: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		let childMock = try #require(output.mockFiles["Child+SafeDIMock.swift"])
		// Child receives SharedThing → path case is "parent"
		#expect(childMock.contains("public enum SharedThing { case parent }"))
		#expect(childMock.contains("sharedThing: ((SafeDIMockPath.SharedThing) -> SharedThing)? = nil"))
		#expect(childMock.contains("let sharedThing = sharedThing?(.parent) ?? SharedThing.mock()"))

		let rootMock = try #require(output.mockFiles["Root+SafeDIMock.swift"])
		// Root instantiates SharedThing → path case is "root"
		#expect(rootMock.contains("public enum SharedThing { case root }"))
		// Root instantiates Child → path case is "root"
		#expect(rootMock.contains("public enum Child { case root }"))
		// Child is built inline threading shared
		#expect(rootMock.contains("let child = child?(.root) ?? Child(shared: sharedThing)"))
	}

	@Test
	mutating func mock_generatedForExtensionBasedInstantiable() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public class SomeThirdPartyType {}

				@Instantiable
				extension SomeThirdPartyType: Instantiable {
				    public static func instantiate() -> SomeThirdPartyType {
				        SomeThirdPartyType()
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		let mockContent = try #require(output.mockFiles["SomeThirdPartyType+SafeDIMock.swift"])
		#expect(mockContent.contains("extension SomeThirdPartyType"))
		#expect(mockContent.contains("SomeThirdPartyType.instantiate()"))
	}

	@Test
	mutating func mock_respectsMockConditionalCompilationNil() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@SafeDIConfiguration
				enum Config {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let generateMocks: Bool = true
				    static let mockConditionalCompilation: StaticString? = nil
				}
				""",
				"""
				@Instantiable
				public struct NoBranch: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		let mockContent = try #require(output.mockFiles["NoBranch+SafeDIMock.swift"])
		#expect(!mockContent.contains("#if"))
		#expect(!mockContent.contains("#endif"))
		#expect(mockContent.contains("extension NoBranch"))
	}

	@Test
	mutating func mock_respectsCustomMockConditionalCompilation() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@SafeDIConfiguration
				enum Config {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let generateMocks: Bool = true
				    static let mockConditionalCompilation: StaticString? = "TESTING"
				}
				""",
				"""
				@Instantiable
				public struct CustomFlag: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		let mockContent = try #require(output.mockFiles["CustomFlag+SafeDIMock.swift"])
		#expect(mockContent.contains("#if TESTING"))
		#expect(mockContent.contains("#endif"))
	}

	@Test
	mutating func mock_notGeneratedWhenGenerateMocksIsFalse() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@SafeDIConfiguration
				enum Config {
				    static let additionalImportedModules: [StaticString] = []
				    static let additionalDirectoriesToInclude: [StaticString] = []
				    static let generateMocks: Bool = false
				    static let mockConditionalCompilation: StaticString? = "DEBUG"
				}
				""",
				"""
				@Instantiable
				public struct NoMocks: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		let mockContent = try #require(output.mockFiles["NoMocks+SafeDIMock.swift"])
		// When generateMocks is false, the file exists but contains only the header.
		#expect(!mockContent.contains("extension NoMocks"))
		#expect(!mockContent.contains("func mock()"))
	}

	@Test
	mutating func mock_respectsMockAttributes() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(mockAttributes: "@MainActor")
				public struct ActorBound: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		let mockContent = try #require(output.mockFiles["ActorBound+SafeDIMock.swift"])
		#expect(mockContent.contains("@MainActor public static func mock()"))
	}

	@Test
	mutating func mock_generatedForFullTree() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(childA: ChildA, shared: SharedThing) {
				        self.childA = childA
				        self.shared = shared
				    }
				    @Instantiated let childA: ChildA
				    @Instantiated let shared: SharedThing
				}
				""",
				"""
				@Instantiable
				public struct ChildA: Instantiable {
				    public init(shared: SharedThing, grandchild: Grandchild) {
				        self.shared = shared
				        self.grandchild = grandchild
				    }
				    @Received let shared: SharedThing
				    @Instantiated let grandchild: Grandchild
				}
				""",
				"""
				@Instantiable
				public struct Grandchild: Instantiable {
				    public init(shared: SharedThing) {
				        self.shared = shared
				    }
				    @Received let shared: SharedThing
				}
				""",
				"""
				@Instantiable
				public struct SharedThing: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		let rootMock = try #require(output.mockFiles["Root+SafeDIMock.swift"])
		// Root has all types in tree
		#expect(rootMock.contains("public enum SafeDIMockPath"))
		#expect(rootMock.contains("public enum SharedThing { case root }"))
		#expect(rootMock.contains("public enum ChildA { case root }"))
		#expect(rootMock.contains("public enum Grandchild { case childA }"))
		// SharedThing constructed first (no deps)
		#expect(rootMock.contains("let sharedThing = sharedThing?(.root) ?? SharedThing.mock()"))
		// Grandchild constructed inline with shared
		#expect(rootMock.contains("let grandchild = grandchild?(.childA) ?? Grandchild(shared: sharedThing)"))
		// ChildA constructed inline with shared and grandchild
		#expect(rootMock.contains("let childA = childA?(.root) ?? ChildA(shared: sharedThing, grandchild: grandchild)"))
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
