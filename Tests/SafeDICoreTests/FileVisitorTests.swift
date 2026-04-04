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
	func nestedStructWithMatchingPropertyNameDoesNotOverrideOuterConfig() {
		let visitor = SafeDIConfigurationVisitor()
		visitor.walk(Parser.parse(source: """
		enum MyConfig {
		    static let additionalImportedModules: [StaticString] = []
		    static let additionalDirectoriesToInclude: [StaticString] = []
		    static let generateMocks: Bool = true
		    static let mockConditionalCompilation: StaticString? = "DEBUG"

		    struct Helper {
		        static let generateMocks: Bool = false
		    }
		}
		"""))

		#expect(visitor.generateMocks == true)
	}

	@Test
	func nestedClassWithMatchingPropertyNameDoesNotOverrideOuterConfig() {
		let visitor = SafeDIConfigurationVisitor()
		visitor.walk(Parser.parse(source: """
		enum MyConfig {
		    static let additionalImportedModules: [StaticString] = []
		    static let additionalDirectoriesToInclude: [StaticString] = []
		    static let generateMocks: Bool = true
		    static let mockConditionalCompilation: StaticString? = "DEBUG"

		    class Helper {
		        static let generateMocks: Bool = false
		    }
		}
		"""))

		#expect(visitor.generateMocks == true)
	}

	@Test
	func nestedEnumWithMatchingPropertyNameDoesNotOverrideOuterConfig() {
		let visitor = SafeDIConfigurationVisitor()
		visitor.walk(Parser.parse(source: """
		enum MyConfig {
		    static let additionalImportedModules: [StaticString] = []
		    static let additionalDirectoriesToInclude: [StaticString] = []
		    static let generateMocks: Bool = true
		    static let mockConditionalCompilation: StaticString? = "DEBUG"

		    enum Helper {
		        static let generateMocks: Bool = false
		    }
		}
		"""))

		#expect(visitor.generateMocks == true)
	}

	@Test
	func nestedActorWithMatchingPropertyNameDoesNotOverrideOuterConfig() {
		let visitor = SafeDIConfigurationVisitor()
		visitor.walk(Parser.parse(source: """
		enum MyConfig {
		    static let additionalImportedModules: [StaticString] = []
		    static let additionalDirectoriesToInclude: [StaticString] = []
		    static let generateMocks: Bool = true
		    static let mockConditionalCompilation: StaticString? = "DEBUG"

		    actor Helper {
		        static let generateMocks: Bool = false
		    }
		}
		"""))

		#expect(visitor.generateMocks == true)
	}
}

