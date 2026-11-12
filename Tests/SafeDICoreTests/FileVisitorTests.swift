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
	func extractConfiguration_returnsGeneratePlainDependencyTreeInitializersTrue_whenSetToTrue() {
		let configuration = extractConfiguration(from: """
		#SafeDIConfiguration(
		    generatePlainDependencyTreeInitializers: true
		)
		""")
		#expect(configuration.generatePlainDependencyTreeInitializers)
	}

	@Test
	func extractConfiguration_returnsGeneratePlainDependencyTreeInitializersFalse_whenSetToFalseOrOmittedOrNotLiteral() {
		for source in [
			"#SafeDIConfiguration(generatePlainDependencyTreeInitializers: false)",
			"#SafeDIConfiguration()",
			"#SafeDIConfiguration(generatePlainDependencyTreeInitializers: someVariable)",
		] {
			#expect(!extractConfiguration(from: source).generatePlainDependencyTreeInitializers, "\(source)")
		}
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
	func walk_recordsDependencyTreeTypeInEveryClause_whenGenerateDependencyTreeIsTrueInInactiveClause() {
		// The file's generated files are planned whatever the conditions, so the declaration is recorded from the
		// inactive clause too, while the instantiable itself is found only in the active one.
		let syntaxTree = Parser.parse(source: """
		#if FEATURE
		@Instantiable(generateDependencyTree: true)
		public struct FeatureScreen: Instantiable {
		    public init() {}
		}
		#else
		@Instantiable
		public struct Screen: Instantiable {
		    public init() {}
		}
		#endif
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.concreteInstantiable) == [.simple(name: "Screen")])
		#expect(fileVisitor.instantiables.map(\.generatesDependencyTree) == [false])
		#expect(fileVisitor.outputFileDeclarations.declaresDependencyTreeType)
		#expect(!fileVisitor.outputFileDeclarations.declaresRoot)
		#expect(fileVisitor.consultedCompilationConditions == ["FEATURE"])
	}

	@Test
	func walk_recordsGeneratesDependencyTree_whenTypeDeclarationSetsIt() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable(generateDependencyTree: true)
		public struct Screen: Instantiable {
		    public init(user: User) {
		        self.user = user
		    }

		    @Received let user: User
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.generatesDependencyTree) == [true])
		#expect(fileVisitor.instantiables.map(\.isRoot) == [false])
		#expect(fileVisitor.outputFileDeclarations.declaresDependencyTreeType)
		#expect(!fileVisitor.outputFileDeclarations.declaresRoot)
		#expect(fileVisitor.consultedCompilationConditions.isEmpty)
	}

	@Test
	func walk_recordsNoDependencyTreeType_whenExtensionSpellsGenerateDependencyTree() {
		// The macro rejects the argument on an extension, as it rejects `isRoot: true` there; the visitors plan
		// no file for it either way.
		let syntaxTree = Parser.parse(source: """
		@Instantiable(generateDependencyTree: true)
		extension Screen: Instantiable {
		    public static func instantiate() -> Screen { Screen() }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.generatesDependencyTree) == [false])
		#expect(!fileVisitor.outputFileDeclarations.declaresDependencyTreeType)
	}

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
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 5, startColumn: 5, endLine: 5, endColumn: 11),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 5, column: 5),
					),
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
				access: AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 4, startColumn: 1, endLine: 4, endColumn: 7),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 4, column: 1),
				),
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
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 11),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
					),
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
				access: AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
				),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
			Instantiable(
				instantiableType: .simple(name: "SomeOtherInstantiable"),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 14, startColumn: 5, endLine: 14, endColumn: 11),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 14, column: 5),
					),
					arguments: [],
				),
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
				access: AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 13, startColumn: 1, endLine: 13, endColumn: 7),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 13, column: 1),
				),
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
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 11),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
					),
					arguments: [],
				),
				additionalInstantiables: [
					.simple(name: "SomeProtocol"),
				],
				dependencies: [],
				declarationType: .structType,
				access: AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
				),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 7, startColumn: 9, endLine: 7, endColumn: 15),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 7, column: 9),
					),
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
				access: AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 6, startColumn: 5, endLine: 6, endColumn: 11),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 6, column: 5),
				),
				enclosingTypeAccess: [
					AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
					),
				],
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
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 5, endLine: 2, endColumn: 11),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 5),
					),
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .extensionType,
				access: AccessDeclaration(
					level: .internal,
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
					isExtension: true,
				),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 6, startColumn: 9, endLine: 6, endColumn: 15),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 6, column: 9),
					),
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
				access: AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 5, startColumn: 5, endLine: 5, endColumn: 11),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 5, column: 5),
				),
				enclosingExtensionAccess: AccessDeclaration(
					level: .internal,
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
					isExtension: true,
				),
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
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 5, endLine: 2, endColumn: 11),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 5),
					),
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .extensionType,
				access: AccessDeclaration(
					level: .internal,
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
					isExtension: true,
				),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel1", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 6, startColumn: 9, endLine: 6, endColumn: 15),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 6, column: 9),
					),
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .actorType,
				access: AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 5, startColumn: 5, endLine: 5, endColumn: 11),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 5, column: 5),
				),
				enclosingExtensionAccess: AccessDeclaration(
					level: .internal,
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
					isExtension: true,
				),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 4, column: 5),
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel2", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 10, startColumn: 9, endLine: 10, endColumn: 15),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 10, column: 9),
					),
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .classType,
				access: AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 9, startColumn: 5, endLine: 9, endColumn: 11),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 5),
				),
				enclosingExtensionAccess: AccessDeclaration(
					level: .internal,
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
					isExtension: true,
				),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 8, column: 5),
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel3", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 14, startColumn: 9, endLine: 14, endColumn: 15),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 14, column: 9),
					),
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
				access: AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 13, startColumn: 5, endLine: 13, endColumn: 11),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 13, column: 5),
				),
				enclosingExtensionAccess: AccessDeclaration(
					level: .internal,
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
					isExtension: true,
				),
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
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 4, startColumn: 9, endLine: 4, endColumn: 15),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 4, column: 9),
					),
					arguments: [],
				),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
				access: AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 11),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
				),
				enclosingTypeAccess: [
					AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 7),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
					),
				],
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
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 7, startColumn: 5, endLine: 7, endColumn: 11),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 7, column: 5),
					),
					arguments: [],
				),
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
				access: AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 6, startColumn: 1, endLine: 6, endColumn: 7),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 6, column: 1),
				),
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
		// The access of each declaration, outermost first: the enum, then each `Nested` type, which encloses the next.
		let declarationAccess = [
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 7),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 11),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 7, startColumn: 9, endLine: 7, endColumn: 15),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 7, column: 9),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 11, startColumn: 13, endLine: 11, endColumn: 19),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 11, column: 13),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 15, startColumn: 17, endLine: 15, endColumn: 23),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 15, column: 17),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 19, startColumn: 21, endLine: 19, endColumn: 27),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 19, column: 21),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 23, startColumn: 25, endLine: 23, endColumn: 31),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 23, column: 25),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 27, startColumn: 29, endLine: 27, endColumn: 35),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 27, column: 29),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 31, startColumn: 33, endLine: 31, endColumn: 39),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 31, column: 33),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 35, startColumn: 37, endLine: 35, endColumn: 43),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 35, column: 37),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 39, startColumn: 41, endLine: 39, endColumn: 47),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 39, column: 41),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 43, startColumn: 45, endLine: 43, endColumn: 51),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 43, column: 45),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 47, startColumn: 49, endLine: 47, endColumn: 55),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 47, column: 49),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 51, startColumn: 53, endLine: 51, endColumn: 59),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 51, column: 53),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 55, startColumn: 57, endLine: 55, endColumn: 63),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 55, column: 57),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 59, startColumn: 61, endLine: 59, endColumn: 67),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 59, column: 61),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 63, startColumn: 65, endLine: 63, endColumn: 71),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 63, column: 65),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 67, startColumn: 69, endLine: 67, endColumn: 75),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 67, column: 69),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 71, startColumn: 73, endLine: 71, endColumn: 79),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 71, column: 73),
			),
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 75, startColumn: 77, endLine: 75, endColumn: 83),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 75, column: 77),
			),
		]
		#expect(fileVisitor.instantiables == [
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .simple(name: "Nested")),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 4, startColumn: 9, endLine: 4, endColumn: 15),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 4, column: 9),
					),
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
				access: declarationAccess[1],
				enclosingTypeAccess: Array(declarationAccess.prefix(1)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 5),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 8, startColumn: 13, endLine: 8, endColumn: 19),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 8, column: 13),
					),
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
				access: declarationAccess[2],
				enclosingTypeAccess: Array(declarationAccess.prefix(2)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 6, column: 9),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 12, startColumn: 17, endLine: 12, endColumn: 23),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 12, column: 17),
					),
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
				access: declarationAccess[3],
				enclosingTypeAccess: Array(declarationAccess.prefix(3)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 10, column: 13),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 16, startColumn: 21, endLine: 16, endColumn: 27),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 16, column: 21),
					),
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
				access: declarationAccess[4],
				enclosingTypeAccess: Array(declarationAccess.prefix(4)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 14, column: 17),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 20, startColumn: 25, endLine: 20, endColumn: 31),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 20, column: 25),
					),
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
				access: declarationAccess[5],
				enclosingTypeAccess: Array(declarationAccess.prefix(5)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 18, column: 21),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 24, startColumn: 29, endLine: 24, endColumn: 35),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 24, column: 29),
					),
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
				access: declarationAccess[6],
				enclosingTypeAccess: Array(declarationAccess.prefix(6)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 22, column: 25),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 28, startColumn: 33, endLine: 28, endColumn: 39),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 28, column: 33),
					),
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
				access: declarationAccess[7],
				enclosingTypeAccess: Array(declarationAccess.prefix(7)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 26, column: 29),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 32, startColumn: 37, endLine: 32, endColumn: 43),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 32, column: 37),
					),
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
				access: declarationAccess[8],
				enclosingTypeAccess: Array(declarationAccess.prefix(8)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 30, column: 33),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 36, startColumn: 41, endLine: 36, endColumn: 47),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 36, column: 41),
					),
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
				access: declarationAccess[9],
				enclosingTypeAccess: Array(declarationAccess.prefix(9)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 34, column: 37),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 40, startColumn: 45, endLine: 40, endColumn: 51),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 40, column: 45),
					),
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
				access: declarationAccess[10],
				enclosingTypeAccess: Array(declarationAccess.prefix(10)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 38, column: 41),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 44, startColumn: 49, endLine: 44, endColumn: 55),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 44, column: 49),
					),
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
				access: declarationAccess[11],
				enclosingTypeAccess: Array(declarationAccess.prefix(11)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 42, column: 45),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 48, startColumn: 53, endLine: 48, endColumn: 59),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 48, column: 53),
					),
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
				access: declarationAccess[12],
				enclosingTypeAccess: Array(declarationAccess.prefix(12)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 46, column: 49),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 52, startColumn: 57, endLine: 52, endColumn: 63),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 52, column: 57),
					),
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
				access: declarationAccess[13],
				enclosingTypeAccess: Array(declarationAccess.prefix(13)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 50, column: 53),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 56, startColumn: 61, endLine: 56, endColumn: 67),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 56, column: 61),
					),
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
				access: declarationAccess[14],
				enclosingTypeAccess: Array(declarationAccess.prefix(14)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 54, column: 57),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 60, startColumn: 65, endLine: 60, endColumn: 71),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 60, column: 65),
					),
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
				access: declarationAccess[15],
				enclosingTypeAccess: Array(declarationAccess.prefix(15)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 58, column: 61),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 64, startColumn: 69, endLine: 64, endColumn: 75),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 64, column: 69),
					),
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
				access: declarationAccess[16],
				enclosingTypeAccess: Array(declarationAccess.prefix(16)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 62, column: 65),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 68, startColumn: 73, endLine: 68, endColumn: 79),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 68, column: 73),
					),
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
				access: declarationAccess[17],
				enclosingTypeAccess: Array(declarationAccess.prefix(17)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 66, column: 69),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 72, startColumn: 77, endLine: 72, endColumn: 83),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 72, column: 77),
					),
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
				access: declarationAccess[18],
				enclosingTypeAccess: Array(declarationAccess.prefix(18)),
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 70, column: 73),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 76, startColumn: 81, endLine: 76, endColumn: 87),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 76, column: 81),
					),
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
				access: declarationAccess[19],
				enclosingTypeAccess: Array(declarationAccess.prefix(19)),
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
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 11),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
					),
					arguments: [],
				),
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
				access: AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
				),
				generateMock: true,
				mockGenerationArgumentRange: Dependency.SourceRange(startLine: 1, startColumn: 29, endLine: 1, endColumn: 33),
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
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 11),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
					),
					arguments: [],
				),
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
				access: AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
				),
				generateMock: false,
				mockGenerationArgumentRange: Dependency.SourceRange(startLine: 1, startColumn: 29, endLine: 1, endColumn: 34),
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
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 11),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
					),
					arguments: [],
				),
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
				access: AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
				),
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
		#expect(fileVisitor.instantiables.map(\.access.level) == [.open, .public, .package, .internal, .fileprivate, .private])
		#expect(fileVisitor.instantiables.map(\.access.modifierRange) == [
			Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 5),
			Dependency.SourceRange(startLine: 7, startColumn: 1, endLine: 7, endColumn: 7),
			Dependency.SourceRange(startLine: 12, startColumn: 1, endLine: 12, endColumn: 8),
			Dependency.SourceRange(startLine: 17, startColumn: 1, endLine: 17, endColumn: 9),
			Dependency.SourceRange(startLine: 22, startColumn: 1, endLine: 22, endColumn: 12),
			Dependency.SourceRange(startLine: 27, startColumn: 1, endLine: 27, endColumn: 8),
		])
		#expect(fileVisitor.instantiables.map(\.access.declarationStartLocation) == [
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
		#expect(fileVisitor.instantiables.map(\.access.level) == [.internal])
		#expect(fileVisitor.instantiables.map(\.access.modifierRange) == [nil])
		#expect(fileVisitor.instantiables.map(\.access.declarationStartLocation) == [
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
		#expect(fileVisitor.instantiables.map(\.access.level) == [.public])
		#expect(fileVisitor.instantiables.map(\.access.modifierRange) == [
			Dependency.SourceRange(startLine: 1, startColumn: 32, endLine: 1, endColumn: 38),
		])
		#expect(fileVisitor.instantiables.map(\.access.declarationStartLocation) == [
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
		#expect(fileVisitor.instantiables.map(\.mockInitializer?.access.level) == [.open, .package, .private])
		#expect(fileVisitor.instantiables.map(\.mockInitializer?.access.modifierRange) == [
			Dependency.SourceRange(startLine: 5, startColumn: 5, endLine: 5, endColumn: 9),
			Dependency.SourceRange(startLine: 14, startColumn: 5, endLine: 14, endColumn: 12),
			Dependency.SourceRange(startLine: 23, startColumn: 5, endLine: 23, endColumn: 12),
		])
		#expect(fileVisitor.instantiables.map(\.mockInitializer?.access.declarationStartLocation) == [
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
		#expect(fileVisitor.instantiables.map(\.mockInitializer?.access.level) == [.internal])
		#expect(fileVisitor.instantiables.map(\.mockInitializer?.access.modifierRange) == [nil])
		#expect(fileVisitor.instantiables.map(\.mockInitializer?.access.declarationStartLocation) == [
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
		#expect(fileVisitor.instantiables.map(\.initializer?.access.level) == [.fileprivate, .package])
		#expect(fileVisitor.instantiables.map(\.initializer?.access.modifierRange) == [
			Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 16),
			Dependency.SourceRange(startLine: 10, startColumn: 5, endLine: 10, endColumn: 12),
		])
		#expect(fileVisitor.instantiables.map(\.initializer?.access.declarationStartLocation) == [
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
		#expect(fileVisitor.instantiables.map(\.initializer?.access.level) == [.internal])
		#expect(fileVisitor.instantiables.map(\.initializer?.access.modifierRange) == [nil])
		#expect(fileVisitor.instantiables.map(\.initializer?.access.declarationStartLocation) == [
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
		#expect(fileVisitor.instantiables.map(\.access.level) == [.public, .package, .internal, .fileprivate, .private])
		#expect(fileVisitor.instantiables.map(\.access.modifierRange) == [
			Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
			Dependency.SourceRange(startLine: 9, startColumn: 1, endLine: 9, endColumn: 8),
			Dependency.SourceRange(startLine: 16, startColumn: 1, endLine: 16, endColumn: 9),
			Dependency.SourceRange(startLine: 23, startColumn: 1, endLine: 23, endColumn: 12),
			Dependency.SourceRange(startLine: 30, startColumn: 1, endLine: 30, endColumn: 8),
		])
		#expect(fileVisitor.instantiables.map(\.access.declarationStartLocation) == [
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
		#expect(fileVisitor.instantiables.map(\.access.level) == [.internal])
		#expect(fileVisitor.instantiables.map(\.access.modifierRange) == [nil])
		#expect(fileVisitor.instantiables.map(\.access.declarationStartLocation) == [
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
		#expect(fileVisitor.instantiables.map(\.access.level) == [.public])
		#expect(fileVisitor.instantiables.map(\.access.modifierRange) == [
			Dependency.SourceRange(startLine: 1, startColumn: 51, endLine: 1, endColumn: 57),
		])
		#expect(fileVisitor.instantiables.map(\.access.declarationStartLocation) == [
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
		#expect(fileVisitor.instantiables.map(\.access.level) == [.public])
		#expect(fileVisitor.instantiables.map(\.initializer?.access.level) == [.internal])
		#expect(fileVisitor.instantiables.map(\.initializer?.access.modifierRange) == [nil])
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
		#expect(fileVisitor.instantiables.map(\.access.level) == [.public])
		#expect(fileVisitor.instantiables.map(\.access.modifierRange) == [
			Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
		])
		#expect(fileVisitor.instantiables.map(\.access.declarationStartLocation) == [
			Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
		])
	}

	@Test
	func walk_recordsMockDeclarationAccessOfType_whenMockMethodIsDeclaredInType() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable
		package struct Service: Instantiable {
		    public init() {}

		    public static func mock() -> Service {
		        Service()
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.mockDeclarationAccess) == [
			AccessDeclaration(
				level: .package,
				modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 8),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
			),
		])
	}

	@Test
	func walk_recordsMockDeclarationAccessOfExtension_whenMockOnlyExtensionSpellsAccessModifierAndMockSpellsNone() {
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
		#expect(fileVisitor.instantiables.map(\.mockDeclarationAccess) == [
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
				isExtension: true,
			),
		])
		#expect(fileVisitor.instantiables.map(\.mockInitializer?.access.level) == [.internal])
	}

	@Test
	func walk_recordsMockDeclarationAccessOfExtension_whenExtensionDeclaresMockAfterInstantiate() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable(conformsElsewhere: true)
		package extension Service {
		    public static func instantiate() -> Service {
		        Service()
		    }

		    static func mock() -> Service {
		        Service()
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.mockDeclarationAccess) == [
			AccessDeclaration(
				level: .package,
				modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 8),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
				isExtension: true,
			),
		])
		#expect(fileVisitor.instantiables.map(\.mockInitializer?.access.level) == [.internal])
	}

	@Test
	func walk_recordsMockDeclarationAccessOfExtension_whenExtensionDeclaresMockBeforeInstantiate() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable(conformsElsewhere: true)
		package extension Service {
		    static func mock() -> Service {
		        Service()
		    }

		    public static func instantiate() -> Service {
		        Service()
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.mockDeclarationAccess) == [
			AccessDeclaration(
				level: .package,
				modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 8),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
				isExtension: true,
			),
		])
		#expect(fileVisitor.instantiables.map(\.mockInitializer?.access.level) == [.internal])
	}

	@Test
	func walk_recordsEnclosingTypeAccess_whenTypeIsNestedInEnumSpellingNoAccessModifier() {
		let syntaxTree = Parser.parse(source: """
		enum Namespace {
		    @Instantiable
		    public struct Inner: Instantiable {
		        public init() {}
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.enclosingTypeAccess) == [
			[
				AccessDeclaration(
					level: .internal,
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
				),
			],
		])
		#expect(fileVisitor.instantiables.map(\.enclosingExtensionAccess) == [nil])
	}

	@Test
	func walk_recordsEnclosingExtensionAccess_whenTypeIsDeclaredDirectlyInExtensionSpellingAccessModifier() {
		let syntaxTree = Parser.parse(source: """
		public extension Outer {
		    @Instantiable
		    struct Inner: Instantiable {
		        public init() {}
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.enclosingExtensionAccess) == [
			AccessDeclaration(
				level: .public,
				modifierRange: Dependency.SourceRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 7),
				declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
				isExtension: true,
			),
		])
		#expect(fileVisitor.instantiables.map(\.enclosingTypeAccess) == [[]])
	}

	@Test
	func walk_recordsEnclosingTypeAccessOutermostFirst_whenTypeIsNestedTwoLevelsDeep() {
		let syntaxTree = Parser.parse(source: """
		public enum Outer {
		    struct Middle {
		        @Instantiable
		        public struct Inner: Instantiable {
		            public init() {}
		        }
		    }
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.instantiables.map(\.enclosingTypeAccess) == [
			[
				AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 7),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
				),
				AccessDeclaration(
					level: .internal,
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 5),
				),
			],
		])
	}

	@Test
	func walk_recordsPlainTypeDeclarationsWithEnclosingAccess_insideIfBlocksAndExtensionsToo() {
		// A declaration inside a platform-conditioned `#if` block is recorded from every clause the compiler could select,
		// as one outside every block is, and one directly inside an extension with the extension's access, which its level
		// takes when it spells none.
		let syntaxTree = Parser.parse(source: """
		public enum Outer {
		    struct Middle {}
		    @Instantiable
		    public struct Inner: Instantiable {
		        public init() {}
		        package enum Deep {}
		    }
		    #if os(macOS)
		    enum Platform {}
		    #else
		    enum Platform {}
		    #endif
		}
		public extension Outer {
		    enum Extended {}
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		let outerAccess = AccessDeclaration(
			level: .public,
			modifierRange: Dependency.SourceRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 7),
			declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
		)
		#expect(fileVisitor.plainTypeDeclarations == [
			PlainTypeDeclaration(typeDescription: .simple(name: "Outer"), access: outerAccess, enclosingTypeAccess: []),
			PlainTypeDeclaration(
				typeDescription: .nested(name: "Middle", parentType: .simple(name: "Outer")),
				access: AccessDeclaration(
					level: .internal,
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 5),
				),
				enclosingTypeAccess: [outerAccess],
			),
			PlainTypeDeclaration(
				typeDescription: .nested(name: "Deep", parentType: .nested(name: "Inner", parentType: .simple(name: "Outer"))),
				access: AccessDeclaration(
					level: .package,
					modifierRange: Dependency.SourceRange(startLine: 6, startColumn: 9, endLine: 6, endColumn: 16),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 6, column: 9),
				),
				enclosingTypeAccess: [
					outerAccess,
					AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 4, startColumn: 5, endLine: 4, endColumn: 11),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 4, column: 5),
					),
				],
			),
			PlainTypeDeclaration(
				typeDescription: .nested(name: "Platform", parentType: .simple(name: "Outer")),
				access: AccessDeclaration(level: .internal, declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 5)),
				enclosingTypeAccess: [outerAccess],
			),
			PlainTypeDeclaration(
				typeDescription: .nested(name: "Platform", parentType: .simple(name: "Outer")),
				access: AccessDeclaration(level: .internal, declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 11, column: 5)),
				enclosingTypeAccess: [outerAccess],
			),
			PlainTypeDeclaration(
				typeDescription: .nested(name: "Extended", parentType: .simple(name: "Outer")),
				access: AccessDeclaration(level: .internal, declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 15, column: 5)),
				enclosingTypeAccess: [],
				enclosingExtensionAccess: AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 14, startColumn: 1, endLine: 14, endColumn: 7),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 14, column: 1),
					isExtension: true,
				),
			),
		])
	}

	@Test
	func walk_recordsProtocolDeclarations_insideExtensionsToo_andNotInsideClausesTheConditionsSkip() {
		// `DEBUG` is not active, so the clause that declares `Guarded` is skipped, and nothing records it.
		let syntaxTree = Parser.parse(source: """
		package protocol FeedService {}
		public enum Outer {
		    protocol Nested {}
		}
		#if DEBUG
		protocol Guarded {}
		#endif
		extension Outer {
		    protocol Extended {}
		}
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		let outerAccess = AccessDeclaration(
			level: .public,
			modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 7),
			declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
		)
		#expect(fileVisitor.plainTypeDeclarations == [
			PlainTypeDeclaration(
				typeDescription: .simple(name: "FeedService"),
				access: AccessDeclaration(
					level: .package,
					modifierRange: Dependency.SourceRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 8),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
				),
				enclosingTypeAccess: [],
			),
			PlainTypeDeclaration(typeDescription: .simple(name: "Outer"), access: outerAccess, enclosingTypeAccess: []),
			PlainTypeDeclaration(
				typeDescription: .nested(name: "Nested", parentType: .simple(name: "Outer")),
				access: AccessDeclaration(
					level: .internal,
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
				),
				enclosingTypeAccess: [outerAccess],
			),
			PlainTypeDeclaration(
				typeDescription: .nested(name: "Extended", parentType: .simple(name: "Outer")),
				access: AccessDeclaration(level: .internal, declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 5)),
				enclosingTypeAccess: [],
				enclosingExtensionAccess: AccessDeclaration(
					level: .internal,
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 8, column: 1),
					isExtension: true,
				),
			),
		])
	}

	@Test
	func walk_recordsTypealiasDeclarations_atTopLevelInTypeBodiesAndInsideExtensions_andNotInsideClausesTheConditionsSkip() {
		// C9: a typealias is recorded as any plain type is, with its spelled chain; `DEBUG` is not active, so `Debug` is not.
		let syntaxTree = Parser.parse(source: """
		public typealias UserID = String
		package enum Space {
		    public typealias ID = Int
		}
		extension Space {
		    typealias Handler = () -> Void
		}
		#if DEBUG
		typealias Debug = Bool
		#endif
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		let spaceAccess = AccessDeclaration(
			level: .package,
			modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 8),
			declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
		)
		#expect(fileVisitor.plainTypeDeclarations == [
			PlainTypeDeclaration(
				typeDescription: .simple(name: "UserID"),
				access: AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 7),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
				),
				enclosingTypeAccess: [],
			),
			PlainTypeDeclaration(typeDescription: .simple(name: "Space"), access: spaceAccess, enclosingTypeAccess: []),
			PlainTypeDeclaration(
				typeDescription: .nested(name: "ID", parentType: .simple(name: "Space")),
				access: AccessDeclaration(
					level: .public,
					modifierRange: Dependency.SourceRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 11),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 3, column: 5),
				),
				enclosingTypeAccess: [spaceAccess],
			),
			PlainTypeDeclaration(
				typeDescription: .nested(name: "Handler", parentType: .simple(name: "Space")),
				access: AccessDeclaration(level: .internal, declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 6, column: 5)),
				enclosingTypeAccess: [],
				enclosingExtensionAccess: AccessDeclaration(
					level: .internal,
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 5, column: 1),
					isExtension: true,
				),
			),
		])
	}

	@Test
	func walk_recordsPlainTypeDeclarationsOfClausesEitherValueOfMockConditionSelects_whenBlockGuardsMockOnlyDeclarations() {
		// PR1: both blocks guard mock-only declarations, and SafeDI reads the mock condition in them as a platform condition
		// for plain declarations. No condition up to `Shown`'s clause mentions `DEBUG`, so either value selects it; where
		// `DEBUG` is active the first block's `#elseif` declares `Token` and `Token.Flagged`, and where it is inactive no
		// clause declares more. The second block declares `Hidden` where `DEBUG` is active and `Visible` where it is not:
		// both are recorded, in source order.
		let syntaxTree = Parser.parse(source: """
		#if os(Linux)
		@Instantiable(mockOnly: true)
		extension Fake {
		    public static func mock() -> Fake { Fake() }
		}
		public struct Shown {}
		#elseif DEBUG
		@Instantiable(mockOnly: true)
		extension Fake {
		    public static func mock() -> Fake { Fake() }
		}
		public struct Token {
		    #if FLAG
		    struct Flagged {}
		    #endif
		}
		#endif
		#if !DEBUG
		public struct Visible {}
		#else
		@Instantiable(mockOnly: true)
		extension Hidden {
		    public static func mock() -> Hidden { Hidden() }
		}
		public struct Hidden {}
		#endif
		public struct After {}
		""")
		let fileVisitor = FileVisitor(conditionalCompilationEvaluator: ConditionalCompilationEvaluator(activeCompilationConditions: ["FLAG"]))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.plainTypeDeclarations.map(\.typeDescription.asSource) == ["Shown", "Token", "Token.Flagged", "Visible", "Hidden", "After"])
		#expect(fileVisitor.conditionalCompilationDecisions.isEmpty)
	}

	@Test
	func walk_recordsDeclarationWithItsLocation_whenOnlyBuildWithoutMockConditionSelectsItsClause() {
		// PR2 (Probe D): where `DEBUG` is active the block declares `Endpoint` `public`, and where it is inactive `package`.
		// Both are recorded, each with its own location, whatever the conditions report, and nothing is asserted.
		let source = """
		#if DEBUG
		@Instantiable(mockOnly: true)
		extension Fake {
		    public static func mock() -> Fake { Fake() }
		}
		public struct Endpoint {}
		#else
		package struct Endpoint {}
		#endif
		"""
		for conditions: Set<String> in [[], ["DEBUG"]] {
			let syntaxTree = Parser.parse(source: source)
			let fileVisitor = FileVisitor(
				conditionalCompilationEvaluator: ConditionalCompilationEvaluator(activeCompilationConditions: conditions),
				sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree),
			)
			fileVisitor.walk(syntaxTree)
			#expect(fileVisitor.plainTypeDeclarations == [
				PlainTypeDeclaration(
					typeDescription: .simple(name: "Endpoint"),
					access: AccessDeclaration(
						level: .public,
						modifierRange: Dependency.SourceRange(startLine: 6, startColumn: 1, endLine: 6, endColumn: 7),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 6, column: 1),
					),
					enclosingTypeAccess: [],
				),
				PlainTypeDeclaration(
					typeDescription: .simple(name: "Endpoint"),
					access: AccessDeclaration(
						level: .package,
						modifierRange: Dependency.SourceRange(startLine: 8, startColumn: 1, endLine: 8, endColumn: 8),
						declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 8, column: 1),
					),
					enclosingTypeAccess: [],
				),
			])
			#expect(fileVisitor.conditionalCompilationDecisions.isEmpty)
			#expect(fileVisitor.plainTypeDeclarationDecisions.isEmpty)
			#expect(fileVisitor.consultedCompilationConditions.isEmpty)
		}
	}

	@Test
	func walk_recordsOnlyClauseMockConditionSelects_whenNoOtherClauseDeclaresAnything() {
		// PR3 (Dan's shape, the declaring file): the block has no `#else`, or an empty one, so a build where `DEBUG` is
		// inactive declares nothing here; another file's `#if !DEBUG` may.
		for elseClause in ["", "#else\n"] {
			let syntaxTree = Parser.parse(source: """
			#if DEBUG
			@Instantiable(mockOnly: true)
			extension Fake {
			    public static func mock() -> Fake { Fake() }
			}
			public struct Endpoint {}
			\(elseClause)#endif
			""")
			let fileVisitor = FileVisitor()
			fileVisitor.walk(syntaxTree)
			#expect(fileVisitor.plainTypeDeclarations.map { [$0.typeDescription.asSource, $0.access.level.spelling] } == [["Endpoint", "public"]])
		}
	}

	@Test
	func walk_recordsOnlyReportedSelection_whenModuleGeneratesMocksUnconditionally() {
		// PR4: without a mock condition, a block that guards mock-only declarations is read with the reported conditions, as
		// production code is, so its `#else` is not read where `DEBUG` is reported.
		let syntaxTree = Parser.parse(source: """
		#if DEBUG
		@Instantiable(mockOnly: true)
		extension Fake {
		    public static func mock() -> Fake { Fake() }
		}
		public struct Token {}
		#else
		package struct Token {}
		#endif
		""")
		let fileVisitor = FileVisitor(conditionalCompilationEvaluator: ConditionalCompilationEvaluator(activeCompilationConditions: ["DEBUG"], mockConditionalCompilation: nil))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.plainTypeDeclarations.map { [$0.typeDescription.asSource, $0.access.level.spelling] } == [["Token", "public"]])
	}

	@Test
	func walk_recordsEveryClauseOfNestedBlocks_whenBuildWithoutMockConditionSelectsThem() {
		// PR5: where `DEBUG` is inactive, the `#else` clause declares `Theme` as the `#if` clause does, `Wider` in each clause
		// of a platform block of its own, `Space` `package` with its `Config`, and `Missing` `private`. Each is recorded with
		// the level it spells, in source order, after the `#if` clause's.
		let syntaxTree = Parser.parse(source: """
		#if DEBUG
		@Instantiable(mockOnly: true)
		extension Fake {
		    public static func mock() -> Fake { Fake() }
		}
		public struct Theme {}
		package struct Wider {}
		public enum Space {
		    public struct Config {}
		}
		public struct Missing {}
		#else
		public struct Theme {}
		#if os(Linux)
		open class Wider {}
		#else
		public struct Wider {}
		#endif
		package enum Space {
		    public struct Config {}
		}
		private struct Missing {}
		#endif
		""")
		let fileVisitor = FileVisitor()
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.plainTypeDeclarations.map { [$0.typeDescription.asSource, $0.access.level.spelling] } == [
			["Theme", "public"],
			["Wider", "package"],
			["Space", "public"],
			["Space.Config", "public"],
			["Missing", "public"],
			["Theme", "public"],
			["Wider", "open"],
			["Wider", "public"],
			["Space", "package"],
			["Space.Config", "public"],
			["Missing", "private"],
		])
	}

	@Test
	func walk_recordsDeclarationsInExtensionAndNestedType_whenBuildWithoutMockConditionSelectsTheirClause() {
		// PR6: the blocks are inside `Space`'s body and inside a `package` extension of `Kit`: the `#else` clauses'
		// declarations are named and leveled as the `#if` clauses' are.
		let syntaxTree = Parser.parse(source: """
		public enum Space {
		    #if DEBUG
		    @Instantiable(mockOnly: true)
		    public final class Probe {
		        public static func mock() -> Probe { Probe() }
		    }
		    public struct Config {}
		    #else
		    package struct Config {}
		    #endif
		}
		package extension Kit {
		    #if DEBUG
		    @Instantiable(mockOnly: true)
		    final class Probe {
		        static func mock() -> Probe { Probe() }
		    }
		    struct Theme {}
		    #else
		    struct Theme {}
		    #endif
		}
		""")
		let fileVisitor = FileVisitor()
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.plainTypeDeclarations.map { [$0.typeDescription.asSource, $0.levelBeforeExtendedTypeCap.spelling] } == [
			["Space", "public"],
			["Space.Config", "public"],
			["Space.Config", "package"],
			["Kit.Theme", "package"],
			["Kit.Theme", "package"],
		])
	}

	@Test
	func walk_consultsAndRecordsDecisionsOfNestedFlagBlocks_whenBuildWithoutMockConditionSelectsTheirClause() {
		// PR7: where `DEBUG` is active, `FLAG` and `STAGING` decide nothing, but where it is inactive `FLAG` selects the
		// `#elseif` and `STAGING` decides the level of the nested block's `Theme`. The decisions of that selection are kept
		// with the types each block declares, as those of a block that guards nothing else SafeDI reads are, for the module
		// to consult and assert when it keeps such a declaration: not among the file's own. The nested `#if DEBUG`, which no
		// build compiles, reports no decision: SafeDI takes `DEBUG` to be inactive there whatever the conditions report.
		let syntaxTree = Parser.parse(source: """
		#if DEBUG
		@Instantiable(mockOnly: true)
		extension Fake {
		    public static func mock() -> Fake { Fake() }
		}
		public struct Theme {}
		#elseif FLAG
		#if STAGING
		public struct Theme {}
		#else
		package struct Theme {}
		#endif
		#if DEBUG
		public struct Unreachable {}
		#endif
		#endif
		""")
		let fileVisitor = FileVisitor(conditionalCompilationEvaluator: ConditionalCompilationEvaluator(activeCompilationConditions: ["FLAG", "DEBUG"]))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.plainTypeDeclarations.map { [$0.typeDescription.asSource, $0.access.level.spelling] } == [["Theme", "public"], ["Theme", "package"]])
		#expect(fileVisitor.consultedCompilationConditions.isEmpty)
		#expect(fileVisitor.plainTypeDeclarationDecisions == [
			GuardedPlainTypeNames(
				decisions: [ConditionalCompilationDecision(condition: "FLAG", isActive: true)],
				consultedConditions: ["FLAG"],
				declaredTypes: [
					GuardedPlainTypeNames.DeclaredType(name: "Theme", outermostName: "Theme", level: .package),
					GuardedPlainTypeNames.DeclaredType(name: "Theme", outermostName: "Theme", level: .public),
					GuardedPlainTypeNames.DeclaredType(name: "Unreachable", outermostName: "Unreachable", level: .public),
				],
			),
			GuardedPlainTypeNames(
				decisions: [ConditionalCompilationDecision(condition: "STAGING", isActive: false)],
				consultedConditions: ["STAGING"],
				declaredTypes: [
					GuardedPlainTypeNames.DeclaredType(name: "Theme", outermostName: "Theme", level: .package),
					GuardedPlainTypeNames.DeclaredType(name: "Theme", outermostName: "Theme", level: .public),
				],
			),
		])
		#expect(fileVisitor.conditionalCompilationDecisions.isEmpty)
	}

	@Test
	func walk_recordsPlainTypeDeclarationsOfSelectedClauseOnly_whenFlagDecidesBlock() {
		// IF23: `FLAG` is active, so the `#if` clause is the one the compiler selects, and only its declaration is recorded.
		let syntaxTree = Parser.parse(source: """
		#if FLAG
		package struct Token {}
		#else
		public struct Token {}
		#endif
		""")
		let fileVisitor = FileVisitor(
			conditionalCompilationEvaluator: ConditionalCompilationEvaluator(activeCompilationConditions: ["FLAG"]),
			sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree),
		)
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.plainTypeDeclarations == [
			PlainTypeDeclaration(
				typeDescription: .simple(name: "Token"),
				access: AccessDeclaration(
					level: .package,
					modifierRange: Dependency.SourceRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 8),
					declarationStartLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 1),
				),
				enclosingTypeAccess: [],
			),
		])
		#expect(fileVisitor.plainTypeDeclarationDecisions == [
			GuardedPlainTypeNames(
				decisions: [ConditionalCompilationDecision(condition: "FLAG", isActive: true)],
				consultedConditions: ["FLAG"],
				declaredTypes: [
					GuardedPlainTypeNames.DeclaredType(name: "Token", outermostName: "Token", level: .package),
					GuardedPlainTypeNames.DeclaredType(name: "Token", outermostName: "Token", level: .public),
				],
			),
		])
	}

	@Test
	func walk_pairsDecisionsWithTypesBlockDeclaresInAnyClause_whenBlockHoldsNothingElseSafeDIReads() {
		// IF23: the block's decisions and the conditions it consulted are kept with the plain types it declares in any
		// clause, nested blocks' included – each one's own name, outermost name and level – rather than among the file's,
		// for the module to consult and assert when it keeps such a declaration. The platform block decides nothing.
		let syntaxTree = Parser.parse(source: """
		public enum Space {
		    #if FLAG
		    struct Config {}
		    #else
		    #if os(Linux)
		    package struct Config {}
		    #endif
		    #endif
		}
		#if !OTHER
		public struct Theme {}
		#endif
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.plainTypeDeclarationDecisions == [
			GuardedPlainTypeNames(
				decisions: [ConditionalCompilationDecision(condition: "FLAG", isActive: false)],
				consultedConditions: ["FLAG"],
				declaredTypes: [
					GuardedPlainTypeNames.DeclaredType(name: "Config", outermostName: "Space", level: .internal),
					GuardedPlainTypeNames.DeclaredType(name: "Config", outermostName: "Space", level: .package),
				],
			),
			GuardedPlainTypeNames(
				decisions: [ConditionalCompilationDecision(condition: "!OTHER", isActive: true)],
				consultedConditions: ["OTHER"],
				declaredTypes: [GuardedPlainTypeNames.DeclaredType(name: "Theme", outermostName: "Theme", level: .public)],
			),
		])
		#expect(fileVisitor.conditionalCompilationDecisions.isEmpty)
		#expect(fileVisitor.consultedCompilationConditions.isEmpty)
	}

	@Test
	func walk_keepsConditionWithBlock_whenBlockDeclaresPlainTypeInSkippedClause() {
		// IF23: the block's only clause is skipped, so nothing is recorded, but the condition that skipped it is kept with
		// the block, which the module consults when it keeps a declaration of `Token`: another value would record it.
		let syntaxTree = Parser.parse(source: """
		#if FLAG
		struct Token {}
		#endif
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.plainTypeDeclarations.isEmpty)
		#expect(fileVisitor.consultedCompilationConditions.isEmpty)
		#expect(fileVisitor.plainTypeDeclarationDecisions == [
			GuardedPlainTypeNames(
				decisions: [ConditionalCompilationDecision(condition: "FLAG", isActive: false)],
				consultedConditions: ["FLAG"],
				declaredTypes: [GuardedPlainTypeNames.DeclaredType(name: "Token", outermostName: "Token", level: .internal)],
			),
		])
	}

	@Test
	func walk_keepsConditionOfImportBlockWithBlock_whenItAlsoDeclaresPlainType() {
		// IF23: a block that holds an import and a plain declaration keeps its condition with the block for what the file
		// contributes, not only among the conditions that decide its imports.
		let syntaxTree = Parser.parse(source: """
		#if FLAG
		import Foundation
		struct Token {}
		#endif
		""")
		let fileVisitor = FileVisitor(sourceLocationConverter: SourceLocationConverter(fileName: "File.swift", tree: syntaxTree))
		fileVisitor.walk(syntaxTree)
		#expect(fileVisitor.consultedCompilationConditions.isEmpty)
		#expect(fileVisitor.importOnlyConsultedCompilationConditions == ["FLAG"])
		#expect(fileVisitor.plainTypeDeclarationDecisions == [
			GuardedPlainTypeNames(
				decisions: [ConditionalCompilationDecision(condition: "FLAG", isActive: false)],
				consultedConditions: ["FLAG"],
				declaredTypes: [GuardedPlainTypeNames.DeclaredType(name: "Token", outermostName: "Token", level: .internal)],
			),
		])
	}

	@Test
	func walk_recordsOutermostNameOfEachTypeExtendedByExtensionThatIsOrHoldsInstantiable_inEveryClause() {
		let syntaxTree = Parser.parse(source: """
		@Instantiable
		extension Rack: Instantiable {
		    public static func instantiate() -> Rack { Rack() }
		}
		extension Outer.Space {
		    @Instantiable
		    public final class Shelf: Instantiable {
		        public init() {}
		    }
		}
		extension Cabinet {
		    #if DEBUG
		    @Instantiable
		    public final class Drawer: Instantiable {
		        public init() {}
		    }
		    #endif
		}
		#if DEBUG
		extension Closet {
		    @Instantiable
		    public final class Hanger: Instantiable {
		        public init() {}
		    }
		}
		@Instantiable
		extension Crate: Instantiable {
		    public static func instantiate() -> Crate { Crate() }
		}
		#endif
		extension Unrelated {
		    func describe() {}
		}
		@Instantiable
		extension [Pallet]: Instantiable {
		    public static func instantiate() -> [Pallet] { [] }
		}
		""")
		let fileVisitor = FileVisitor()
		fileVisitor.walk(syntaxTree)
		// A type spelled with sugar, such as `[Pallet]`, is declared nowhere SafeDI reads, and records no name.
		#expect(fileVisitor.outputFileDeclarations.extendedTypeNames == ["Rack", "Outer", "Cabinet", "Closet", "Crate"])
	}
}
