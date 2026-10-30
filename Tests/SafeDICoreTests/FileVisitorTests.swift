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

import SwiftParser
import SwiftSyntax
import Testing
@testable import SafeDICore

struct SafeDIConfigurationVisitorTests {
	@Test
	func extractConfiguration_returnsCorrectValues() {
		let configuration = extractConfiguration(from: """
		#SafeDIConfiguration(
		    additionalImportedModules: ["ModuleA", "ModuleB"],
		    additionalDirectoriesToInclude: ["../Other"],
		    mockConditionalCompilation: "TESTING"
		)
		""")
		#expect(configuration.additionalImportedModules == ["ModuleA", "ModuleB"])
		#expect(configuration.additionalDirectoriesToInclude == ["../Other"])
		#expect(configuration.mockConditionalCompilation == "TESTING")
	}

	@Test
	func extractConfiguration_returnsDefaults_whenNoArguments() {
		let configuration = extractConfiguration(from: """
		#SafeDIConfiguration()
		""")
		#expect(configuration.additionalImportedModules == [])
		#expect(configuration.additionalDirectoriesToInclude == [])
		#expect(configuration.mockConditionalCompilation == "DEBUG")
	}

	@Test
	func extractConfiguration_returnsMockConditionalCompilationNil() {
		let configuration = extractConfiguration(from: """
		#SafeDIConfiguration(
		    mockConditionalCompilation: nil
		)
		""")
		#expect(configuration.mockConditionalCompilation == nil)
	}

	@Test
	func extractConfiguration_ignoresNonLiteralArguments() {
		let configuration = extractConfiguration(from: """
		#SafeDIConfiguration(
		    additionalImportedModules: someVariable,
		    additionalDirectoriesToInclude: anotherVariable,
		    mockConditionalCompilation: yetAnother
		)
		""")
		#expect(configuration.additionalImportedModules == [])
		#expect(configuration.additionalDirectoriesToInclude == [])
		#expect(configuration.mockConditionalCompilation == "DEBUG")
	}

	@Test
	func extractConfiguration_ignoresUnlabeledArguments() {
		let configuration = extractConfiguration(from: """
		#SafeDIConfiguration(
		    ["ModuleA"],
		    additionalDirectoriesToInclude: ["../Other"]
		)
		""")
		// Unlabeled argument is skipped; labeled argument is extracted.
		#expect(configuration.additionalImportedModules == [])
		#expect(configuration.additionalDirectoriesToInclude == ["../Other"])
	}

	@Test
	func extractConfiguration_ignoresUnknownLabeledArguments() {
		let configuration = extractConfiguration(from: """
		#SafeDIConfiguration(
		    unknownParameter: "value",
		    additionalImportedModules: ["ModuleA"]
		)
		""")
		#expect(configuration.additionalImportedModules == ["ModuleA"])
		#expect(configuration.additionalDirectoriesToInclude == [])
	}

	@Test
	func extractConfiguration_ignoresInterpolatedStringLiterals() {
		let configuration = extractConfiguration(from: """
		#SafeDIConfiguration(
		    additionalImportedModules: ["\\(someVar)"]
		)
		""")
		#expect(configuration.additionalImportedModules == [])
	}

	// MARK: Private

	private func extractConfiguration(from source: String) -> SafeDIConfiguration {
		let syntaxTree = Parser.parse(source: source)
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		return fileVisitor.configurations.first ?? SafeDIConfiguration(
			additionalImportedModules: [],
			additionalDirectoriesToInclude: [],
		)
	}
}

