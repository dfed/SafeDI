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

import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

#if canImport(SafeDIMacros)
	@testable import SafeDIMacros

	/// A dependency's type that names, unqualified, a type declared in the declaration `@Instantiable` decorates,
	/// which the code SafeDI generates in another type's extension cannot resolve.
	struct InstantiableMacroNestedTypeTests {
		// MARK: Tests

		@Test
		func declaration_producesWarningThatQualifiesNestedType_whenForwardedPropertyNamesNestedTypeUnqualified() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public struct Config {}

				    public init(config: Config) {
				        self.config = config
				    }

				    @Forwarded let config: Config
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public struct Config {}

				    public init(config: Config) {
				        self.config = config
				    }

				    let config: Config

				    public typealias ForwardedProperties = Config
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The generated code that builds or receives `config` lives in another type’s extension, where `Config`, declared in `Child`, does not resolve. Write it as `Child.Config`.",
						line: 9,
						column: 28,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Config` with `Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Config` with `Child.Config`"],
				fixedSource: """
				@Instantiable
				public final class Child: Instantiable {
				    public struct Config {}

				    public init(config: Child.Config) {
				        self.config = config
				    }

				    @Forwarded let config: Child.Config
				}
				""",
			)
		}

		@Test
		func declaration_producesWarningThatQualifiesNestedType_whenReceivedPropertyNamesNestedTypeUnqualified() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public struct Settings {}

				    public init(settings: Settings) {
				        self.settings = settings
				    }

				    @Received let settings: Settings
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public struct Settings {}

				    public init(settings: Settings) {
				        self.settings = settings
				    }

				    let settings: Settings
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The generated code that builds or receives `settings` lives in another type’s extension, where `Settings`, declared in `Child`, does not resolve. Write it as `Child.Settings`.",
						line: 9,
						column: 29,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Settings` with `Child.Settings`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Settings` with `Child.Settings`"],
				fixedSource: """
				@Instantiable
				public final class Child: Instantiable {
				    public struct Settings {}

				    public init(settings: Child.Settings) {
				        self.settings = settings
				    }

				    @Received let settings: Child.Settings
				}
				""",
			)
		}

		@Test
		func declaration_producesWarningThatQualifiesNestedType_whenInstantiatedPropertyNamesNestedTypeUnqualified() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public struct AnyLogger {
				        public init(_ logger: some Any) {}
				    }

				    public init(logger: AnyLogger) {
				        self.logger = logger
				    }

				    @Instantiated(fulfilledByType: "ConsoleLogger", erasedToConcreteExistential: true) let logger: AnyLogger
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public struct AnyLogger {
				        public init(_ logger: some Any) {}
				    }

				    public init(logger: AnyLogger) {
				        self.logger = logger
				    }

				    let logger: AnyLogger
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The generated code that builds or receives `logger` lives in another type’s extension, where `AnyLogger`, declared in `Child`, does not resolve. Write it as `Child.AnyLogger`.",
						line: 11,
						column: 100,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `AnyLogger` with `Child.AnyLogger`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `AnyLogger` with `Child.AnyLogger`"],
				fixedSource: """
				@Instantiable
				public final class Child: Instantiable {
				    public struct AnyLogger {
				        public init(_ logger: some Any) {}
				    }

				    public init(logger: Child.AnyLogger) {
				        self.logger = logger
				    }

				    @Instantiated(fulfilledByType: "ConsoleLogger", erasedToConcreteExistential: true) let logger: Child.AnyLogger
				}
				""",
			)
		}

		@Test(arguments: UnqualifiedNestedTypePosition.all)
		func declaration_producesWarningThatQualifiesNestedType_whenNestedTypeIsNamedUnqualifiedWithinPropertyType(_ position: UnqualifiedNestedTypePosition) {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public struct Config {
				        public struct Options {}
				    }
				    public struct Box<Value> {}

				    public init(config: \(position.initializerParameterType)) {
				        self.config = config
				    }

				    @Received let config: \(position.propertyType)
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public struct Config {
				        public struct Options {}
				    }
				    public struct Box<Value> {}

				    public init(config: \(position.initializerParameterType)) {
				        self.config = config
				    }

				    let config: \(position.propertyType)
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The generated code that builds or receives `config` lives in another type’s extension, where `\(position.typeName)`, declared in `Child`, does not resolve. Write it as `Child.\(position.typeName)`.",
						line: 12,
						column: 27,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `\(position.typeName)` with `Child.\(position.typeName)`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `\(position.typeName)` with `Child.\(position.typeName)`"],
				fixedSource: """
				@Instantiable
				public final class Child: Instantiable {
				    public struct Config {
				        public struct Options {}
				    }
				    public struct Box<Value> {}

				    public init(config: \(position.qualifiedInitializerParameterType)) {
				        self.config = config
				    }

				    @Received let config: \(position.qualifiedPropertyType)
				}
				""",
			)
		}

		@Test(arguments: UnqualifiedNestedTypeDeclaration.all)
		func declaration_producesWarningThatQualifiesNestedType_whenNestedTypeIsDeclaredWithAnyKindOfTypeDeclaration(_ nestedType: UnqualifiedNestedTypeDeclaration) {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    \(nestedType.declaration)

				    public init(config: \(nestedType.propertyType)) {
				        self.config = config
				    }

				    @Received let config: \(nestedType.propertyType)
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    \(nestedType.declaration)

				    public init(config: \(nestedType.propertyType)) {
				        self.config = config
				    }

				    let config: \(nestedType.propertyType)
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The generated code that builds or receives `config` lives in another type’s extension, where `Config`, declared in `Child`, does not resolve. Write it as `Child.Config`.",
						line: 9,
						column: 27,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Config` with `Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Config` with `Child.Config`"],
				fixedSource: """
				@Instantiable
				public final class Child: Instantiable {
				    \(nestedType.declaration)

				    public init(config: \(nestedType.qualifiedPropertyType)) {
				        self.config = config
				    }

				    @Received let config: \(nestedType.qualifiedPropertyType)
				}
				""",
			)
		}

		@Test
		func declaration_producesWarningForEachNestedType_whenPropertyTypeNamesSeveralNestedTypesUnqualified() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public struct Config {}
				    public struct Box<Value> {}

				    public init(box: Box<Config>) {
				        self.box = box
				    }

				    @Received let box: Box<Config>
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public struct Config {}
				    public struct Box<Value> {}

				    public init(box: Box<Config>) {
				        self.box = box
				    }

				    let box: Box<Config>
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The generated code that builds or receives `box` lives in another type’s extension, where `Box`, declared in `Child`, does not resolve. Write it as `Child.Box`.",
						line: 10,
						column: 24,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Box` with `Child.Box`")],
					),
					DiagnosticSpec(
						message: "The generated code that builds or receives `box` lives in another type’s extension, where `Config`, declared in `Child`, does not resolve. Write it as `Child.Config`.",
						line: 10,
						column: 24,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Config` with `Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Box` with `Child.Box`"],
				fixedSource: """
				@Instantiable
				public final class Child: Instantiable {
				    public struct Config {}
				    public struct Box<Value> {}

				    public init(box: Child.Box<Config>) {
				        self.box = box
				    }

				    @Received let box: Child.Box<Config>
				}
				""",
			)
		}

		@Test
		func declaration_fixItQualifiesHandWrittenMockParameter_whenForwardedPropertyNamesNestedTypeUnqualified() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public final class Child: Instantiable {
				    public struct Config {}

				    public init(config: Config) {
				        self.config = config
				    }

				    @Forwarded let config: Config

				    public static func customMock(config: Config) -> Child {
				        Child(config: config)
				    }
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public struct Config {}

				    public init(config: Config) {
				        self.config = config
				    }

				    let config: Config

				    public static func customMock(config: Config) -> Child {
				        Child(config: config)
				    }

				    public typealias ForwardedProperties = Config
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The generated code that builds or receives `config` lives in another type’s extension, where `Config`, declared in `Child`, does not resolve. Write it as `Child.Config`.",
						line: 9,
						column: 28,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Config` with `Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Config` with `Child.Config`"],
				fixedSource: """
				@Instantiable(generateMock: true, customMockName: "customMock")
				public final class Child: Instantiable {
				    public struct Config {}

				    public init(config: Child.Config) {
				        self.config = config
				    }

				    @Forwarded let config: Child.Config

				    public static func customMock(config: Child.Config) -> Child {
				        Child(config: config)
				    }
				}
				""",
			)
		}

		@Test
		func declaration_producesOneWarning_whenEachClauseOfIfConfigDeclaresNestedType() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    #if DEBUG
				    public struct Config {}
				    #else
				    public struct Config {}
				    #endif

				    public init(config: Config) {
				        self.config = config
				    }

				    @Forwarded let config: Config
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    #if DEBUG
				    public struct Config {}
				    #else
				    public struct Config {}
				    #endif

				    public init(config: Config) {
				        self.config = config
				    }

				    let config: Config

				    public typealias ForwardedProperties = Config
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The generated code that builds or receives `config` lives in another type’s extension, where `Config`, declared in `Child`, does not resolve. Write it as `Child.Config`.",
						line: 13,
						column: 28,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Config` with `Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesWarning_whenDecoratedPropertyIsDeclaredInIfConfigClause() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public struct Config {}

				    public init(config: Config) {
				        self.config = config
				    }

				    #if DEBUG
				    @Forwarded let config: Config
				    #endif
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public struct Config {}

				    public init(config: Config) {
				        self.config = config
				    }

				    #if DEBUG
				    let config: Config
				    #endif

				    public typealias ForwardedProperties = Config
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The generated code that builds or receives `config` lives in another type’s extension, where `Config`, declared in `Child`, does not resolve. Write it as `Child.Config`.",
						line: 10,
						column: 28,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Config` with `Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenInstantiatedPropertyNamesNestedInstantiableTypeUnqualified() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Parent: Instantiable {
				    @Instantiable
				    public final class Service: Instantiable {
				        public init() {}
				    }

				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
				expandedSource: """
				public final class Parent: Instantiable {
				    public final class Service: Instantiable {
				        public init() {}
				    }

				    public init(service: Service) {
				        self.service = service
				    }

				    let service: Service
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesWarningThatQualifiesNestedTypeWithEnclosingTypes_whenDecoratedTypeIsNested() {
			assertMacroExpansion(
				"""
				public enum Feature {
				    @Instantiable
				    public final class Child: Instantiable {
				        public struct Config {}

				        public init(config: Config) {
				            self.config = config
				        }

				        @Forwarded let config: Config
				    }
				}
				""",
				expandedSource: """
				public enum Feature {
				    public final class Child: Instantiable {
				        public struct Config {}

				        public init(config: Config) {
				            self.config = config
				        }

				        let config: Config

				        public typealias ForwardedProperties = Config
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The generated code that builds or receives `config` lives in another type’s extension, where `Config`, declared in `Feature.Child`, does not resolve. Write it as `Feature.Child.Config`.",
						line: 10,
						column: 32,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Config` with `Feature.Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Config` with `Feature.Child.Config`"],
				fixedSource: """
				public enum Feature {
				    @Instantiable
				    public final class Child: Instantiable {
				        public struct Config {}

				        public init(config: Feature.Child.Config) {
				            self.config = config
				        }

				        @Forwarded let config: Feature.Child.Config
				    }
				}
				""",
			)
		}

		@Test
		func declaration_producesWarningThatQualifiesNestedTypeWithEnclosingTypes_whenDecoratedTypeIsNestedInTypeDeclaredInExtension() {
			assertMacroExpansion(
				"""
				extension Feature {
				    public struct Screen {
				        @Instantiable
				        public final class Child: Instantiable {
				            public struct Config {}

				            public init(config: Config) {
				                self.config = config
				            }

				            @Forwarded let config: Config
				        }
				    }
				}
				""",
				expandedSource: """
				extension Feature {
				    public struct Screen {
				        public final class Child: Instantiable {
				            public struct Config {}

				            public init(config: Config) {
				                self.config = config
				            }

				            let config: Config

				            public typealias ForwardedProperties = Config
				        }
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The generated code that builds or receives `config` lives in another type’s extension, where `Config`, declared in `Feature.Screen.Child`, does not resolve. Write it as `Feature.Screen.Child.Config`.",
						line: 11,
						column: 36,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Config` with `Feature.Screen.Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Config` with `Feature.Screen.Child.Config`"],
				fixedSource: """
				extension Feature {
				    public struct Screen {
				        @Instantiable
				        public final class Child: Instantiable {
				            public struct Config {}

				            public init(config: Feature.Screen.Child.Config) {
				                self.config = config
				            }

				            @Forwarded let config: Feature.Screen.Child.Config
				        }
				    }
				}
				""",
			)
		}

		@Test
		func declaration_producesWarningThatQualifiesNestedInstantiableType_whenPropertyTypeNamesItWhereSafeDIDoesNotQualifyIt() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    @Instantiable
				    public final class Service: Instantiable {
				        public init() {}
				    }

				    public init(services: [Service]) {
				        self.services = services
				    }

				    @Forwarded let services: [Service]
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public final class Service: Instantiable {
				        public init() {}
				    }

				    public init(services: [Service]) {
				        self.services = services
				    }

				    let services: [Service]

				    public typealias ForwardedProperties = [Service]
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The generated code that builds or receives `services` lives in another type’s extension, where `Service`, declared in `Child`, does not resolve. Write it as `Child.Service`.",
						line: 12,
						column: 30,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Service` with `Child.Service`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Service` with `Child.Service`"],
				fixedSource: """
				@Instantiable
				public final class Child: Instantiable {
				    @Instantiable
				    public final class Service: Instantiable {
				        public init() {}
				    }

				    public init(services: [Child.Service]) {
				        self.services = services
				    }

				    @Forwarded let services: [Child.Service]
				}
				""",
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenForwardedPropertyQualifiesNestedType() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public struct Config {}

				    public init(config: Child.Config) {
				        self.config = config
				    }

				    @Forwarded let config: Child.Config
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public struct Config {}

				    public init(config: Child.Config) {
				        self.config = config
				    }

				    let config: Child.Config

				    public typealias ForwardedProperties = Child.Config
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenForwardedPropertyNamesTypeOfSameNameDeclaredOutsideMemberBlock() {
			assertMacroExpansion(
				"""
				public struct Config {}

				@Instantiable
				public final class Child: Instantiable {
				    public enum Defaults {
				        public struct Config {}
				    }

				    public init(config: Config) {
				        self.config = config
				    }

				    @Forwarded let config: Config
				}
				""",
				expandedSource: """
				public struct Config {}
				public final class Child: Instantiable {
				    public enum Defaults {
				        public struct Config {}
				    }

				    public init(config: Config) {
				        self.config = config
				    }

				    let config: Config

				    public typealias ForwardedProperties = Config
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenUndecoratedPropertyNamesNestedTypeUnqualified() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public struct Cache {}

				    public init() {
				        cache = Cache()
				    }

				    let cache: Cache
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    public struct Cache {}

				    public init() {
				        cache = Cache()
				    }

				    let cache: Cache
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesWarningThatQualifiesNestedType_whenInstantiateParameterNamesNestedTypeUnqualified() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Child: Instantiable {
				    public struct Config {}

				    public static func instantiate(config: Config) -> Child { fatalError() }
				}
				""",
				expandedSource: """
				extension Child: Instantiable {
				    public struct Config {}

				    public static func instantiate(config: Config) -> Child { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The generated code that builds or receives `config` lives in another type’s extension, where `Config`, declared in `Child`, does not resolve. Write it as `Child.Config`.",
						line: 5,
						column: 44,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Config` with `Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Config` with `Child.Config`"],
				fixedSource: """
				@Instantiable
				extension Child: Instantiable {
				    public struct Config {}

				    public static func instantiate(config: Child.Config) -> Child { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_expandsWithoutIssue_whenDefaultValuedInstantiateParameterNamesNestedTypeUnqualified() {
			// A default-valued parameter is not a dependency, so no generated code outside `Child` spells its type.
			assertMacroExpansion(
				"""
				@Instantiable
				extension Child: Instantiable {
				    public struct Config {}

				    public static func instantiate(config: Config = Config()) -> Child { fatalError() }
				}
				""",
				expandedSource: """
				extension Child: Instantiable {
				    public struct Config {}

				    public static func instantiate(config: Config = Config()) -> Child { fatalError() }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		// MARK: UnqualifiedNestedTypePosition

		/// A dependency's type that names a nested type unqualified, and the type with the name qualified.
		struct UnqualifiedNestedTypePosition: CustomTestStringConvertible, Sendable {
			let propertyType: String
			let initializerParameterType: String
			let typeName: String
			let qualifiedPropertyType: String
			let qualifiedInitializerParameterType: String

			init(
				propertyType: String,
				initializerParameterType: String? = nil,
				typeName: String = "Config",
				qualifiedPropertyType: String,
				qualifiedInitializerParameterType: String? = nil,
			) {
				self.propertyType = propertyType
				self.initializerParameterType = initializerParameterType ?? propertyType
				self.typeName = typeName
				self.qualifiedPropertyType = qualifiedPropertyType
				self.qualifiedInitializerParameterType = qualifiedInitializerParameterType ?? qualifiedPropertyType
			}

			var testDescription: String {
				propertyType
			}

			static let all = [
				UnqualifiedNestedTypePosition(propertyType: "Config?", qualifiedPropertyType: "Child.Config?"),
				UnqualifiedNestedTypePosition(propertyType: "Set<Config>", qualifiedPropertyType: "Set<Child.Config>"),
				UnqualifiedNestedTypePosition(propertyType: "[String: Config]", qualifiedPropertyType: "[String: Child.Config]"),
				UnqualifiedNestedTypePosition(propertyType: "(Config, Int)", qualifiedPropertyType: "(Child.Config, Int)"),
				UnqualifiedNestedTypePosition(
					propertyType: "@Sendable (Config) -> Void",
					initializerParameterType: "@escaping @Sendable (Config) -> Void",
					qualifiedPropertyType: "@Sendable (Child.Config) -> Void",
					qualifiedInitializerParameterType: "@escaping @Sendable (Child.Config) -> Void",
				),
				UnqualifiedNestedTypePosition(propertyType: "Config.Options", qualifiedPropertyType: "Child.Config.Options"),
				UnqualifiedNestedTypePosition(propertyType: "Box<Int>", typeName: "Box", qualifiedPropertyType: "Child.Box<Int>"),
			]
		}

		// MARK: UnqualifiedNestedTypeDeclaration

		/// A declaration of a nested type named `Config`, and a dependency type that names it unqualified and qualified.
		struct UnqualifiedNestedTypeDeclaration: CustomTestStringConvertible, Sendable {
			let declaration: String
			let propertyType: String
			let qualifiedPropertyType: String

			var testDescription: String {
				declaration
			}

			static let all = [
				UnqualifiedNestedTypeDeclaration(declaration: "public struct Config {}", propertyType: "Config", qualifiedPropertyType: "Child.Config"),
				UnqualifiedNestedTypeDeclaration(declaration: "public final class Config {}", propertyType: "Config", qualifiedPropertyType: "Child.Config"),
				UnqualifiedNestedTypeDeclaration(declaration: "public actor Config {}", propertyType: "Config", qualifiedPropertyType: "Child.Config"),
				UnqualifiedNestedTypeDeclaration(declaration: "public enum Config {}", propertyType: "Config", qualifiedPropertyType: "Child.Config"),
				UnqualifiedNestedTypeDeclaration(declaration: "public protocol Config {}", propertyType: "any Config", qualifiedPropertyType: "any Child.Config"),
				UnqualifiedNestedTypeDeclaration(declaration: "public typealias Config = [String: Int]", propertyType: "Config", qualifiedPropertyType: "Child.Config"),
			]
		}
	}
#endif