struct FileVisitorTests {
	@Test
	func walk_findsInstantiable() {
		let fileVisitor = FileVisitor()
		fileVisitor.walk(Parser.parse(source: """
		import UIKit

		@Instantiable
		public final class LoggedInViewController: UIViewController {
		    public init(user: User, networkService: NetworkService) {
		        fatalError("SafeDI doesn't inspect the initializer body")
		    }

		    @Forwarded private let user: User

		    @Received let networkService: NetworkService
		}
		"""))
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
					),
					Dependency(
						property: Property(
							label: "networkService",
							typeDescription: .simple(name: "NetworkService"),
						),
						source: .received(onlyIfAvailable: false),
					),
				],
				declarationType: .classType,
			),
		])
	}

	@Test
	func walk_findsMultipleInstantiables() {
		let fileVisitor = FileVisitor()
		fileVisitor.walk(Parser.parse(source: """
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
		"""))
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
					),
					Dependency(
						property: Property(
							label: "networkService",
							typeDescription: .simple(name: "NetworkService"),
						),
						source: .received(onlyIfAvailable: false),
					),
				],
				declarationType: .classType,
			),
			Instantiable(
				instantiableType: .simple(name: "SomeOtherInstantiable"),
				isRoot: false,
				initializer: Initializer(arguments: []),
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
			),
		])
	}

	@Test
	func walk_findsInstantiableNestedInOuterInstantiableConcreteDeclaration() {
		let fileVisitor = FileVisitor()
		fileVisitor.walk(Parser.parse(source: """
		@Instantiable(fulfillingAdditionalTypes: [SomeProtocol.self])
		public struct OuterLevel: SomeProtocol {
		    public init() {}

		    @Instantiable
		    public struct InnerLevel {
		        public init() {}
		    }
		}
		"""))
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
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(arguments: []),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
			),
		])
	}

	@Test
	func walk_findsInstantiableNestedInOuterExtendedInstantiable() {
		let fileVisitor = FileVisitor()
		fileVisitor.walk(Parser.parse(source: """
		extension OuterLevel {
		    public static func instantiate() -> OuterLevel { fatalError() }

		    @Instantiable
		    public struct InnerLevel {
		        public init() {}
		    }
		}
		"""))
		#expect(fileVisitor.instantiables == [
			Instantiable(
				instantiableType: .simple(name: "OuterLevel"),
				isRoot: false,
				initializer: Initializer(arguments: []),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .extensionType,
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(arguments: []),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
			),
		])
	}

	@Test
	func walk_findsInstantiablesNestedInOuterExtendedInstantiable() {
		let fileVisitor = FileVisitor()
		fileVisitor.walk(Parser.parse(source: """
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
		"""))
		#expect(fileVisitor.instantiables == [
			Instantiable(
				instantiableType: .simple(name: "OuterLevel"),
				isRoot: false,
				initializer: Initializer(arguments: []),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .extensionType,
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel1", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(arguments: []),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .actorType,
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel2", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(arguments: []),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .classType,
			),
			Instantiable(
				instantiableType: .nested(name: "InnerLevel3", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(arguments: []),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
			),
		])
	}

	@Test
	func walk_findsInstantiableNestedWithinEnum() {
		let fileVisitor = FileVisitor()
		fileVisitor.walk(Parser.parse(source: """
		public enum OuterLevel {
		    @Instantiable
		    public struct InnerLevel {
		        public init() {}
		    }
		}
		"""))
		#expect(fileVisitor.instantiables == [
			Instantiable(
				instantiableType: .nested(name: "InnerLevel", parentType: .simple(name: "OuterLevel")),
				isRoot: false,
				initializer: Initializer(arguments: []),
				additionalInstantiables: [],
				dependencies: [],
				declarationType: .structType,
			),
		])
	}

	@Test
	func walk_findsSafeDIConfiguration() {
		let fileVisitor = FileVisitor()
		fileVisitor.walk(Parser.parse(source: """
		@SafeDIConfiguration
		enum MyConfiguration {
		    static let additionalImportedModules: [StaticString] = ["ModuleA", "ModuleB"]
		    static let additionalDirectoriesToInclude: [StaticString] = ["DirA"]
		}
		"""))
		#expect(fileVisitor.configurations == [
			SafeDIConfiguration(
				additionalImportedModules: ["ModuleA", "ModuleB"],
				additionalDirectoriesToInclude: ["DirA"],
			),
		])
		#expect(fileVisitor.instantiables.isEmpty)
	}

	@Test
	func walk_findsSafeDIConfigurationWithEmptyArrays() {
		let fileVisitor = FileVisitor()
		fileVisitor.walk(Parser.parse(source: """
		@SafeDIConfiguration
		enum MyConfiguration {
		    static let additionalImportedModules: [StaticString] = []
		    static let additionalDirectoriesToInclude: [StaticString] = []
		}
		"""))
		#expect(fileVisitor.configurations == [
			SafeDIConfiguration(
				additionalImportedModules: [],
				additionalDirectoriesToInclude: [],
			),
		])
	}

	@Test
	func walk_findsSafeDIConfigurationWithTupleBinding() {
		let fileVisitor = FileVisitor()
		fileVisitor.walk(Parser.parse(source: """
		@SafeDIConfiguration
		enum MyConfiguration {
		    static let (a, b) = (1, 2)
		    static let additionalImportedModules: [StaticString] = []
		    static let additionalDirectoriesToInclude: [StaticString] = []
		}
		"""))
		#expect(fileVisitor.configurations == [
			SafeDIConfiguration(
				additionalImportedModules: [],
				additionalDirectoriesToInclude: [],
			),
		])
	}

	@Test
	func walk_findsSafeDIConfigurationWithInvalidValues() {
		let fileVisitor = FileVisitor()
		fileVisitor.walk(Parser.parse(source: """
		@SafeDIConfiguration
		enum MyConfiguration {
		    static let additionalImportedModules: [StaticString] = someVariable
		    static let additionalDirectoriesToInclude: [StaticString] = anotherVariable
		}
		"""))
		#expect(fileVisitor.configurations == [
			SafeDIConfiguration(
				additionalImportedModules: [],
				additionalDirectoriesToInclude: [],
			),
		])
	}

	@Test
	func walk_findsSafeDIConfigurationAlongsideInstantiable() {
		let fileVisitor = FileVisitor()
		fileVisitor.walk(Parser.parse(source: """
		@SafeDIConfiguration
		enum MyConfiguration {
		    static let additionalImportedModules: [StaticString] = ["ModuleA"]
		    static let additionalDirectoriesToInclude: [StaticString] = []
		}

		@Instantiable
		public struct SomeService {
		    public init() {}
		}
		"""))
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
			),
		])
	}

	@Test
	func walk_findsDeeplyNestedInstantiables() {
		let fileVisitor = FileVisitor()
		fileVisitor.walk(Parser.parse(source: """
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
		"""))
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
			),
		])
	}
}
