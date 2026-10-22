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
		#expect(configuration.activeCompilationConditions == [])
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
	func extractConfiguration_returnsActiveCompilationConditions() {
		let configuration = extractConfiguration(from: """
		#SafeDIConfiguration(
		    activeCompilationConditions: ["STAGING", "FEATURE_FLAG"]
		)
		""")
		#expect(configuration.activeCompilationConditions == ["STAGING", "FEATURE_FLAG"])
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
						identifierRange: Dependency.SourceRange(
							start: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 28),
							end: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 32),
						),
						typeAnnotationRange: Dependency.SourceRange(
							start: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 34),
							end: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 38),
						),
						bareAttributeRange: Dependency.SourceRange(
							start: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 5),
							end: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 15),
						),
					),
					Dependency(
						property: Property(
							label: "networkService",
							typeDescription: .simple(name: "NetworkService"),
						),
						source: .received(onlyIfAvailable: false),
						declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 11, column: 5),
						identifierRange: Dependency.SourceRange(
							start: Dependency.DeclarationLocation(filePath: "File.swift", line: 11, column: 19),
							end: Dependency.DeclarationLocation(filePath: "File.swift", line: 11, column: 33),
						),
						typeAnnotationRange: Dependency.SourceRange(
							start: Dependency.DeclarationLocation(filePath: "File.swift", line: 11, column: 35),
							end: Dependency.DeclarationLocation(filePath: "File.swift", line: 11, column: 49),
						),
						bareAttributeRange: Dependency.SourceRange(
							start: Dependency.DeclarationLocation(filePath: "File.swift", line: 11, column: 5),
							end: Dependency.DeclarationLocation(filePath: "File.swift", line: 11, column: 14),
						),
					),
				],
				declarationType: .classType,
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
						identifierRange: Dependency.SourceRange(
							start: Dependency.DeclarationLocation(filePath: "File.swift", line: 7, column: 28),
							end: Dependency.DeclarationLocation(filePath: "File.swift", line: 7, column: 32),
						),
						typeAnnotationRange: Dependency.SourceRange(
							start: Dependency.DeclarationLocation(filePath: "File.swift", line: 7, column: 34),
							end: Dependency.DeclarationLocation(filePath: "File.swift", line: 7, column: 38),
						),
						bareAttributeRange: Dependency.SourceRange(
							start: Dependency.DeclarationLocation(filePath: "File.swift", line: 7, column: 5),
							end: Dependency.DeclarationLocation(filePath: "File.swift", line: 7, column: 15),
						),
					),
					Dependency(
						property: Property(
							label: "networkService",
							typeDescription: .simple(name: "NetworkService"),
						),
						source: .received(onlyIfAvailable: false),
						declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 5),
						identifierRange: Dependency.SourceRange(
							start: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 19),
							end: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 33),
						),
						typeAnnotationRange: Dependency.SourceRange(
							start: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 35),
							end: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 49),
						),
						bareAttributeRange: Dependency.SourceRange(
							start: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 5),
							end: Dependency.DeclarationLocation(filePath: "File.swift", line: 9, column: 14),
						),
					),
				],
				declarationType: .classType,
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
			Instantiable(
				instantiableType: .simple(name: "SomeOtherInstantiable"),
				isRoot: false,
				initializer: Initializer(arguments: []),
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
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
				initializer: Initializer(arguments: []),
				additionalInstantiables: [
					.simple(name: "SomeProtocol"),
				],
				dependencies: [],
				declarationType: .structType,
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(arguments: []),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
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
				initializer: Initializer(arguments: []),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .extensionType,
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(arguments: []),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
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
				initializer: Initializer(arguments: []),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .extensionType,
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel1", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(arguments: []),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .actorType,
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 4, column: 5),
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel2", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(arguments: []),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .classType,
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 8, column: 5),
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel3", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(arguments: []),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
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
				initializer: Initializer(arguments: []),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
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
			),
		])
		#expect(fileVisitor.instantiables == [
			Instantiable(
				instantiableType: .simple(name: "SomeService"),
				isRoot: false,
				initializer: Initializer(arguments: []),
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
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
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 2, column: 5),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 6, column: 9),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 10, column: 13),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 14, column: 17),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 18, column: 21),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 22, column: 25),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 26, column: 29),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 30, column: 33),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 34, column: 37),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 38, column: 41),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 42, column: 45),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 46, column: 49),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 50, column: 53),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 54, column: 57),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 58, column: 61),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 62, column: 65),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 66, column: 69),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested"))))))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 70, column: 73),
			),
			Instantiable(
				instantiableType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .nested(name: "Nested", parentType: .simple(name: "Nested")))))))))))))))))))),
				isRoot: false,
				initializer: Initializer(
					isPublicOrOpen: true,
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
				initializer: Initializer(arguments: []),
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
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
				initializer: Initializer(arguments: []),
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
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
				initializer: Initializer(arguments: []),
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
				declarationLocation: Dependency.DeclarationLocation(filePath: "File.swift", line: 1, column: 1),
			),
		])
	}
}
