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

	/// A dependency's type that names a type declared in the declaration `@Instantiable` decorates through `Self`, which
	/// the code SafeDI generates in another type's extension, where `Self` is that other type, spells as written. A
	/// class cannot spell a stored property's type through `Self`, so the decorated types that do are structs.
	struct InstantiableMacroNestedTypeTests {
		// MARK: Tests

		@Test
		func declaration_producesWarningThatQualifiesNestedType_whenForwardedPropertyNamesNestedTypeThroughSelf() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(config: Self.Config) {
				        self.config = config
				    }

				    @Forwarded let config: Self.Config
				}
				""",
				expandedSource: """
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(config: Self.Config) {
				        self.config = config
				    }

				    let config: Self.Config

				    public typealias ForwardedProperties = Self.Config
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Generated code spells `Self.Config` in another type’s extension, where `Self` is that type. Write it as `Child.Config`.",
						line: 9,
						column: 28,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.Config` with `Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Self.Config` with `Child.Config`"],
				fixedSource: """
				@Instantiable
				public struct Child: Instantiable {
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
		func declaration_producesWarningThatQualifiesNestedType_whenReceivedPropertyNamesNestedTypeThroughSelf() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Child: Instantiable {
				    public struct Settings {}

				    public init(settings: Self.Settings) {
				        self.settings = settings
				    }

				    @Received let settings: Self.Settings
				}
				""",
				expandedSource: """
				public struct Child: Instantiable {
				    public struct Settings {}

				    public init(settings: Self.Settings) {
				        self.settings = settings
				    }

				    let settings: Self.Settings
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Generated code spells `Self.Settings` in another type’s extension, where `Self` is that type. Write it as `Child.Settings`.",
						line: 9,
						column: 29,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.Settings` with `Child.Settings`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Self.Settings` with `Child.Settings`"],
				fixedSource: """
				@Instantiable
				public struct Child: Instantiable {
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
		func declaration_producesWarningThatQualifiesNestedType_whenInstantiatedPropertyNamesNestedTypeThroughSelf() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Child: Instantiable {
				    public struct AnyLogger {
				        public init(_ logger: some Any) {}
				    }

				    public init(logger: Self.AnyLogger) {
				        self.logger = logger
				    }

				    @Instantiated(fulfilledByType: "ConsoleLogger", erasedToConcreteExistential: true) let logger: Self.AnyLogger
				}
				""",
				expandedSource: """
				public struct Child: Instantiable {
				    public struct AnyLogger {
				        public init(_ logger: some Any) {}
				    }

				    public init(logger: Self.AnyLogger) {
				        self.logger = logger
				    }

				    let logger: Self.AnyLogger
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Generated code spells `Self.AnyLogger` in another type’s extension, where `Self` is that type. Write it as `Child.AnyLogger`.",
						line: 11,
						column: 100,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.AnyLogger` with `Child.AnyLogger`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Self.AnyLogger` with `Child.AnyLogger`"],
				fixedSource: """
				@Instantiable
				public struct Child: Instantiable {
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

		@Test(arguments: NestedTypeThroughSelfPosition.all)
		func declaration_producesWarningThatQualifiesNestedType_whenNestedTypeIsNamedThroughSelfWithinPropertyType(_ position: NestedTypeThroughSelfPosition) {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Child: Instantiable {
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
				public struct Child: Instantiable {
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
						message: "Generated code spells `Self.\(position.typeName)` in another type’s extension, where `Self` is that type. Write it as `Child.\(position.typeName)`.",
						line: 12,
						column: 27,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.\(position.typeName)` with `Child.\(position.typeName)`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Self.\(position.typeName)` with `Child.\(position.typeName)`"],
				fixedSource: """
				@Instantiable
				public struct Child: Instantiable {
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

		@Test(arguments: NestedTypeThroughSelfDeclaration.all)
		func declaration_producesWarningThatQualifiesNestedType_whenNestedTypeIsDeclaredWithAnyKindOfTypeDeclaration(_ nestedType: NestedTypeThroughSelfDeclaration) {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Child: Instantiable {
				    \(nestedType.declaration)

				    public init(config: \(nestedType.propertyType)) {
				        self.config = config
				    }

				    @Received let config: \(nestedType.propertyType)
				}
				""",
				expandedSource: """
				public struct Child: Instantiable {
				    \(nestedType.declaration)

				    public init(config: \(nestedType.propertyType)) {
				        self.config = config
				    }

				    let config: \(nestedType.propertyType)
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Generated code spells `Self.Config` in another type’s extension, where `Self` is that type. Write it as `Child.Config`.",
						line: 9,
						column: 27,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.Config` with `Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Self.Config` with `Child.Config`"],
				fixedSource: """
				@Instantiable
				public struct Child: Instantiable {
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
		func declaration_producesOneWarningThatQualifiesEveryNestedType_whenPropertyTypeNamesSeveralNestedTypesThroughSelf() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Child: Instantiable {
				    public struct Zeta {}
				    public struct Alpha {}

				    public init(pair: (Self.Zeta, Self.Alpha)) {
				        self.pair = pair
				    }

				    @Received let pair: (Self.Zeta, Self.Alpha)
				}
				""",
				expandedSource: """
				public struct Child: Instantiable {
				    public struct Zeta {}
				    public struct Alpha {}

				    public init(pair: (Self.Zeta, Self.Alpha)) {
				        self.pair = pair
				    }

				    let pair: (Self.Zeta, Self.Alpha)
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Generated code spells `Self.Alpha` and `Self.Zeta` in another type’s extension, where `Self` is that type. Write them as `Child.Alpha` and `Child.Zeta`.",
						line: 10,
						column: 25,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.Alpha` with `Child.Alpha` and `Self.Zeta` with `Child.Zeta`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Self.Alpha` with `Child.Alpha` and `Self.Zeta` with `Child.Zeta`"],
				fixedSource: """
				@Instantiable
				public struct Child: Instantiable {
				    public struct Zeta {}
				    public struct Alpha {}

				    public init(pair: (Child.Zeta, Child.Alpha)) {
				        self.pair = pair
				    }

				    @Received let pair: (Child.Zeta, Child.Alpha)
				}
				""",
			)
		}

		@Test
		func declaration_producesWarningListingEveryNestedType_whenPropertyTypeNamesThreeNestedTypesThroughSelf() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Child: Instantiable {
				    public struct Alpha {}
				    public struct Box<Value> {}
				    public struct Zeta {}

				    public init(box: Self.Box<(Self.Alpha, Self.Zeta)>) {
				        self.box = box
				    }

				    @Received let box: Self.Box<(Self.Alpha, Self.Zeta)>
				}
				""",
				expandedSource: """
				public struct Child: Instantiable {
				    public struct Alpha {}
				    public struct Box<Value> {}
				    public struct Zeta {}

				    public init(box: Self.Box<(Self.Alpha, Self.Zeta)>) {
				        self.box = box
				    }

				    let box: Self.Box<(Self.Alpha, Self.Zeta)>
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Generated code spells `Self.Alpha`, `Self.Box`, and `Self.Zeta` in another type’s extension, where `Self` is that type. Write them as `Child.Alpha`, `Child.Box`, and `Child.Zeta`.",
						line: 11,
						column: 24,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.Alpha` with `Child.Alpha`, `Self.Box` with `Child.Box`, and `Self.Zeta` with `Child.Zeta`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Self.Alpha` with `Child.Alpha`, `Self.Box` with `Child.Box`, and `Self.Zeta` with `Child.Zeta`"],
				fixedSource: """
				@Instantiable
				public struct Child: Instantiable {
				    public struct Alpha {}
				    public struct Box<Value> {}
				    public struct Zeta {}

				    public init(box: Child.Box<(Child.Alpha, Child.Zeta)>) {
				        self.box = box
				    }

				    @Received let box: Child.Box<(Child.Alpha, Child.Zeta)>
				}
				""",
			)
		}

		@Test
		func declaration_fixItQualifiesAliasOfType_whenAliasPropertyNamesNestedTypeThroughSelf() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(configuration: Self.Config) {
				        self.configuration = configuration
				    }

				    @Received(fulfilledByDependencyNamed: "config", ofType: Self.Config.self) let configuration: Self.Config
				}
				""",
				expandedSource: """
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(configuration: Self.Config) {
				        self.configuration = configuration
				    }

				    let configuration: Self.Config
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Generated code spells `Self.Config` in another type’s extension, where `Self` is that type. Write it as `Child.Config`.",
						line: 9,
						column: 98,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.Config` with `Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Self.Config` with `Child.Config`"],
				fixedSource: """
				@Instantiable
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(configuration: Child.Config) {
				        self.configuration = configuration
				    }

				    @Received(fulfilledByDependencyNamed: "config", ofType: Child.Config.self) let configuration: Child.Config
				}
				""",
			)
		}

		@Test
		func declaration_producesWarningAtAliasOfType_whenOnlyOfTypeNamesNestedTypeThroughSelf() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(configuration: Child.Config) {
				        self.configuration = configuration
				    }

				    @Received(fulfilledByDependencyNamed: "config", ofType: Self.Config.self) let configuration: Child.Config
				}
				""",
				expandedSource: """
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(configuration: Child.Config) {
				        self.configuration = configuration
				    }

				    let configuration: Child.Config
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Generated code spells `Self.Config` in another type’s extension, where `Self` is that type. Write it as `Child.Config`.",
						line: 9,
						column: 61,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.Config` with `Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Self.Config` with `Child.Config`"],
				fixedSource: """
				@Instantiable
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(configuration: Child.Config) {
				        self.configuration = configuration
				    }

				    @Received(fulfilledByDependencyNamed: "config", ofType: Child.Config.self) let configuration: Child.Config
				}
				""",
			)
		}

		@Test
		func declaration_fixItQualifiesOnlyNestedTypeWithinAliasOfType_whenOfTypeTupleNamesNestedTypeThroughSelfAndAnotherType() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(pair: (Child.Config, Int)) {
				        self.pair = pair
				    }

				    @Received(fulfilledByDependencyNamed: "configAndCount", ofType: (Self.Config, Int).self) let pair: (Child.Config, Int)
				}
				""",
				expandedSource: """
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(pair: (Child.Config, Int)) {
				        self.pair = pair
				    }

				    let pair: (Child.Config, Int)
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Generated code spells `Self.Config` in another type’s extension, where `Self` is that type. Write it as `Child.Config`.",
						line: 9,
						column: 69,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.Config` with `Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Self.Config` with `Child.Config`"],
				fixedSource: """
				@Instantiable
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(pair: (Child.Config, Int)) {
				        self.pair = pair
				    }

				    @Received(fulfilledByDependencyNamed: "configAndCount", ofType: (Child.Config, Int).self) let pair: (Child.Config, Int)
				}
				""",
			)
		}

		@Test
		func declaration_fixItQualifiesHandWrittenMockParameter_whenForwardedPropertyNamesNestedTypeThroughSelf() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(config: Self.Config) {
				        self.config = config
				    }

				    @Forwarded let config: Self.Config

				    public static func customMock(config: Self.Config) -> Child {
				        Child(config: config)
				    }
				}
				""",
				expandedSource: """
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(config: Self.Config) {
				        self.config = config
				    }

				    let config: Self.Config

				    public static func customMock(config: Self.Config) -> Child {
				        Child(config: config)
				    }

				    public typealias ForwardedProperties = Self.Config
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Generated code spells `Self.Config` in another type’s extension, where `Self` is that type. Write it as `Child.Config`.",
						line: 9,
						column: 28,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.Config` with `Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Self.Config` with `Child.Config`"],
				fixedSource: """
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct Child: Instantiable {
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
		func declaration_fixItQualifiesInitializerParameter_whenParameterNamesKeywordPropertyWithoutBackticks() {
			// `default` names the property declared as `` `default` ``, so the parameter fulfills it.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(default: Self.Config) {
				        self.default = `default`
				    }

				    @Forwarded let `default`: Self.Config
				}
				""",
				expandedSource: """
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(default: Self.Config) {
				        self.default = `default`
				    }

				    let `default`: Self.Config

				    public typealias ForwardedProperties = Self.Config
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Generated code spells `Self.Config` in another type’s extension, where `Self` is that type. Write it as `Child.Config`.",
						line: 9,
						column: 31,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.Config` with `Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Self.Config` with `Child.Config`"],
				fixedSource: """
				@Instantiable
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(default: Child.Config) {
				        self.default = `default`
				    }

				    @Forwarded let `default`: Child.Config
				}
				""",
			)
		}

		@Test
		func declaration_producesOneWarning_whenEachClauseOfIfConfigDeclaresNestedType() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Child: Instantiable {
				    #if DEBUG
				    public struct Config {}
				    #else
				    public struct Config {}
				    #endif

				    public init(config: Self.Config) {
				        self.config = config
				    }

				    @Forwarded let config: Self.Config
				}
				""",
				expandedSource: """
				public struct Child: Instantiable {
				    #if DEBUG
				    public struct Config {}
				    #else
				    public struct Config {}
				    #endif

				    public init(config: Self.Config) {
				        self.config = config
				    }

				    let config: Self.Config

				    public typealias ForwardedProperties = Self.Config
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Generated code spells `Self.Config` in another type’s extension, where `Self` is that type. Write it as `Child.Config`.",
						line: 13,
						column: 28,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.Config` with `Child.Config`")],
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
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(config: Self.Config) {
				        self.config = config
				    }

				    #if DEBUG
				    @Forwarded let config: Self.Config
				    #endif
				}
				""",
				expandedSource: """
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(config: Self.Config) {
				        self.config = config
				    }

				    #if DEBUG
				    let config: Self.Config
				    #endif

				    public typealias ForwardedProperties = Self.Config
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Generated code spells `Self.Config` in another type’s extension, where `Self` is that type. Write it as `Child.Config`.",
						line: 10,
						column: 28,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.Config` with `Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesWarningThatQualifiesNestedInstantiableType_whenInstantiatedPropertyNamesItThroughSelf() {
			// SafeDI qualifies a nested type's bare name, never a spelling through `Self`, so a nested `@Instantiable`
			// type spelled through `Self` is reported like any other.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Parent: Instantiable {
				    @Instantiable
				    public final class Service: Instantiable {
				        public init() {}
				    }

				    public init(service: Self.Service) {
				        self.service = service
				    }

				    @Instantiated let service: Self.Service
				}
				""",
				expandedSource: """
				public struct Parent: Instantiable {
				    public final class Service: Instantiable {
				        public init() {}
				    }

				    public init(service: Self.Service) {
				        self.service = service
				    }

				    let service: Self.Service
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Generated code spells `Self.Service` in another type’s extension, where `Self` is that type. Write it as `Parent.Service`.",
						line: 12,
						column: 32,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.Service` with `Parent.Service`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Self.Service` with `Parent.Service`"],
				fixedSource: """
				@Instantiable
				public struct Parent: Instantiable {
				    @Instantiable
				    public final class Service: Instantiable {
				        public init() {}
				    }

				    public init(service: Parent.Service) {
				        self.service = service
				    }

				    @Instantiated let service: Parent.Service
				}
				""",
			)
		}

		@Test
		func declaration_producesWarningThatQualifiesNestedTypeWithEnclosingTypes_whenDecoratedTypeIsNested() {
			assertMacroExpansion(
				"""
				public enum Feature {
				    @Instantiable
				    public struct Child: Instantiable {
				        public struct Config {}

				        public init(config: Self.Config) {
				            self.config = config
				        }

				        @Forwarded let config: Self.Config
				    }
				}
				""",
				expandedSource: """
				public enum Feature {
				    public struct Child: Instantiable {
				        public struct Config {}

				        public init(config: Self.Config) {
				            self.config = config
				        }

				        let config: Self.Config

				        public typealias ForwardedProperties = Self.Config
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Generated code spells `Self.Config` in another type’s extension, where `Self` is that type. Write it as `Feature.Child.Config`.",
						line: 10,
						column: 32,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.Config` with `Feature.Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Self.Config` with `Feature.Child.Config`"],
				fixedSource: """
				public enum Feature {
				    @Instantiable
				    public struct Child: Instantiable {
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
				        public struct Child: Instantiable {
				            public struct Config {}

				            public init(config: Self.Config) {
				                self.config = config
				            }

				            @Forwarded let config: Self.Config
				        }
				    }
				}
				""",
				expandedSource: """
				extension Feature {
				    public struct Screen {
				        public struct Child: Instantiable {
				            public struct Config {}

				            public init(config: Self.Config) {
				                self.config = config
				            }

				            let config: Self.Config

				            public typealias ForwardedProperties = Self.Config
				        }
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Generated code spells `Self.Config` in another type’s extension, where `Self` is that type. Write it as `Feature.Screen.Child.Config`.",
						line: 11,
						column: 36,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.Config` with `Feature.Screen.Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Self.Config` with `Feature.Screen.Child.Config`"],
				fixedSource: """
				extension Feature {
				    public struct Screen {
				        @Instantiable
				        public struct Child: Instantiable {
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

		@Test(arguments: NestedTypeWithoutQualificationShape.all)
		func declaration_expandsWithoutIssue_whenDependencyNamesNestedTypeWithoutQualifyingIt(_ shape: NestedTypeWithoutQualificationShape) {
			// SafeDI qualifies a nested type's bare name wherever a declaration spells it, so generated code resolves it.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Child: Instantiable {
				    \(shape.nestedTypeDeclaration)

				    public init(\(shape.label): \(shape.propertyType)) {
				        self.\(shape.label) = \(shape.label)
				    }

				    \(shape.attribute) let \(shape.label): \(shape.propertyType)
				}
				""",
				expandedSource: """
				public final class Child: Instantiable {
				    \(shape.nestedTypeDeclaration)

				    public init(\(shape.label): \(shape.propertyType)) {
				        self.\(shape.label) = \(shape.label)
				    }

				    let \(shape.label): \(shape.propertyType)\(shape.addedMembers)
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenInstantiatedPropertyNamesNestedInstantiableTypeWithoutQualifyingIt() {
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
		func declaration_expandsWithoutIssue_whenForwardedPropertyNamesNestedInstantiableTypeWithinCollectionWithoutQualifyingIt() {
			// SafeDI qualifies `Service` here as it qualifies a plain nested type, not as the type a dependency builds.
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
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenForwardedPropertyQualifiesNestedType() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Child: Instantiable {
				    public struct Config {}

				    public init(config: Child.Config) {
				        self.config = config
				    }

				    @Forwarded let config: Child.Config
				}
				""",
				expandedSource: """
				public struct Child: Instantiable {
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
		func declaration_expandsWithoutIssue_whenUndecoratedPropertyNamesNestedTypeThroughSelf() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Child: Instantiable {
				    public struct Cache {}

				    public init() {
				        cache = Cache()
				    }

				    let cache: Self.Cache
				}
				""",
				expandedSource: """
				public struct Child: Instantiable {
				    public struct Cache {}

				    public init() {
				        cache = Cache()
				    }

				    let cache: Self.Cache
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesWarningThatQualifiesNestedType_whenInstantiateParameterNamesNestedTypeThroughSelf() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Child: Instantiable {
				    public struct Config {}

				    public static func instantiate(config: Self.Config) -> Child { fatalError() }
				}
				""",
				expandedSource: """
				extension Child: Instantiable {
				    public struct Config {}

				    public static func instantiate(config: Self.Config) -> Child { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Generated code spells `Self.Config` in another type’s extension, where `Self` is that type. Write it as `Child.Config`.",
						line: 5,
						column: 44,
						severity: .warning,
						fixIts: [FixItSpec(message: "Replace `Self.Config` with `Child.Config`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Replace `Self.Config` with `Child.Config`"],
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
		func extension_expandsWithoutIssue_whenInstantiateParameterNamesNestedTypeWithoutQualifyingIt() {
			// SafeDI qualifies a nested type's bare name wherever a declaration spells it, so generated code resolves it.
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
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_expandsWithoutIssue_whenDefaultValuedInstantiateParameterNamesNestedTypeThroughSelf() {
			// A default-valued parameter is not a dependency, so no generated code outside `Child` spells its type.
			assertMacroExpansion(
				"""
				@Instantiable
				extension Child: Instantiable {
				    public struct Config {}

				    public static func instantiate(config: Self.Config = .init()) -> Child { fatalError() }
				}
				""",
				expandedSource: """
				extension Child: Instantiable {
				    public struct Config {}

				    public static func instantiate(config: Self.Config = .init()) -> Child { fatalError() }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		// MARK: NestedTypeThroughSelfPosition

		/// A dependency's type that names a nested type through `Self`, and the type with the name qualified.
		struct NestedTypeThroughSelfPosition: CustomTestStringConvertible, Sendable {
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
				NestedTypeThroughSelfPosition(propertyType: "Self.Config?", qualifiedPropertyType: "Child.Config?"),
				NestedTypeThroughSelfPosition(propertyType: "Set<Self.Config>", qualifiedPropertyType: "Set<Child.Config>"),
				NestedTypeThroughSelfPosition(propertyType: "[String: Self.Config]", qualifiedPropertyType: "[String: Child.Config]"),
				NestedTypeThroughSelfPosition(propertyType: "(Self.Config, Int)", qualifiedPropertyType: "(Child.Config, Int)"),
				NestedTypeThroughSelfPosition(
					propertyType: "@Sendable (Self.Config) -> Void",
					initializerParameterType: "@escaping @Sendable (Self.Config) -> Void",
					qualifiedPropertyType: "@Sendable (Child.Config) -> Void",
					qualifiedInitializerParameterType: "@escaping @Sendable (Child.Config) -> Void",
				),
				NestedTypeThroughSelfPosition(propertyType: "Self.Config.Options", qualifiedPropertyType: "Child.Config.Options"),
				NestedTypeThroughSelfPosition(propertyType: "Self.Box<Int>", typeName: "Box", qualifiedPropertyType: "Child.Box<Int>"),
				NestedTypeThroughSelfPosition(propertyType: "Instantiator<Self.Config>", qualifiedPropertyType: "Instantiator<Child.Config>"),
				// SafeDI qualifies the bare name, so the fix-it leaves it as written.
				NestedTypeThroughSelfPosition(propertyType: "[Config: Self.Config]", qualifiedPropertyType: "[Config: Child.Config]"),
			]
		}

		// MARK: NestedTypeThroughSelfDeclaration

		/// A declaration of a nested type named `Config`, and a dependency type that names it through `Self` and
		/// qualified.
		struct NestedTypeThroughSelfDeclaration: CustomTestStringConvertible, Sendable {
			let declaration: String
			let propertyType: String
			let qualifiedPropertyType: String

			var testDescription: String {
				declaration
			}

			static let all = [
				NestedTypeThroughSelfDeclaration(declaration: "public struct Config {}", propertyType: "Self.Config", qualifiedPropertyType: "Child.Config"),
				NestedTypeThroughSelfDeclaration(declaration: "public final class Config {}", propertyType: "Self.Config", qualifiedPropertyType: "Child.Config"),
				NestedTypeThroughSelfDeclaration(declaration: "public actor Config {}", propertyType: "Self.Config", qualifiedPropertyType: "Child.Config"),
				NestedTypeThroughSelfDeclaration(declaration: "public enum Config {}", propertyType: "Self.Config", qualifiedPropertyType: "Child.Config"),
				NestedTypeThroughSelfDeclaration(declaration: "public protocol Config {}", propertyType: "any Self.Config", qualifiedPropertyType: "any Child.Config"),
				NestedTypeThroughSelfDeclaration(declaration: "public typealias Config = [String: Int]", propertyType: "Self.Config", qualifiedPropertyType: "Child.Config"),
			]
		}

		// MARK: NestedTypeWithoutQualificationShape

		/// A dependency whose type names a nested type by its bare name, which SafeDI qualifies.
		struct NestedTypeWithoutQualificationShape: CustomTestStringConvertible, Sendable {
			let nestedTypeDeclaration: String
			let attribute: String
			let label: String
			let propertyType: String
			/// The members the macro adds after the property, each after a blank line.
			let addedMembers: String

			var testDescription: String {
				"\(attribute) let \(label): \(propertyType)"
			}

			static let all = [
				NestedTypeWithoutQualificationShape(
					nestedTypeDeclaration: "public struct Config {}",
					attribute: "@Forwarded",
					label: "config",
					propertyType: "Config",
					addedMembers: "\n\n    public typealias ForwardedProperties = Config",
				),
				NestedTypeWithoutQualificationShape(
					nestedTypeDeclaration: "public struct Config {}",
					attribute: "@Received",
					label: "config",
					propertyType: "Config",
					addedMembers: "",
				),
				NestedTypeWithoutQualificationShape(
					nestedTypeDeclaration: "public struct AnyLogger {}",
					attribute: #"@Instantiated(fulfilledByType: "ConsoleLogger", erasedToConcreteExistential: true)"#,
					label: "logger",
					propertyType: "AnyLogger",
					addedMembers: "",
				),
				NestedTypeWithoutQualificationShape(
					nestedTypeDeclaration: "public struct Config {}",
					attribute: #"@Received(fulfilledByDependencyNamed: "config", ofType: Config.self)"#,
					label: "configuration",
					propertyType: "Config",
					addedMembers: "",
				),
				NestedTypeWithoutQualificationShape(
					nestedTypeDeclaration: "public struct Box<Value> {}",
					attribute: "@Received",
					label: "boxes",
					propertyType: "[String: Box<(Int, Box<Int>)>]",
					addedMembers: "",
				),
				NestedTypeWithoutQualificationShape(
					nestedTypeDeclaration: "public protocol Config {}",
					attribute: "@Received",
					label: "config",
					propertyType: "any Config",
					addedMembers: "",
				),
			]
		}
	}
#endif