struct FileVisitorTests {
	@Test
	func walk_findsInstantiable() {
		let syntaxTree = Parser.parse(source: """
		import UIKit

		@Instantiable
		public final class LoggedInViewController: UIViewController {
		    public init(user: User, networkService: NetworkService) {
		        fatalError("SafeDI doesn't inspect the initializer body")
		    }

		    @Forwarded private let user: User

		    @Received let networkService: NetworkService
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables == [
			Instantiable(
				instantiableType: .simple(name: "LoggedInViewController"),
				isRoot: false,
				initializer: Initializer(
					accessModifierRange: Dependency.SourceRange(startLine: 5, startColumn: 5, endLine: 5, endColumn: 11),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 5, column: 5),
					arguments: [
						.init(
							innerLabel: "user",
							typeDescription: .simple(name: "User"),
							defaultValueExpression: nil,
						),
						.init(
							innerLabel: "networkService",
							typeDescription: .simple(name: "NetworkService"),
							defaultValueExpression: nil,
						),
					],
				),
				additionalInstantiables: nil,
				dependencies: [
					Dependency(
						property: Property(
							label: "user",
							typeDescription: .simple(name: "User"),
						),
						source: .forwarded,
						declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 5),
						identifierRange: Dependency.SourceRange(startLine: 9, startColumn: 28, endLine: 9, endColumn: 32),
						typeAnnotationRange: Dependency.SourceRange(startLine: 9, startColumn: 34, endLine: 9, endColumn: 38),
						bareAttributeRange: Dependency.SourceRange(startLine: 9, startColumn: 5, endLine: 9, endColumn: 15),
					),
					Dependency(
						property: Property(
							label: "networkService",
							typeDescription: .simple(name: "NetworkService"),
						),
						source: .received(onlyIfAvailable: false),
						declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 11, column: 5),
						identifierRange: Dependency.SourceRange(startLine: 11, startColumn: 19, endLine: 11, endColumn: 33),
						typeAnnotationRange: Dependency.SourceRange(startLine: 11, startColumn: 35, endLine: 11, endColumn: 49),
						bareAttributeRange: Dependency.SourceRange(startLine: 11, startColumn: 5, endLine: 11, endColumn: 14),
					),
				],
				declarationType: .classType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 4, startColumn: 1, endLine: 4, endColumn: 7),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 4, column: 1),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 1),
			),
		])
	}

	@Test
	func walk_findsMultipleInstantiables() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable
		public final class LoggedInViewController: UIViewController {
		    public init(user: User, networkService: NetworkService) {
		        fatalError("SafeDI doesn't inspect the initializer body")
		    }

		    @Forwarded private let user: User

		    @Received let networkService: NetworkService
		}

		@Instantiable
		public struct SomeOtherInstantiable {
		    public init() {}
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables == [
			Instantiable(
				instantiableType: .simple(name: "LoggedInViewController"),
				isRoot: false,
				initializer: Initializer(
					accessModifierRange: Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 11),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
					arguments: [
						.init(
							innerLabel: "user",
							typeDescription: .simple(name: "User"),
							defaultValueExpression: nil,
						),
						.init(
							innerLabel: "networkService",
							typeDescription: .simple(name: "NetworkService"),
							defaultValueExpression: nil,
						),
					],
				),
				additionalInstantiables: nil,
				dependencies: [
					Dependency(
						property: Property(
							label: "user",
							typeDescription: .simple(name: "User"),
						),
						source: .forwarded,
						declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 7, column: 5),
						identifierRange: Dependency.SourceRange(startLine: 7, startColumn: 28, endLine: 7, endColumn: 32),
						typeAnnotationRange: Dependency.SourceRange(startLine: 7, startColumn: 34, endLine: 7, endColumn: 38),
						bareAttributeRange: Dependency.SourceRange(startLine: 7, startColumn: 5, endLine: 7, endColumn: 15),
					),
					Dependency(
						property: Property(
							label: "networkService",
							typeDescription: .simple(name: "NetworkService"),
						),
						source: .received(onlyIfAvailable: false),
						declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 5),
						identifierRange: Dependency.SourceRange(startLine: 9, startColumn: 19, endLine: 9, endColumn: 33),
						typeAnnotationRange: Dependency.SourceRange(startLine: 9, startColumn: 35, endLine: 9, endColumn: 49),
						bareAttributeRange: Dependency.SourceRange(startLine: 9, startColumn: 5, endLine: 9, endColumn: 14),
					),
				],
				declarationType: .classType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
			Instantiable(
				instantiableType: .simple(name: "SomeOtherInstantiable"),
				isRoot: false,
				initializer: Initializer(
					accessModifierRange: Dependency.SourceRange(startLine: 14, startColumn: 5, endLine: 14, endColumn: 11),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 14, column: 5),
					arguments: [],
				),
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 13, startColumn: 1, endLine: 13, endColumn: 7),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 13, column: 1),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 12, column: 1),
			),
		])
	}

	@Test
	func walk_findsInstantiableNestedInOuterInstantiableConcreteDeclaration() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable(fulfillingAdditionalTypes: [SomeProtocol.self])
		public struct OuterLevel: SomeProtocol {
		    public init() {}

		    @Instantiable
		    public struct InnerLevel {
		        public init() {}
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables == [
			Instantiable(
				instantiableType: .simple(name: "OuterLevel"),
				isRoot: false,
				initializer: Initializer(
					accessModifierRange: Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 11),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
					arguments: [],
				),
				additionalInstantiables: [
					.simple(name: "SomeProtocol"),
				],
				dependencies: [],
				declarationType: .structType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(
					accessModifierRange: Dependency.SourceRange(startLine: 7, startColumn: 9, endLine: 7, endColumn: 15),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 7, column: 9),
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 6, startColumn: 5, endLine: 6, endColumn: 11),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 6, column: 5),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 5, column: 5),
			),
		])
	}

	@Test
	func walk_findsInstantiableNestedInOuterExtendedInstantiable() {
		let syntaxTree = Parser.parse(source: """
		extension OuterLevel {
		    public static func instantiate() -> OuterLevel { fatalError() }

		    @Instantiable
		    public struct InnerLevel {
		        public init() {}
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables == [
			Instantiable(
				instantiableType: .simple(name: "OuterLevel"),
				isRoot: false,
				initializer: Initializer(
					accessModifierRange: Dependency.SourceRange(startLine: 2, startColumn: 5, endLine: 2, endColumn: 11),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 5),
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .extensionType,
				accessLevel: .internal,
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(
					accessModifierRange: Dependency.SourceRange(startLine: 6, startColumn: 9, endLine: 6, endColumn: 15),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 6, column: 9),
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 5, startColumn: 5, endLine: 5, endColumn: 11),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 5, column: 5),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 4, column: 5),
			),
		])
	}

	@Test
	func walk_findsInstantiablesNestedInOuterExtendedInstantiable() {
		let syntaxTree = Parser.parse(source: """
		extension OuterLevel {
		    public static func instantiate() -> OuterLevel { fatalError() }

		    @Instantiable
		    public actor InnerLevel1 {
		        public init() {}
		    }
		    @Instantiable
		    public class InnerLevel2 {
		        public init() {}
		    }
		    @Instantiable
		    public struct InnerLevel3 {
		        public init() {}
		    }
		    public struct InnerLevel4 {
		        public init() {}
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables == [
			Instantiable(
				instantiableType: .simple(name: "OuterLevel"),
				isRoot: false,
				initializer: Initializer(
					accessModifierRange: Dependency.SourceRange(startLine: 2, startColumn: 5, endLine: 2, endColumn: 11),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 5),
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .extensionType,
				accessLevel: .internal,
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel1", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(
					accessModifierRange: Dependency.SourceRange(startLine: 6, startColumn: 9, endLine: 6, endColumn: 15),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 6, column: 9),
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .actorType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 5, startColumn: 5, endLine: 5, endColumn: 11),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 5, column: 5),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 4, column: 5),
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel2", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(
					accessModifierRange: Dependency.SourceRange(startLine: 10, startColumn: 9, endLine: 10, endColumn: 15),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 10, column: 9),
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .classType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 9, startColumn: 5, endLine: 9, endColumn: 11),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 5),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 8, column: 5),
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel3", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(
					accessModifierRange: Dependency.SourceRange(startLine: 14, startColumn: 9, endLine: 14, endColumn: 15),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 14, column: 9),
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 13, startColumn: 5, endLine: 13, endColumn: 11),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 13, column: 5),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 12, column: 5),
			),
		])
	}

	@Test
	func walk_findsInstantiableNestedWithinEnum() {
		let syntaxTree = Parser.parse(source: """
		public enum OuterLevel {
		    @Instantiable
		    public struct InnerLevel {
		        public init() {}
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables == [
			Instantiable(
				instantiableType: .nested(name: "InnerLevel", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(
					accessModifierRange: Dependency.SourceRange(startLine: 4, startColumn: 9, endLine: 4, endColumn: 15),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 4, column: 9),
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 11),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 5),
			),
		])
	}

	@Test
	func walk_findsSafeDIConfiguration() {
		let syntaxTree = Parser.parse(source: """
		#SafeDIConfiguration(
		    additionalImportedModules: ["ModuleA", "ModuleB"],
		    additionalDirectoriesToInclude: ["DirA"]
		)
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.configurations == [
			SafeDIConfiguration(
				additionalImportedModules: ["ModuleA", "ModuleB"],
				additionalDirectoriesToInclude: ["DirA"],
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
		])
		#expect(fileVisitor.instantiables.isEmpty)
	}

	@Test
	func walk_findsSafeDIConfigurationWithNoArguments() {
		let syntaxTree = Parser.parse(source: """
		#SafeDIConfiguration()
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.configurations == [
			SafeDIConfiguration(
				additionalImportedModules: [],
				additionalDirectoriesToInclude: [],
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
		])
	}

	@Test
	func walk_findsSafeDIConfigurationWithEmptyArrays() {
		let syntaxTree = Parser.parse(source: """
		#SafeDIConfiguration(
		    additionalImportedModules: [],
		    additionalDirectoriesToInclude: []
		)
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.configurations == [
			SafeDIConfiguration(
				additionalImportedModules: [],
				additionalDirectoriesToInclude: [],
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
		])
	}

	@Test
	func walk_findsSafeDIConfigurationWithNonLiteralValues() {
		let syntaxTree = Parser.parse(source: """
		#SafeDIConfiguration(
		    additionalImportedModules: someVariable,
		    additionalDirectoriesToInclude: anotherVariable
		)
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.configurations == [
			SafeDIConfiguration(
				additionalImportedModules: [],
				additionalDirectoriesToInclude: [],
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
		])
	}

	@Test
	func walk_findsSafeDIConfigurationAlongsideInstantiable() {
		let syntaxTree = Parser.parse(source: """
		#SafeDIConfiguration(
		    additionalImportedModules: ["ModuleA"]
		)

		@Instantiable
		public struct SomeService {
		    public init() {}
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.configurations == [
			SafeDIConfiguration(
				additionalImportedModules: ["ModuleA"],
				additionalDirectoriesToInclude: [],
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
		])
		#expect(fileVisitor.instantiables == [
			Instantiable(
				instantiableType: .simple(name: "SomeService"),
				isRoot: false,
				initializer: Initializer(
					accessModifierRange: Dependency.SourceRange(startLine: 7, startColumn: 5, endLine: 7, endColumn: 11),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 7, column: 5),
					arguments: [],
				),
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 6, startColumn: 1, endLine: 6, endColumn: 7),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 6, column: 1),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 5, column: 1),
			),
		])
	}

	@Test
	func walk_ignoresSafeDIConfigurationInsideType() {
		let syntaxTree = Parser.parse(source: """
		struct Outer {
		    #SafeDIConfiguration(
		        additionalImportedModules: ["ModuleA"]
		    )
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.configurations.isEmpty)
	}

	@Test
	func walk_findsDeeplyNestedInstantiables() {
		let syntaxTree = Parser.parse(source: """
		public enum Nested {
		    @Instantiable
		    public struct Nested {
		        public init() {}

		        @Instantiable
		        public actor Nested {
		            public init() {}

		            @Instantiable
		            public final class Nested {
		                public init() {}

		                @Instantiable
		                public actor Nested {
		                    public init() {}

		                    @Instantiable
		                    public final class Nested {
		                        public init() {}

		                        @Instantiable
		                        public struct Nested {
		                            public init() {}

		                            @Instantiable
		                            public final class Nested {
		                                public init() {}

		                                @Instantiable
		                                public actor Nested {
		                                    public init() {}

		                                    @Instantiable
		                                    public actor Nested {
		                                        public init() {}

		                                        @Instantiable
		                                        public struct Nested {
		                                            public init() {}

		                                            @Instantiable
		                                            public struct Nested {
		                                                public init() {}

		                                                @Instantiable
		                                                public final class Nested {
		                                                    public init() {}

		                                                    @Instantiable
		                                                    public final class Nested {
		                                                        public init() {}

		                                                        @Instantiable
		                                                        public final class Nested {
		                                                            public init() {}

		                                                            @Instantiable
		                                                            public final class Nested {
		                                                                public init() {}

		                                                                @Instantiable
		                                                                public final class Nested {
		                                                                    public init() {}

		                                                                    @Instantiable
		                                                                    public final class Nested {
		                                                                        public init() {}

		                                                                        @Instantiable
		                                                                        public final class Nested {
		                                                                            public init() {}

		                                                                            @Instantiable
		                                                                            public final class Nested {
		                                                                                public init() {}
		                                                                            }
		                                                                        }
		                                                                    }
		                                                                }
		                                                            }
		                                                        }
		                                                    }
		                                                }
		                                            }
		                                        }
		                                    }
		                                }
		                            }
		                        }
		                    }
		                }
		            }
		        }
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables == [
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .simple(name: "Nested")),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 4, startColumn: 9, endLine: 4, endColumn: 15),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 4, column: 9),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 11),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 5),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 8, startColumn: 13, endLine: 8, endColumn: 19),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 8, column: 13),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .actorType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 7, startColumn: 9, endLine: 7, endColumn: 15),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 7, column: 9),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 6, column: 9),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 12, startColumn: 17, endLine: 12, endColumn: 23),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 12, column: 17),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .classType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 11, startColumn: 13, endLine: 11, endColumn: 19),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 11, column: 13),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 10, column: 13),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 16, startColumn: 21, endLine: 16, endColumn: 27),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 16, column: 21),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .actorType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 15, startColumn: 17, endLine: 15, endColumn: 23),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 15, column: 17),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 14, column: 17),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 20, startColumn: 25, endLine: 20, endColumn: 31),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 20, column: 25),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .classType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 19, startColumn: 21, endLine: 19, endColumn: 27),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 19, column: 21),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 18, column: 21),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 24, startColumn: 29, endLine: 24, endColumn: 35),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 24, column: 29),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 23, startColumn: 25, endLine: 23, endColumn: 31),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 23, column: 25),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 22, column: 25),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 28, startColumn: 33, endLine: 28, endColumn: 39),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 28, column: 33),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .classType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 27, startColumn: 29, endLine: 27, endColumn: 35),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 27, column: 29),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 26, column: 29),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 32, startColumn: 37, endLine: 32, endColumn: 43),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 32, column: 37),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .actorType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 31, startColumn: 33, endLine: 31, endColumn: 39),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 31, column: 33),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 30, column: 33),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 36, startColumn: 41, endLine: 36, endColumn: 47),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 36, column: 41),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .actorType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 35, startColumn: 37, endLine: 35, endColumn: 43),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 35, column: 37),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 34, column: 37),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 40, startColumn: 45, endLine: 40, endColumn: 51),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 40, column: 45),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 39, startColumn: 41, endLine: 39, endColumn: 47),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 39, column: 41),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 38, column: 41),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 44, startColumn: 49, endLine: 44, endColumn: 55),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 44, column: 49),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 43, startColumn: 45, endLine: 43, endColumn: 51),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 43, column: 45),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 42, column: 45),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 48, startColumn: 53, endLine: 48, endColumn: 59),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 48, column: 53),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .classType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 47, startColumn: 49, endLine: 47, endColumn: 55),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 47, column: 49),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 46, column: 49),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 52, startColumn: 57, endLine: 52, endColumn: 63),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 52, column: 57),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .classType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 51, startColumn: 53, endLine: 51, endColumn: 59),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 51, column: 53),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 50, column: 53),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 56, startColumn: 61, endLine: 56, endColumn: 67),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 56, column: 61),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .classType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 55, startColumn: 57, endLine: 55, endColumn: 63),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 55, column: 57),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 54, column: 57),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 60, startColumn: 65, endLine: 60, endColumn: 71),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 60, column: 65),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .classType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 59, startColumn: 61, endLine: 59, endColumn: 67),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 59, column: 61),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 58, column: 61),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 64, startColumn: 69, endLine: 64, endColumn: 75),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 64, column: 69),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .classType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 63, startColumn: 65, endLine: 63, endColumn: 71),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 63, column: 65),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 62, column: 65),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 68, startColumn: 73, endLine: 68, endColumn: 79),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 68, column: 73),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .classType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 67, startColumn: 69, endLine: 67, endColumn: 75),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 67, column: 69),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 66, column: 69),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 72, startColumn: 77, endLine: 72, endColumn: 83),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 72, column: 77),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .classType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 71, startColumn: 73, endLine: 71, endColumn: 79),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 71, column: 73),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 70, column: 73),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					accessLevel: .public,
					accessModifierRange: Dependency.SourceRange(startLine: 76, startColumn: 81, endLine: 76, endColumn: 87),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 76, column: 81),
					isOptional: false,
					isAsync: false,
					doesThrow: false,
					hasGenericParameter: false,
					hasGenericWhereClause: false,
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .classType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 75, startColumn: 77, endLine: 75, endColumn: 83),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 75, column: 77),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 74, column: 77),
			),
		])
	}

	@Test
	func walk_parsesGenerateMockTrue() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable(generateMock: true)
		public struct OptedIn {
		    public init() {}
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables == [
			Instantiable(
				instantiableType: .simple(name: "OptedIn"),
				isRoot: false,
				initializer: Initializer(
					accessModifierRange: Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 11),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
					arguments: [],
				),
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
				generateMock: true,
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
		])
	}

	@Test
	func walk_parsesGenerateMockFalse() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable(generateMock: false)
		public struct OptedOut {
		    public init() {}
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables == [
			Instantiable(
				instantiableType: .simple(name: "OptedOut"),
				isRoot: false,
				initializer: Initializer(
					accessModifierRange: Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 11),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
					arguments: [],
				),
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
				generateMock: false,
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
		])
	}

	@Test
	func walk_parsesGenerateMockDefault() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable
		public struct DefaultType {
		    public init() {}
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables == [
			Instantiable(
				instantiableType: .simple(name: "DefaultType"),
				isRoot: false,
				initializer: Initializer(
					accessModifierRange: Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 11),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
					arguments: [],
				),
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
				accessLevel: .public,
				accessModifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
		])
	}

	@Test
	func walk_recordsAccessLevelOfEachTypeDeclaration_whenTypesSpellEveryAccessLevel() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable
		open class OpenType: Instantiable {
		    public init() {}
		}

		@Instantiable
		public struct PublicType: Instantiable {
		    public init() {}
		}

		@Instantiable
		package struct PackageType: Instantiable {
		    public init() {}
		}

		@Instantiable
		internal struct InternalType: Instantiable {
		    public init() {}
		}

		@Instantiable
		fileprivate struct FileprivateType: Instantiable {
		    public init() {}
		}

		@Instantiable
		private struct PrivateType: Instantiable {
		    public init() {}
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.accessLevel) == [.open, .public, .package, .internal, .fileprivate, .private])
		#expect(fileVisitor.instantiables.map(\.accessModifierRange) == [
			Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 5),
			Dependency.SourceRange(startLine: 7, startColumn: 1, endLine: 7, endColumn: 7),
			Dependency.SourceRange(startLine: 12, startColumn: 1, endLine: 12, endColumn: 8),
			Dependency.SourceRange(startLine: 17, startColumn: 1, endLine: 17, endColumn: 9),
			Dependency.SourceRange(startLine: 22, startColumn: 1, endLine: 22, endColumn: 12),
			Dependency.SourceRange(startLine: 27, startColumn: 1, endLine: 27, endColumn: 8),
		])
		#expect(fileVisitor.instantiables.map(\.declarationStartLocation) == [
			Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
			Dependency.DeclarationLocation(filePath: "File.swift", line: 7, column: 1),
			Dependency.DeclarationLocation(filePath: "File.swift", line: 12, column: 1),
			Dependency.DeclarationLocation(filePath: "File.swift", line: 17, column: 1),
			Dependency.DeclarationLocation(filePath: "File.swift", line: 22, column: 1),
			Dependency.DeclarationLocation(filePath: "File.swift", line: 27, column: 1),
		])
	}

	@Test
	func walk_recordsInternalAccessLevelWithoutModifierRange_whenTypeSpellsNoAccessModifier() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable
		struct ImplicitType: Instantiable {
		    public init() {}
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.accessLevel) == [.internal])
		#expect(fileVisitor.instantiables.map(\.accessModifierRange) == [nil])
		#expect(fileVisitor.instantiables.map(\.declarationStartLocation) == [
			Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
		])
	}

	@Test
	func walk_recordsDeclarationStartAtFirstModifierAfterAttributes_whenAccessModifierFollowsAnotherModifier() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable @MainActor final public class FinalType: Instantiable {
		    public init() {}
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.accessLevel) == [.public])
		#expect(fileVisitor.instantiables.map(\.accessModifierRange) == [
			Dependency.SourceRange(startLine: 1, startColumn: 32, endLine: 1, endColumn: 38),
		])
		#expect(fileVisitor.instantiables.map(\.declarationStartLocation) == [
			Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 26),
		])
	}

	@Test
	func walk_recordsAccessLevelOfEachMockMethod_whenMockMethodsSpellAccessModifiers() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable
		open class OpenService: Instantiable {
		    public init() {}

		    open class func mock() -> OpenService {
		        OpenService()
		    }
		}

		@Instantiable
		public struct PackageService: Instantiable {
		    public init() {}

		    package static func mock() -> PackageService {
		        PackageService()
		    }
		}

		@Instantiable
		public struct PrivateService: Instantiable {
		    public init() {}

		    private static func mock() -> PrivateService {
		        PrivateService()
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.mockInitializer?.accessLevel) == [.open, .package, .private])
		#expect(fileVisitor.instantiables.map(\.mockInitializer?.accessModifierRange) == [
			Dependency.SourceRange(startLine: 5, startColumn: 5, endLine: 5, endColumn: 9),
			Dependency.SourceRange(startLine: 14, startColumn: 5, endLine: 14, endColumn: 12),
			Dependency.SourceRange(startLine: 23, startColumn: 5, endLine: 23, endColumn: 12),
		])
		#expect(fileVisitor.instantiables.map(\.mockInitializer?.declarationStartLocation) == [
			Dependency.DeclarationLocation(filePath: "File.swift", line: 5, column: 5),
			Dependency.DeclarationLocation(filePath: "File.swift", line: 14, column: 5),
			Dependency.DeclarationLocation(filePath: "File.swift", line: 23, column: 5),
		])
	}

	@Test
	func walk_recordsInternalAccessLevelWithoutModifierRange_whenMockMethodSpellsNoAccessModifier() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable
		public struct Service: Instantiable {
		    public init() {}

		    static func mock() -> Service {
		        Service()
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.mockInitializer?.accessLevel) == [.internal])
		#expect(fileVisitor.instantiables.map(\.mockInitializer?.accessModifierRange) == [nil])
		#expect(fileVisitor.instantiables.map(\.mockInitializer?.declarationStartLocation) == [
			Dependency.DeclarationLocation(filePath: "File.swift", line: 5, column: 5),
		])
	}

	@Test
	func walk_recordsAccessLevelOfEachInstantiateMethod_whenInstantiateMethodsSpellAccessModifiers() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable
		extension FileprivateService: Instantiable {
		    fileprivate static func instantiate() -> FileprivateService {
		        FileprivateService()
		    }
		}

		@Instantiable
		extension PackageService: Instantiable {
		    package static func instantiate() -> PackageService {
		        PackageService()
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.initializer?.accessLevel) == [.fileprivate, .package])
		#expect(fileVisitor.instantiables.map(\.initializer?.accessModifierRange) == [
			Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 16),
			Dependency.SourceRange(startLine: 10, startColumn: 5, endLine: 10, endColumn: 12),
		])
		#expect(fileVisitor.instantiables.map(\.initializer?.declarationStartLocation) == [
			Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
			Dependency.DeclarationLocation(filePath: "File.swift", line: 10, column: 5),
		])
	}

	@Test
	func walk_recordsInternalAccessLevelWithoutModifierRange_whenInstantiateMethodSpellsNoAccessModifier() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable
		extension Service: Instantiable {
		    static func instantiate() -> Service {
		        Service()
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.initializer?.accessLevel) == [.internal])
		#expect(fileVisitor.instantiables.map(\.initializer?.accessModifierRange) == [nil])
		#expect(fileVisitor.instantiables.map(\.initializer?.declarationStartLocation) == [
			Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
		])
	}

	@Test
	func walk_recordsAccessLevelOfEachExtension_whenExtensionsSpellAccessModifiers() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable(conformsElsewhere: true)
		public extension PublicService {
		    static func instantiate() -> PublicService {
		        PublicService()
		    }
		}

		@Instantiable(conformsElsewhere: true)
		package extension PackageService {
		    static func instantiate() -> PackageService {
		        PackageService()
		    }
		}

		@Instantiable(conformsElsewhere: true)
		internal extension InternalService {
		    static func instantiate() -> InternalService {
		        InternalService()
		    }
		}

		@Instantiable(conformsElsewhere: true)
		fileprivate extension FileprivateService {
		    static func instantiate() -> FileprivateService {
		        FileprivateService()
		    }
		}

		@Instantiable(conformsElsewhere: true)
		private extension PrivateService {
		    static func instantiate() -> PrivateService {
		        PrivateService()
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.accessLevel) == [.public, .package, .internal, .fileprivate, .private])
		#expect(fileVisitor.instantiables.map(\.accessModifierRange) == [
			Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
			Dependency.SourceRange(startLine: 9, startColumn: 1, endLine: 9, endColumn: 8),
			Dependency.SourceRange(startLine: 16, startColumn: 1, endLine: 16, endColumn: 9),
			Dependency.SourceRange(startLine: 23, startColumn: 1, endLine: 23, endColumn: 12),
			Dependency.SourceRange(startLine: 30, startColumn: 1, endLine: 30, endColumn: 8),
		])
		#expect(fileVisitor.instantiables.map(\.declarationStartLocation) == [
			Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
			Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 1),
			Dependency.DeclarationLocation(filePath: "File.swift", line: 16, column: 1),
			Dependency.DeclarationLocation(filePath: "File.swift", line: 23, column: 1),
			Dependency.DeclarationLocation(filePath: "File.swift", line: 30, column: 1),
		])
	}

	@Test
	func walk_recordsInternalAccessLevelWithoutModifierRange_whenExtensionSpellsNoAccessModifier() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable
		extension Service: Instantiable {
		    public static func instantiate() -> Service {
		        Service()
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.accessLevel) == [.internal])
		#expect(fileVisitor.instantiables.map(\.accessModifierRange) == [nil])
		#expect(fileVisitor.instantiables.map(\.declarationStartLocation) == [
			Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
		])
	}

	@Test
	func walk_recordsExtensionDeclarationStartAtAccessModifier_whenAttributesPrecedeAccessModifier() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable(conformsElsewhere: true) @MainActor public extension Service {
		    static func instantiate() -> Service {
		        Service()
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.accessLevel) == [.public])
		#expect(fileVisitor.instantiables.map(\.accessModifierRange) == [
			Dependency.SourceRange(startLine: 1, startColumn: 51, endLine: 1, endColumn: 57),
		])
		#expect(fileVisitor.instantiables.map(\.declarationStartLocation) == [
			Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 51),
		])
	}

	@Test
	func walk_recordsInstantiateMethodAccessLevelAsSpelledOnMethod_whenExtensionSpellsAccessModifier() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable(conformsElsewhere: true)
		public extension Service {
		    static func instantiate() -> Service {
		        Service()
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.accessLevel) == [.public])
		#expect(fileVisitor.instantiables.map(\.initializer?.accessLevel) == [.internal])
		#expect(fileVisitor.instantiables.map(\.initializer?.accessModifierRange) == [nil])
	}

	@Test
	func walk_recordsAccessLevelOfMockOnlyExtension_whenExtensionSpellsAccessModifier() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable(mockOnly: true)
		public extension Service {
		    static func mock() -> Service {
		        Service()
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.accessLevel) == [.public])
		#expect(fileVisitor.instantiables.map(\.accessModifierRange) == [
			Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
		])
		#expect(fileVisitor.instantiables.map(\.declarationStartLocation) == [
			Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
		])
		#expect(fileVisitor.instantiables.map(\.mockInitializer?.accessLevel) == [.internal])
	}
}
