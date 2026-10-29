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

/// Dependency trees and chains of received dependencies far deeper than a concurrency thread's stack holds
/// recursion for. Tests run on such threads, half a megabyte on Apple platforms, and a debug build spends kilobytes
/// of stack on a level of a recursive walk, so these chains are deeper than any walk, build, or release of a tree
/// could go while it recursed per level.
struct SafeDIToolDeepTreeTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Dependency Tree Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_writesDependencyTree_whenTwoHundredFeaturesEachInstantiateTheNextThroughAnInstantiator() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.featureChain(depth: 200, rootAttribute: "@Instantiable(isRoot: true)", featuresAreConstant: false),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			// The time the compiler takes for nested builder functions grows exponentially with their depth, so the chain of twenty below is compiled instead.
			skipCompileVerification: true,
		)

		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == Self.instantiatorChainDependencyTree(depth: 200))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_writesDependencyTreeThatCompiles_whenTwentyFeaturesEachInstantiateTheNextThroughAnInstantiator() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.featureChain(depth: 20, rootAttribute: "@Instantiable(isRoot: true)", featuresAreConstant: false),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == Self.instantiatorChainDependencyTree(depth: 20))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_writesDependencyTree_whenTwoHundredFeaturesEachInstantiateTheNextBesideALazilyInstantiatedDependency() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.featureChain(depth: 200, rootAttribute: "@Instantiable(isRoot: true)", featuresAreConstant: true),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			// The time the compiler takes for nested builder functions grows exponentially with their depth, so only the chains of twenty are compiled.
			skipCompileVerification: true,
		)

		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == Self.constantChainDependencyTree(depth: 200))
		// The lazily instantiated dependency has every scope analyzed for the warning it has none of.
		#expect(output.warnings.isEmpty)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_writesDependencyTree_whenEachOfTwoHundredSiblingsReceivesTheNext() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.receivedChain(length: 200),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		let services = (0..<200).map { "service\($0)" }
		var lines = [
			"extension Root {",
			"    public init() {",
			"        let service199 = Service199()",
		]
		for index in (0..<199).reversed() {
			lines.append("        let service\(index) = Service\(index)(service\(index + 1): service\(index + 1))")
		}
		lines += [
			"        self.init(\(services.map { "\($0): \($0)" }.joined(separator: ", ")))",
			"    }",
			"}",
		]
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == Self.fileHeader + lines.joined(separator: "\n"))
	}

	// MARK: Mock Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_writesMock_whenTypeWhoseMockIsGeneratedStartsAChainOfFifteenHundredFeaturesEachInstantiatingTheNext() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.featureChain(depth: 1_500, rootAttribute: "@Instantiable(generateMock: true)", featuresAreConstant: false),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			// The time the compiler takes for nested builder functions grows exponentially with their depth, so the chain of twenty below is compiled instead.
			skipCompileVerification: true,
		)

		#expect(output.mockFiles["Root+SafeDIMock.swift"] == Self.instantiatorChainMock(depth: 1_500))
		#expect(output.mockConfigurationFile == Self.instantiatorChainMockConfiguration(depth: 1_500))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_writesMockThatCompiles_whenTypeWhoseMockIsGeneratedStartsAChainOfTwentyFeaturesEachInstantiatingTheNext() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.featureChain(depth: 20, rootAttribute: "@Instantiable(generateMock: true)", featuresAreConstant: false),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Root+SafeDIMock.swift"] == Self.instantiatorChainMock(depth: 20))
		#expect(output.mockConfigurationFile == Self.instantiatorChainMockConfiguration(depth: 20))
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let fileHeader = """
	// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
	// Any modifications made to this file will be overwritten on subsequent builds.
	// Please refrain from editing this file directly.


	"""

	/// Four spaces for each of `level` levels of indentation.
	private static func indentation(_ level: Int) -> String {
		String(repeating: "    ", count: level)
	}

	/// The source of `Root`, which instantiates `Service` and `Feature0`, of `Service`, and of `depth` features, each of
	/// which receives `Service` and instantiates the next feature but the last. A root of constant features also
	/// instantiates a `LazilyInstantiated<LazyService>`. Features are instantiated through an `Instantiator` otherwise.
	private static func featureChain(depth: Int, rootAttribute: String, featuresAreConstant: Bool) -> [String] {
		func propertyType(ofFeature index: Int) -> String {
			featuresAreConstant ? "Feature\(index)" : "Instantiator<Feature\(index)>"
		}
		let lazyServiceParameter = featuresAreConstant ? ", lazyService: LazilyInstantiated<LazyService>" : ""
		let lazyServiceDeclaration = featuresAreConstant ? "\n    @Instantiated let lazyService: LazilyInstantiated<LazyService>" : ""
		var swiftFileContent = [
			"""
			\(rootAttribute)
			public struct Root: Instantiable {
			    public init(service: Service, feature0: \(propertyType(ofFeature: 0))\(lazyServiceParameter)) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let service: Service
			    @Instantiated let feature0: \(propertyType(ofFeature: 0))\(lazyServiceDeclaration)
			}
			""",
			"""
			@Instantiable
			public struct Service: Instantiable {
			    public init() {}
			}
			""",
		]
		if featuresAreConstant {
			swiftFileContent.append("""
			@Instantiable
			public struct LazyService: Instantiable {
			    public init() {}
			}
			""")
		}
		for index in 0..<depth {
			let nextFeatureParameter = index + 1 < depth ? ", feature\(index + 1): \(propertyType(ofFeature: index + 1))" : ""
			let nextFeatureDeclaration = index + 1 < depth ? "\n    @Instantiated let feature\(index + 1): \(propertyType(ofFeature: index + 1))" : ""
			swiftFileContent.append("""
			@Instantiable
			public struct Feature\(index): Instantiable {
			    public init(service: Service\(nextFeatureParameter)) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Received let service: Service\(nextFeatureDeclaration)
			}
			""")
		}
		return swiftFileContent
	}

	/// The source of `Root`, which instantiates `length` services, each of which but the last receives the next.
	private static func receivedChain(length: Int) -> [String] {
		let services = (0..<length).map { (label: "service\($0)", type: "Service\($0)") }
		var swiftFileContent = [
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(\(services.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			\(services.map { "    @Instantiated let \($0.label): \($0.type)" }.joined(separator: "\n"))
			}
			""",
		]
		for index in 0..<length {
			if index + 1 < length {
				swiftFileContent.append("""
				@Instantiable
				public struct Service\(index): Instantiable {
				    public init(service\(index + 1): Service\(index + 1)) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let service\(index + 1): Service\(index + 1)
				}
				""")
			} else {
				swiftFileContent.append("""
				@Instantiable
				public struct Service\(index): Instantiable {
				    public init() {}
				}
				""")
			}
		}
		return swiftFileContent
	}

	/// The dependency tree of a chain of `depth` features instantiated through an `Instantiator`: a builder function
	/// for each feature, nested in the function that builds the feature before it.
	private static func instantiatorChainDependencyTree(depth: Int) -> String {
		var lines = [
			"extension Root {",
			"    public init() {",
			"        let service = Service()",
		]
		for index in 0..<depth {
			lines.append("\(indentation(2 + index))func __safeDI_feature\(index)() -> Feature\(index) {")
		}
		lines.append("\(indentation(2 + depth))Feature\(depth - 1)(service: service)")
		for index in (0..<depth).reversed() {
			lines.append("\(indentation(2 + index))}")
			lines.append("\(indentation(2 + index))let feature\(index) = Instantiator<Feature\(index)>(__safeDI_feature\(index))")
			if index > 0 {
				lines.append("\(indentation(2 + index))return Feature\(index - 1)(service: service, feature\(index): feature\(index))")
			}
		}
		lines += [
			"        self.init(service: service, feature0: feature0)",
			"    }",
			"}",
		]
		return fileHeader + lines.joined(separator: "\n")
	}

	/// The dependency tree of a chain of `depth` constant features beside a lazily instantiated `LazyService`: a builder
	/// function for each feature that instantiates another, nested in the function that builds the feature before it.
	private static func constantChainDependencyTree(depth: Int) -> String {
		var lines = [
			"extension Root {",
			"    public init() {",
			"        let service = Service()",
		]
		for index in 0..<(depth - 1) {
			lines.append("\(indentation(2 + index))func __safeDI_feature\(index)() -> Feature\(index) {")
		}
		lines.append("\(indentation(1 + depth))let feature\(depth - 1) = Feature\(depth - 1)(service: service)")
		for index in (0..<(depth - 1)).reversed() {
			lines.append("\(indentation(3 + index))return Feature\(index)(service: service, feature\(index + 1): feature\(index + 1))")
			lines.append("\(indentation(2 + index))}")
			lines.append("\(indentation(2 + index))let feature\(index): Feature\(index) = __safeDI_feature\(index)()")
		}
		lines += [
			"        func __safeDI_lazyService() -> LazyService {",
			"            LazyService()",
			"        }",
			"        let lazyService = LazilyInstantiated<LazyService>(__safeDI_lazyService)",
			"        self.init(service: service, feature0: feature0, lazyService: lazyService)",
			"    }",
			"}",
		]
		return fileHeader + lines.joined(separator: "\n")
	}

	/// The path in `safeDIOverrides` of the configuration of the feature at `index`.
	private static func overridePath(toFeatureAt index: Int) -> String {
		(["safeDIOverrides"] + (0...index).map { "feature\($0)" }).joined(separator: ".")
	}

	/// The mock of `Root` for a chain of `depth` features instantiated through an `Instantiator`.
	private static func instantiatorChainMock(depth: Int) -> String {
		var lines = [
			"#if DEBUG",
			"extension Root {",
			"    /// Overrides for the mock dependency tree.",
			"    struct SafeDIOverrides {",
			"        init(",
			"            service: (() -> Service)? = nil,",
			"            feature0: Feature0.SafeDIMockConfiguration = .init()",
			"        ) {",
			"            self.service = service",
			"            self.feature0 = feature0",
			"        }",
			"",
			"        let service: (() -> Service)?",
			"        let feature0: Feature0.SafeDIMockConfiguration",
			"    }",
			"",
			"    static func mock(",
			"        safeDIOverrides: SafeDIOverrides = .init()",
			"    ) -> Root {",
			"        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service() }",
		]
		for index in 0..<depth {
			lines.append("\(indentation(2 + index))func __safeDI_feature\(index)() -> Feature\(index) {")
		}
		lines.append("\(indentation(2 + depth))if let safeDIBuilder = \(overridePath(toFeatureAt: depth - 1)) { safeDIBuilder(service) } else { Feature\(depth - 1)(service: service) }")
		for index in (0..<depth).reversed() {
			lines.append("\(indentation(2 + index))}")
			lines.append("\(indentation(2 + index))let feature\(index) = Instantiator<Feature\(index)>(__safeDI_feature\(index))")
			if index > 0 {
				lines.append("\(indentation(2 + index))return if let safeDIBuilder = \(overridePath(toFeatureAt: index - 1)).safeDIBuilder { safeDIBuilder(service, feature\(index)) } else { Feature\(index - 1)(service: service, feature\(index): feature\(index)) }")
			}
		}
		lines += [
			"        return Root(service: service, feature0: feature0)",
			"    }",
			"}",
			"#endif",
		]
		return fileHeader + lines.joined(separator: "\n")
	}

	/// The configurations of the features in a chain of `depth` features instantiated through an `Instantiator`: one
	/// for each feature that instantiates another, the deepest first.
	private static func instantiatorChainMockConfiguration(depth: Int) -> String {
		let extensions = (0..<(depth - 1)).reversed().map { index in
			let nextFeature = "feature\(index + 1)"
			let nextFeatureType = index + 2 < depth
				? "Feature\(index + 1).SafeDIMockConfiguration"
				: "((Service) -> Feature\(index + 1))?"
			let nextFeatureDefault = index + 2 < depth ? ".init()" : "nil"
			let builderType = "((Service, Instantiator<Feature\(index + 1)>) -> Feature\(index))?"
			return """
			extension Feature\(index) {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            \(nextFeature): \(nextFeatureType) = \(nextFeatureDefault),
			            _ safeDIBuilder: \(builderType) = nil
			        ) {
			            self.\(nextFeature) = \(nextFeature)
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let \(nextFeature): \(nextFeatureType)
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: \(builderType)
			    }
			}
			"""
		}
		return fileHeader + "#if DEBUG\n" + extensions.joined(separator: "\n\n") + "\n#endif\n"
	}
}
