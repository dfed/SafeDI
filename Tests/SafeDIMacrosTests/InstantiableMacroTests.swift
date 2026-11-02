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

	let instantiableTestMacros: [String: Macro.Type] = [
		InstantiableVisitor.macroName: InstantiableMacro.self,
		Dependency.Source.instantiatedRawValue: InjectableMacro.self,
		Dependency.Source.receivedRawValue: InjectableMacro.self,
		Dependency.Source.forwardedRawValue: InjectableMacro.self,
	]

	struct InstantiableMacroTests {
		// MARK: Behavior Tests

		@Test
		func providingMacros_containsInstantiable() {
			#expect(SafeDIMacroPlugin().providingMacros.contains(where: { $0 == InstantiableMacro.self }))
		}

		@Test
		func declaration_expandsWithoutIssueWhenInstantiableConformanceMissingAndConformsElsewhereIsTrue() {
			assertMacroExpansion(
				"""
				@Instantiable(conformsElsewhere: true)
				public final class ExampleService {
				    public init() {}
				}
				""",
				expandedSource: """
				public final class ExampleService {
				    public init() {}
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_expandsWithoutIssueOnExtensionWhenInstantiableConformanceMissingAndConformsElsewhereIsTrue() {
			assertMacroExpansion(
				"""
				@Instantiable(conformsElsewhere: true)
				extension ExampleService: CustomStringConvertible {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				""",
				expandedSource: """
				extension ExampleService: CustomStringConvertible {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		// MARK: Default-valued instantiate parameters

		@Test
		func extension_expandsWithoutIssue_whenInstantiateParameterHasDefaultValue() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(database: Database, title: String = "production") -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(database: Database, title: String = "production") -> Service { fatalError() }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_expandsWithoutIssue_whenMockOmitsDefaultValuedInstantiateParameter() {
			// A default-valued parameter of `instantiate(…)` is not a dependency, so a mock need not take it.
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(database: Database, title: String = "production") -> Service { fatalError() }

				    public static func mock(database: Database) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(database: Database, title: String = "production") -> Service { fatalError() }

				    public static func mock(database: Database) -> Service { fatalError() }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesDiagnostic_whenMockTakesDefaultValuedInstantiateParameterWithoutDefault() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(title: String = "production") -> Service { fatalError() }

				    public static func mock(title: String) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(title: String = "production") -> Service { fatalError() }

				    public static func mock(title: String) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This `mock()` method’s parameter `title: String` does not correspond to a dependency, so it must have a default value.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add default values to `mock()` non-dependency parameters for title: String"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_doesNotThrow_whenRootInstantiateHasOnlyDefaultValuedParameters() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				extension Service: Instantiable {
				    public static func instantiate(title: String = "production") -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(title: String = "production") -> Service { fatalError() }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesDiagnostic_whenInstantiateDefaultValueReferencesSelf() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(title: String = Self.defaultTitle) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(title: String = Self.defaultTitle) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The default value of `title` refers to `Self`. A generated `mock()` repeats this default outside `Service`, where `Self` names a different type. Write `Service` instead of `Self`, or remove the default.",
						line: 3,
						column: 36,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesDiagnostic_whenInstantiateHasUnlabeledDefaultBeforeUnlabeledParameter() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(_ enabled: Bool = false, _ leaf: Leaf) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(_ enabled: Bool = false, _ leaf: Leaf) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Unlabeled parameter `enabled: Bool` has a default value but is followed by unlabeled required parameter `leaf: Leaf`, so a generated `mock()` cannot leave `enabled` out of its call. Add an argument label to `enabled`, move unlabeled parameters with defaults after the required ones, or remove the default.",
						line: 3,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add argument label `enabled`"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_fixit_renamesArgumentLabel_whenDefaultValuedInstantiateParameterLabelBeginsWithReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(__safeDI_delay: Double = 0) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(__safeDI_delay: Double = 0) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_delay` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 3,
						column: 36,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `__safeDI_delay` to `delay`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Rename `__safeDI_delay` to `delay`"],
				fixedSource: """
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(delay __safeDI_delay: Double = 0) -> Service { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_expandsWithoutIssue_whenDefaultValuedInstantiateParameterNameBeginsWithReservedPrefix() {
			// A default-valued parameter is not a dependency, so its parameter name binds nothing SafeDI generates,
			// as for an initializer.
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(delay __safeDI_delay: Double = 0) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(delay __safeDI_delay: Double = 0) -> Service { fatalError() }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		// MARK: Error tests

		@Test
		func declaration_throwsErrorWhenOnProtocol() {
			assertMacroExpansion(
				"""
				@Instantiable
				public protocol ExampleService {}
				""",
				expandedSource: """
				public protocol ExampleService {}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable must decorate a class, struct, or actor declaration, or an extension of a type. To fulfill a protocol, decorate a type that conforms to it and list the protocol in `fulfillingAdditionalTypes`.",
						line: 1,
						column: 1,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_throwsErrorWhenOnEnum() {
			assertMacroExpansion(
				"""
				@Instantiable
				public enum ExampleService: Instantiable {}
				""",
				expandedSource: """
				public enum ExampleService: Instantiable {}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable must decorate a class, struct, or actor declaration, or an extension of a type.",
						line: 1,
						column: 1,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_throwsErrorWhenFulfillingAdditionalTypesIncludesAnOptional() {
			assertMacroExpansion(
				"""
				@Instantiable(fulfillingAdditionalTypes: [AnyObject?.self])
				public final class ExampleService: Instantiable {}
				""",
				expandedSource: """
				public final class ExampleService: Instantiable {}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `fulfillingAdditionalTypes` must not include optional types, but it includes `AnyObject?.self`. List the non-optional type instead.",
						line: 1,
						column: 1,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_throwsErrorWhenFulfillingAdditionalTypesIsAPropertyReference() {
			assertMacroExpansion(
				"""
				let fulfillingAdditionalTypes: [Any.Type] = [AnyObject.self]
				@Instantiable(fulfillingAdditionalTypes: fulfillingAdditionalTypes)
				public final class ExampleService: Instantiable {}
				""",
				expandedSource: """
				let fulfillingAdditionalTypes: [Any.Type] = [AnyObject.self]
				public final class ExampleService: Instantiable {}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `fulfillingAdditionalTypes` must be an array literal of types, such as `[MyProtocol.self]`.",
						line: 2,
						column: 1,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_throwsErrorWhenFulfillingAdditionalTypesIsAClosure() {
			assertMacroExpansion(
				"""
				@Instantiable(fulfillingAdditionalTypes: { [AnyObject.self] }())
				public final class ExampleService: Instantiable {}
				""",
				expandedSource: """
				public final class ExampleService: Instantiable {}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `fulfillingAdditionalTypes` must be an array literal of types, such as `[MyProtocol.self]`.",
						line: 1,
						column: 1,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_doesNotThrowWhenRootHasInstantiatedAndRenamedDependencies() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				public final class Foo: Instantiable {
				    public init(dependency: Dependency, renamedDependency: Dependency, renamed2Dependency: Dependency) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated private let dependency: Dependency
				    @Received(fulfilledByDependencyNamed: "dependency", ofType: Dependency.self) private let renamedDependency: Dependency
				    @Received(fulfilledByDependencyNamed: "renamedDependency", ofType: Dependency.self) private let renamed2Dependency: Dependency
				}
				""",
				expandedSource: """
				public final class Foo: Instantiable {
				    public init(dependency: Dependency, renamedDependency: Dependency, renamed2Dependency: Dependency) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    private let dependency: Dependency
				    private let renamedDependency: Dependency
				    private let renamed2Dependency: Dependency
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_doesNotThrow_whenRootRenamesInstanceOfItsOwnLazilyInstantiatedProperty() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(service: LazilyInstantiated<Service>, other: Service) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let service: LazilyInstantiated<Service>
				    @Received(fulfilledByDependencyNamed: "service", ofType: Service.self) let other: Service
				}
				""",
				expandedSource: """
				public final class Root: Instantiable {
				    public init(service: LazilyInstantiated<Service>, other: Service) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    let service: LazilyInstantiated<Service>
				    let other: Service
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_doesNotThrow_whenRootRenamesInstanceOfItsOwnLazilyInstantiatedPropertyOnlyIfAvailable() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(service: LazilyInstantiated<Service>, other: Service?) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let service: LazilyInstantiated<Service>
				    @Received(fulfilledByDependencyNamed: "service", ofType: Service.self, onlyIfAvailable: true) let other: Service?
				}
				""",
				expandedSource: """
				public final class Root: Instantiable {
				    public init(service: LazilyInstantiated<Service>, other: Service?) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    let service: LazilyInstantiated<Service>
				    let other: Service?
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_doesNotThrow_whenRootRenamesInstanceOfItsOwnSendableLazilyInstantiatedProperty() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(service: SendableLazilyInstantiated<Service>, other: Service) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let service: SendableLazilyInstantiated<Service>
				    @Received(fulfilledByDependencyNamed: "service", ofType: Service.self) let other: Service
				}
				""",
				expandedSource: """
				public final class Root: Instantiable {
				    public init(service: SendableLazilyInstantiated<Service>, other: Service) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    let service: SendableLazilyInstantiated<Service>
				    let other: Service
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_doesNotThrow_whenRootRenamesInstanceOfRenamingOfItsOwnLazilyInstantiatedProperty() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(service: LazilyInstantiated<Service>, renamedService: LazilyInstantiated<Service>, other: Service) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let service: LazilyInstantiated<Service>
				    @Received(fulfilledByDependencyNamed: "service", ofType: LazilyInstantiated<Service>.self) let renamedService: LazilyInstantiated<Service>
				    @Received(fulfilledByDependencyNamed: "renamedService", ofType: Service.self) let other: Service
				}
				""",
				expandedSource: """
				public final class Root: Instantiable {
				    public init(service: LazilyInstantiated<Service>, renamedService: LazilyInstantiated<Service>, other: Service) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    let service: LazilyInstantiated<Service>
				    let renamedService: LazilyInstantiated<Service>
				    let other: Service
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_throwsErrors_whenInstantiatedLazilyInstantiatedCreatesOptionalTypeAndRootRenamesItsInstance() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(service: LazilyInstantiated<Service?>, other: Service?) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let service: LazilyInstantiated<Service?>
				    @Received(fulfilledByDependencyNamed: "service", ofType: Service?.self) let other: Service?
				}
				""",
				expandedSource: """
				public final class Root: Instantiable {
				    public init(service: LazilyInstantiated<Service?>, other: Service?) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    let service: LazilyInstantiated<Service?>
				    let other: Service?
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "SafeDI always creates an @Instantiated property, so its type must not be optional. Declare `service: LazilyInstantiated<Service>`, or receive it with `@Received(onlyIfAvailable: true)` where it may be absent.",
						line: 7,
						column: 32,
						severity: .error,
						fixIts: [FixItSpec(message: "Declare `service: LazilyInstantiated<Service>`")],
					),
					DiagnosticSpec(
						message: """
						`Root` is declared with `isRoot: true`, so no other type passes it dependencies, but it needs `other: Service?` from outside it. Declare each as @Instantiated, or as `@Received(fulfilledByDependencyNamed:ofType:)` naming an @Instantiated property of `Root`, or remove `isRoot: true` and instantiate `Root` from another type.
						""",
						line: 1,
						column: 1,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Declare `service: LazilyInstantiated<Service>`"],
				fixedSource: """
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(service: LazilyInstantiated<Service?>, other: Service?) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let service: LazilyInstantiated<Service>
				    @Received(fulfilledByDependencyNamed: "service", ofType: Service?.self) let other: Service?
				}
				""",
			)
		}

		@Test
		func declaration_throwsErrorWhenRootHasReceivedDependency() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				public final class Foo: Instantiable {
				    public init(dependency: Dependency) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received private let dependency: Dependency 
				}
				""",
				expandedSource: """
				public final class Foo: Instantiable {
				    public init(dependency: Dependency) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    private let dependency: Dependency 
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: """
						`Foo` is declared with `isRoot: true`, so no other type passes it dependencies, but it needs `dependency: Dependency` from outside it. Declare each as @Instantiated, or as `@Received(fulfilledByDependencyNamed:ofType:)` naming an @Instantiated property of `Foo`, or remove `isRoot: true` and instantiate `Foo` from another type.
						""",
						line: 1,
						column: 1,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_throwsErrorWhenRootHasForwardedDependency() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				public final class Foo: Instantiable {
				    public init(dependency: Dependency) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Forwarded private let dependency: Dependency 
				}
				""",
				expandedSource: """
				public final class Foo: Instantiable {
				    public init(dependency: Dependency) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    private let dependency: Dependency 
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: """
						`Foo` is declared with `isRoot: true`, so no other type passes it dependencies, but it needs `dependency: Dependency` from outside it. Declare each as @Instantiated, or as `@Received(fulfilledByDependencyNamed:ofType:)` naming an @Instantiated property of `Foo`, or remove `isRoot: true` and instantiate `Foo` from another type.
						""",
						line: 1,
						column: 1,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_throwsErrorWhenFulfillingAdditionalTypesIsAPropertyReference() {
			assertMacroExpansion(
				"""
				let fulfillingAdditionalTypes: [Any.Type] = [AnyObject.self]
				@Instantiable(fulfillingAdditionalTypes: fulfillingAdditionalTypes)
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				let fulfillingAdditionalTypes: [Any.Type] = [AnyObject.self]
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `fulfillingAdditionalTypes` must be an array literal of types, such as `[MyProtocol.self]`.",
						line: 2,
						column: 1,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_throwsErrorWhenFulfillingAdditionalTypesIsAClosure() {
			assertMacroExpansion(
				"""
				@Instantiable(fulfillingAdditionalTypes: { [AnyObject.self] }())
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `fulfillingAdditionalTypes` must be an array literal of types, such as `[MyProtocol.self]`.",
						line: 1,
						column: 1,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_throwsErrorWhenMoreThanOneInstantiateMethodForSameType() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				    public static func instantiate(user: User) -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				    public static func instantiate(user: User) -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension must have a single `instantiate(…)` method that returns `ExampleService`, but it has 2. Remove all but one.",
						line: 1,
						column: 1,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_doesNotThrowWhenRootHasNoDependencies() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				extension Foo: Instantiable {
				    public static func instantiate() -> Foo { fatalError() }
				}
				""",
				expandedSource: """
				extension Foo: Instantiable {
				    public static func instantiate() -> Foo { fatalError() }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_throwsErrorWhenRootHasDependencies() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				extension Foo: Instantiable {
				    public static func instantiate(bar: Bar) -> Foo { fatalError() }
				}
				""",
				expandedSource: """
				extension Foo: Instantiable {
				    public static func instantiate(bar: Bar) -> Foo { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: """
						`Foo` is declared with `isRoot: true`, so no other type passes it dependencies, but its `instantiate(…)` method takes `bar: Bar`. Remove the parameters, or remove `isRoot: true` and instantiate `Foo` from another type.
						""",
						line: 1,
						column: 1,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_rootWithNestedInstantiableHavingDependenciesDoesNotThrow() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true)
				extension Foo: Instantiable {
				    public static func instantiate() -> Foo { fatalError() }

				    @Instantiable
				    public struct Helper: Instantiable {
				        public init(bar: Bar) {
				            self.bar = bar
				        }
				        @Received let bar: Bar
				    }
				}
				""",
				expandedSource: """
				extension Foo: Instantiable {
				    public static func instantiate() -> Foo { fatalError() }
				    public struct Helper: Instantiable {
				        public init(bar: Bar) {
				            self.bar = bar
				        }
				        let bar: Bar
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		// MARK: FixIt tests

		@Test
		func declaration_fixit_generatesRequiredInitializerWithoutAnyDependenciesOnStruct() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init() {}

				}
				""",
			)
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithoutAnyDependenciesOnClass() {
			assertMacroExpansion(
				"""
				@Instantiable
				public class ExampleService: Instantiable {
				}
				""",
				expandedSource: """
				public class ExampleService: Instantiable {
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 43,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public class ExampleService: Instantiable {
				public init() {}

				}
				""",
			)
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithoutAnyDependenciesOnActor() {
			assertMacroExpansion(
				"""
				@Instantiable
				public actor ExampleService: Instantiable {
				}
				""",
				expandedSource: """
				public actor ExampleService: Instantiable {
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 43,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public actor ExampleService: Instantiable {
				public init() {}

				}
				""",
			)
		}

		@Test
		func declaration_doesNotGenerateFixitWithoutDependenciesIfItAlreadyExists() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init() {}
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init() {}
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithoutAnyDependenciesAndInitializedVariable() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    var initializedVariable = "test"
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    var initializedVariable = "test"
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init() {}

				    var initializedVariable = "test"
				}
				""",
			)
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithoutAnyDependenciesAndVariableWithAccessor() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    var initializedVariable { "test" }
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    var initializedVariable { "test" }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init() {}

				    var initializedVariable { "test" }
				}
				""",
			)
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerEvenWhenPropertyDecoratedWithUnknownMacro() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated @Unknown let instantiatedA: InstantiatedA
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    @Unknown let instantiatedA: InstantiatedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    @Instantiated @Unknown let instantiatedA: InstantiatedA
				}
				""",
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenDependencyIsDeclaredInIfConfig() {
			// The compiler has already chosen the active clause, so the macro reads every clause as written.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(dependency: Dependency) {
				        self.dependency = dependency
				    }

				    #if DEBUG
				    @Received let dependency: Dependency
				    #endif
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(dependency: Dependency) {
				        self.dependency = dependency
				    }

				    #if DEBUG
				    let dependency: Dependency
				    #endif
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerEvenWhenPropertyDecoratedWithUnknownMacroInIfConfig() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated
				    #if DEBUG
				    @Unknown
				    #endif
				    let instantiatedA: InstantiatedA
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    #if DEBUG
				    @Unknown
				    #endif
				    let instantiatedA: InstantiatedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    @Instantiated
				    #if DEBUG
				    @Unknown
				    #endif
				    let instantiatedA: InstantiatedA
				}
				""",
			)
		}

		@Test
		func declaration_doesNotGenerateRequiredInitializerWithDependenciesIfItAlreadyExists() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let instantiatedA: InstantiatedA

				    public init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    let instantiatedA: InstantiatedA

				    public init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_doesNotGenerateRequiredInitializerIfItAlreadyExistsWithClosureDependency() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(block closure: @escaping () -> Void) {
				        self.closure = closure
				    }
				    @Forwarded let closure: () -> Void
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(block closure: @escaping () -> Void) {
				        self.closure = closure
				    }
				    let closure: () -> Void

				    public typealias ForwardedProperties = () -> Void
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_doesNotGenerateRequiredInitializerIfItAlreadyExistsWithSendableClosureDependency() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(closure: @escaping @Sendable () -> Void) {
				        self.closure = closure
				    }
				    @Forwarded let closure: @Sendable () -> Void
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(closure: @escaping @Sendable () -> Void) {
				        self.closure = closure
				    }
				    let closure: @Sendable () -> Void

				    public typealias ForwardedProperties = @Sendable () -> Void
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_doesNotGenerateRequiredInitializerIfItAlreadyExistsWithTupleWrappedClosureDependency() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(closure: @escaping @Sendable () -> Void) {
				        self.closure = closure
				    }
				    @Forwarded let closure: (@Sendable () -> Void)
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(closure: @escaping @Sendable () -> Void) {
				        self.closure = closure
				    }
				    let closure: (@Sendable () -> Void)

				    public typealias ForwardedProperties = @Sendable () -> Void
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_doesNotGenerateRequiredInitializerIfItAlreadyExistsWithMultipleForwardedDependencies() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(userID: String, userName: String) {
				        self.userID = userID
				        self.userName = userName
				    }
				    @Forwarded let userID: String
				    @Forwarded let userName: String
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(userID: String, userName: String) {
				        self.userID = userID
				        self.userName = userName
				    }
				    let userID: String
				    let userName: String

				    public typealias ForwardedProperties = (userID: String, userName: String)
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_doesNotGenerateRequiredInitializerIfItAlreadyExistsWithDefaultArguments() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    let nonInjectedProperty: Int

				    public init(nonInjectedProperty: Int = 5) {
				        self.nonInjectedProperty = nonInjectedProperty
				    }
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    let nonInjectedProperty: Int

				    public init(nonInjectedProperty: Int = 5) {
				        self.nonInjectedProperty = nonInjectedProperty
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_doesNotGenerateRequiredInitializerWithDependenciesSatisfyingInitializerIfItAlreadyExistsWithDefaultArguments() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let instantiatedA: InstantiatedA

				    let nonInjectedProperty: Int

				    public init(instantiatedA: InstantiatedA, nonInjectedProperty: Int = 5) {
				        self.instantiatedA = instantiatedA
				        self.nonInjectedProperty = nonInjectedProperty
				    }
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    let instantiatedA: InstantiatedA

				    let nonInjectedProperty: Int

				    public init(instantiatedA: InstantiatedA, nonInjectedProperty: Int = 5) {
				        self.instantiatedA = instantiatedA
				        self.nonInjectedProperty = nonInjectedProperty
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithDependencies() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let instantiatedA: InstantiatedA
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    let instantiatedA: InstantiatedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    @Instantiated let instantiatedA: InstantiatedA
				}
				""",
			)
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithDependenciesWhenNestedTypesHaveUninitializedProperties() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class ExampleService: Instantiable {
				    @Instantiated let instantiatedA: InstantiatedA

				    public enum NestedEnum {
				        // This won't compile but we should still generate an initializer.
				        let uninitializedProperty: Any
				    }
				    public struct NestedStruct {
				        let uninitializedProperty: Any
				    }
				    public actor NestedActor {
				        let uninitializedProperty: Any
				    }
				    public final class NestedClass {
				        let uninitializedProperty: Any
				    }
				}
				""",
				expandedSource: """
				public final class ExampleService: Instantiable {
				    let instantiatedA: InstantiatedA

				    public enum NestedEnum {
				        // This won't compile but we should still generate an initializer.
				        let uninitializedProperty: Any
				    }
				    public struct NestedStruct {
				        let uninitializedProperty: Any
				    }
				    public actor NestedActor {
				        let uninitializedProperty: Any
				    }
				    public final class NestedClass {
				        let uninitializedProperty: Any
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 49,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public final class ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    @Instantiated let instantiatedA: InstantiatedA

				    public enum NestedEnum {
				        // This won't compile but we should still generate an initializer.
				        let uninitializedProperty: Any
				    }
				    public struct NestedStruct {
				        let uninitializedProperty: Any
				    }
				    public actor NestedActor {
				        let uninitializedProperty: Any
				    }
				    public final class NestedClass {
				        let uninitializedProperty: Any
				    }
				}
				""",
			)
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithDependenciesWhenPropertyHasInitializerAndNoType() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let instantiatedA: InstantiatedA

				    let initializedProperty = 5
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    let instantiatedA: InstantiatedA

				    let initializedProperty = 5
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    @Instantiated let instantiatedA: InstantiatedA

				    let initializedProperty = 5
				}
				""",
			)
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithDependenciesWhenPropertyHasInitializerAndType() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let instantiatedA: InstantiatedA

				    let initializedProperty: Int = 5
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    let instantiatedA: InstantiatedA

				    let initializedProperty: Int = 5
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    @Instantiated let instantiatedA: InstantiatedA

				    let initializedProperty: Int = 5
				}
				""",
			)
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithDependenciesWhenPropertyIsOptional() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let instantiatedA: InstantiatedA

				    var optionalProperty: Int?
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    let instantiatedA: InstantiatedA

				    var optionalProperty: Int?
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    @Instantiated let instantiatedA: InstantiatedA

				    var optionalProperty: Int?
				}
				""",
			)
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithDependenciesWhenPropertyIsStatic() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let instantiatedA: InstantiatedA

				    // This won't compile but we should still generate an initializer.
				    public static let staticProperty: Int
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    let instantiatedA: InstantiatedA

				    // This won't compile but we should still generate an initializer.
				    public static let staticProperty: Int
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    @Instantiated let instantiatedA: InstantiatedA

				    // This won't compile but we should still generate an initializer.
				    public static let staticProperty: Int
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenOnlyDependencyMissingFromInitializer() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init() {
						_ = "keep me"
					}

					@Received let receivedA: ReceivedA
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
					public init() {
						_ = "keep me"
					}

					let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `receivedA: ReceivedA`.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedA: ReceivedA"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for receivedA: ReceivedA",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(receivedA: ReceivedA) {
						self.receivedA = receivedA
						_ = "keep me"
					}

					@Received let receivedA: ReceivedA
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenSecondDependencyMissingFromInitializer() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(receivedA: ReceivedA) {
						self.receivedA = receivedA
						_ = "keep me"
					}

					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
					public init(receivedA: ReceivedA) {
						self.receivedA = receivedA
						_ = "keep me"
					}

					let receivedA: ReceivedA
					let receivedB: ReceivedB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `receivedB: ReceivedB`.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedB: ReceivedB"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for receivedB: ReceivedB",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(
				receivedA: ReceivedA,
				receivedB: ReceivedB
				) {
						self.receivedA = receivedA
						self.receivedB = receivedB
						_ = "keep me"
					}

					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenSecondDependencyMissingFromInitializerAndNewlinesInArgumentList() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(
						receivedA: ReceivedA
					) {
						self.receivedA = receivedA
						_ = "keep me"
					}

					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
					public init(
						receivedA: ReceivedA
					) {
						self.receivedA = receivedA
						_ = "keep me"
					}

					let receivedA: ReceivedA
					let receivedB: ReceivedB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `receivedB: ReceivedB`.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedB: ReceivedB"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for receivedB: ReceivedB",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(
				receivedA: ReceivedA,
				receivedB: ReceivedB
					) {
						self.receivedA = receivedA
						self.receivedB = receivedB
						_ = "keep me"
					}

					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenFirstDependencyMissingFromInitializer() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(receivedA: ReceivedA, receivedB: ReceivedB) {
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
					public init(receivedA: ReceivedA, receivedB: ReceivedB) {
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `forwardedA: ForwardedA`.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for forwardedA: ForwardedA"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for forwardedA: ForwardedA",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenMiddleDependencyMissingFromInitializer() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(forwardedA: ForwardedA, receivedB: ReceivedB) {
						self.forwardedA = forwardedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
					public init(forwardedA: ForwardedA, receivedB: ReceivedB) {
						self.forwardedA = forwardedA
						self.receivedB = receivedB
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `receivedA: ReceivedA`.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedA: ReceivedA"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for receivedA: ReceivedA",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenMiddleDependencyMissingFromInitializerAndArgumentAlreadySet() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(forwardedA: ForwardedA, receivedB: ReceivedB) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
					public init(forwardedA: ForwardedA, receivedB: ReceivedB) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `receivedA: ReceivedA`.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedA: ReceivedA"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for receivedA: ReceivedA",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenLastDependencyMissingFromInitializer() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(
						forwardedA: ForwardedA,
						receivedA: ReceivedA
					) {
				        self.forwardedA = forwardedA
				        self.receivedA = receivedA
				    }

				    @Forwarded let forwardedA: ForwardedA
				    @Received let receivedA: ReceivedA
				    @Received let receivedB: ReceivedB
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(
						forwardedA: ForwardedA,
						receivedA: ReceivedA
					) {
				        self.forwardedA = forwardedA
				        self.receivedA = receivedA
				    }

				    let forwardedA: ForwardedA
				    let receivedA: ReceivedA
				    let receivedB: ReceivedB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `receivedB: ReceivedB`.",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedB: ReceivedB"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for receivedB: ReceivedB",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(
						forwardedA: ForwardedA,
						receivedA: ReceivedA,
						receivedB: ReceivedB
					) {
				        self.forwardedA = forwardedA
				        self.receivedA = receivedA
				        self.receivedB = receivedB
				    }

				    @Forwarded let forwardedA: ForwardedA
				    @Received let receivedA: ReceivedA
				    @Received let receivedB: ReceivedB
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerKeepingAssignments_whenAssignmentsEscapeLabelsDifferently() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(
						default: ReceivedA,
						leaf: Leaf
					) {
				        self.default = `default`
				        self.`leaf` = leaf
				    }

				    @Received let `default`: ReceivedA
				    @Received let leaf: Leaf
				    @Received let receivedB: ReceivedB
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(
						default: ReceivedA,
						leaf: Leaf
					) {
				        self.default = `default`
				        self.`leaf` = leaf
				    }

				    let `default`: ReceivedA
				    let leaf: Leaf
				    let receivedB: ReceivedB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `receivedB: ReceivedB`.",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedB: ReceivedB"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for receivedB: ReceivedB",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(
						default: ReceivedA,
						leaf: Leaf,
						receivedB: ReceivedB
					) {
				        self.default = `default`
				        self.`leaf` = leaf
				        self.receivedB = receivedB
				    }

				    @Received let `default`: ReceivedA
				    @Received let leaf: Leaf
				    @Received let receivedB: ReceivedB
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenFirstDependencyMissingFromInitializerAndNonDependencyParameterExists() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
					public init(receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `forwardedA: ForwardedA`.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for forwardedA: ForwardedA"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for forwardedA: ForwardedA",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenMiddleDependencyMissingFromInitializerAndNonDependencyParameterExists() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(
						customizable: String = "",
						forwardedA: ForwardedA,
						receivedB: ReceivedB
					) {
						self.forwardedA = forwardedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
					public init(
						customizable: String = "",
						forwardedA: ForwardedA,
						receivedB: ReceivedB
					) {
						self.forwardedA = forwardedA
						self.receivedB = receivedB
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `receivedA: ReceivedA`.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedA: ReceivedA"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for receivedA: ReceivedA",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(
						customizable: String = "",
						forwardedA: ForwardedA,
						receivedA: ReceivedA,
						receivedB: ReceivedB
					) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenLastDependencyMissingFromInitializerAndNonDependencyParameterExists() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(forwardedA: ForwardedA, receivedA: ReceivedA, customizable: String = "") {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
					public init(forwardedA: ForwardedA, receivedA: ReceivedA, customizable: String = "") {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `receivedB: ReceivedB`.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedB: ReceivedB"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for receivedB: ReceivedB",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerKeepingNonDependencyParametersInSourceOrder_whenSeveralNonDependencyParametersExist() {
			// The non-dependency parameters were inserted in dictionary order, which changes from run
			// to run, and an insertion past the end of the parameter list crashed the macro. Six
			// parameters make inserting them in source order by chance unlikely.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(forwardedA: ForwardedA, receivedA: ReceivedA, alpha: Int = 1, bravo: Int = 2, charlie: Int = 3, delta: Int = 4, echo: Int = 5, foxtrot: Int = 6) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
					public init(forwardedA: ForwardedA, receivedA: ReceivedA, alpha: Int = 1, bravo: Int = 2, charlie: Int = 3, delta: Int = 4, echo: Int = 5, foxtrot: Int = 6) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `receivedB: ReceivedB`.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedB: ReceivedB"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for receivedB: ReceivedB",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB, alpha: Int = 1, bravo: Int = 2, charlie: Int = 3, delta: Int = 4, echo: Int = 5, foxtrot: Int = 6) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenLastDependencyMissingFromInitializerAndEscapingDependencyParameterExists() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(customizable: @escaping (String) -> Void, forwardedA: ForwardedA, receivedA: ReceivedA) {
						self.customizable = customizable
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					@Forwarded let customizable: (String) -> Void
					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
					public init(customizable: @escaping (String) -> Void, forwardedA: ForwardedA, receivedA: ReceivedA) {
						self.customizable = customizable
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					let customizable: (String) -> Void
					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `receivedB: ReceivedB`.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedB: ReceivedB"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for receivedB: ReceivedB",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(customizable: @escaping (String) -> Void, forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB) {
						self.customizable = customizable
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let customizable: (String) -> Void
					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenAllDependenciesMissingFromInitializer() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init() {
					}

					@Received let received: Received
					@Instantiated let instantiated: Instantiated
					@Forwarded let forwarded: Forwarded
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
					public init() {
					}

					let received: Received
					let instantiated: Instantiated
					let forwarded: Forwarded
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `received: Received`, `instantiated: Instantiated`, `forwarded: Forwarded`.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for received: Received, instantiated: Instantiated, forwarded: Forwarded"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for received: Received, instantiated: Instantiated, forwarded: Forwarded",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(
				received: Received,
				instantiated: Instantiated,
				forwarded: Forwarded
				) {
				self.received = received
				self.instantiated = instantiated
				self.forwarded = forwarded
					}

					@Received let received: Received
					@Instantiated let instantiated: Instantiated
					@Forwarded let forwarded: Forwarded
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenIncorrectAccessibilityOnInitializerAndOtherNonConformingInitializersExist() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					fileprivate init(forwardedA: ForwardedA, receivedA: ReceivedA, customizable: String) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					init(forwardedA: ForwardedA, receivedA: ReceivedA) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					public init(receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					public init(receivedA: ReceivedA, customizable: String = "") {
						self.receivedA = receivedA
					}

					private init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
					fileprivate init(forwardedA: ForwardedA, receivedA: ReceivedA, customizable: String) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					init(forwardedA: ForwardedA, receivedA: ReceivedA) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					public init(receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					public init(receivedA: ReceivedA, customizable: String = "") {
						self.receivedA = receivedA
					}

					private init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer.",
						line: 22,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public` modifier",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
					fileprivate init(forwardedA: ForwardedA, receivedA: ReceivedA, customizable: String) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					init(forwardedA: ForwardedA, receivedA: ReceivedA) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					public init(receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					public init(receivedA: ReceivedA, customizable: String = "") {
						self.receivedA = receivedA
					}

					public init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenDependencyMissingFromInitializerAndOtherNonConformingInitializersExist() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					private init(receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					fileprivate init(forwardedA: ForwardedA, receivedA: ReceivedA, customizable: String) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					init(forwardedA: ForwardedA, receivedA: ReceivedA) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					public init(receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
					private init(receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					fileprivate init(forwardedA: ForwardedA, receivedA: ReceivedA, customizable: String) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					init(forwardedA: ForwardedA, receivedA: ReceivedA) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					public init(receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `forwardedA: ForwardedA`.",
						line: 18,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for forwardedA: ForwardedA"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for forwardedA: ForwardedA",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
					private init(receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					fileprivate init(forwardedA: ForwardedA, receivedA: ReceivedA, customizable: String) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					init(forwardedA: ForwardedA, receivedA: ReceivedA) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					public init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenDependencyMissingFromInitializerAndAccessibilityModifierMissing() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					init(receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
					init(receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `forwardedA: ForwardedA`.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for forwardedA: ForwardedA"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for forwardedA: ForwardedA",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
					init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				""",
			)
		}

		@Test
		func declaration_fixit_generatesInitializerWithForwardedPropertiesWhenThereAreMultipleForwardedProperties() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class UserService: Instantiable {
				    @Forwarded let userID: String

				    @Forwarded let userName: String
				}
				""",
				expandedSource: """
				public final class UserService: Instantiable {
				    let userID: String

				    let userName: String
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 46,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public final class UserService: Instantiable {
				public init(
				userID: String,
				userName: String
				) {
				self.userID = userID
				self.userName = userName
				}

				    @Forwarded let userID: String

				    @Forwarded let userName: String
				}
				""",
			)
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithClosureDependency() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Forwarded let closure: () -> Void
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    let closure: () -> Void
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(closure: @escaping () -> Void) {
				self.closure = closure
				}

				    @Forwarded let closure: () -> Void
				}
				""",
			)
		}

		@Test
		func declaration_fixit_generatesFixitForRequiredInitializerWithSendableClosureDependency() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Forwarded let closure: @Sendable () -> Void
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    let closure: @Sendable () -> Void
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(closure: @escaping @Sendable () -> Void) {
				self.closure = closure
				}

				    @Forwarded let closure: @Sendable () -> Void
				}
				""",
			)
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWhenInstantiatorDependencyMissingFromInitializer() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated private let instantiatableAInstantiator: Instantiator<ReceivedA>
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    private let instantiatableAInstantiator: Instantiator<ReceivedA>
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(instantiatableAInstantiator: Instantiator<ReceivedA>) {
				self.instantiatableAInstantiator = instantiatableAInstantiator
				}

				    @Instantiated private let instantiatableAInstantiator: Instantiator<ReceivedA>
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesInitializerWhenExistingInitializerIsMissingAccessModifier() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class UserService: Instantiable {
					init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				""",
				expandedSource: """
				public final class UserService: Instantiable {
					init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					let a: A
					let b: B
					let c: C
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public` modifier",
				],
				fixedSource: """
				@Instantiable
				public final class UserService: Instantiable {
					public init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesInitializerWhenExistingInitializerIsMissingAccessModifierWithOtherModifier() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class UserService: Instantiable {
					final init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				""",
				expandedSource: """
				public final class UserService: Instantiable {
					final init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					let a: A
					let b: B
					let c: C
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public` modifier",
				],
				fixedSource: """
				@Instantiable
				public final class UserService: Instantiable {
					public final init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesFirstInitializer_whenIfConfigClausesDeclareSameSignatureWithDifferentNonPublicAccess() {
			// The initializers differ only in access, so each is reported where it is declared. The macro reports the
			// first initializer it can fix.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    #if DEBUG
				    init() {}
				    #else
				    private init() {}
				    #endif
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    #if DEBUG
				    init() {}
				    #else
				    private init() {}
				    #endif
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer.",
						line: 4,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public` modifier",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				    #if DEBUG
				    public init() {}
				    #else
				    private init() {}
				    #endif
				}
				""",
			)
		}

		@Test
		func declaration_diagnosesUnlabeledDefaultAtEachInitializer_whenIfConfigClausesDeclareSameSignatureWithDifferentNonPublicAccess() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    #if DEBUG
				    init(_ enabled: Bool = false, _ dependency: Dependency) {
				        self.dependency = dependency
				    }
				    #else
				    private init(_ enabled: Bool = false, _ dependency: Dependency) {
				        self.dependency = dependency
				    }
				    #endif

				    @Received let dependency: Dependency
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    #if DEBUG
				    init(_ enabled: Bool = false, _ dependency: Dependency) {
				        self.dependency = dependency
				    }
				    #else
				    private init(_ enabled: Bool = false, _ dependency: Dependency) {
				        self.dependency = dependency
				    }
				    #endif

				    let dependency: Dependency
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Unlabeled parameter `enabled: Bool` has a default value but is followed by unlabeled required parameter `dependency: Dependency`, so a generated `mock()` cannot leave `enabled` out of its call. Add an argument label to `enabled`, move unlabeled parameters with defaults after the required ones, or remove the default.",
						line: 4,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add argument label `enabled`"),
						],
					),
					DiagnosticSpec(
						message: "Unlabeled parameter `enabled: Bool` has a default value but is followed by unlabeled required parameter `dependency: Dependency`, so a generated `mock()` cannot leave `enabled` out of its call. Add an argument label to `enabled`, move unlabeled parameters with defaults after the required ones, or remove the default.",
						line: 8,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add argument label `enabled`"),
						],
					),
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer.",
						line: 4,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_fixit_updatesInitializerWhenExistingInitializerHasIncorrectAccessModifier() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class UserService: Instantiable {
					private init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				""",
				expandedSource: """
				public final class UserService: Instantiable {
					private init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					let a: A
					let b: B
					let c: C
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public` modifier",
				],
				fixedSource: """
				@Instantiable
				public final class UserService: Instantiable {
					public init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesInitializerWhenExistingInitializerHasIncorrectAccessModifierWithCorrectEarlierModifier() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class UserService: Instantiable {
					final private init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				""",
				expandedSource: """
				public final class UserService: Instantiable {
					final private init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					let a: A
					let b: B
					let c: C
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public` modifier",
				],
				fixedSource: """
				@Instantiable
				public final class UserService: Instantiable {
					final public init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesInitializerWhenExistingInitializerHasIncorrectAccessModifierWithCorrectLaterModifier() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class UserService: Instantiable {
					private final init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				""",
				expandedSource: """
				public final class UserService: Instantiable {
					private final init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					let a: A
					let b: B
					let c: C
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public` modifier",
				],
				fixedSource: """
				@Instantiable
				public final class UserService: Instantiable {
					public final init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesInitializerWhenExistingInitializerIsMissingAccessModifierAndAnotherInitializerWithMissingArgument() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class UserService: Instantiable {
					init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					private init(a: A, b: B) {
						self.a = a
						self.b = b
						c = C()
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				""",
				expandedSource: """
				public final class UserService: Instantiable {
					init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					private init(a: A, b: B) {
						self.a = a
						self.b = b
						c = C()
					}

					let a: A
					let b: B
					let c: C
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public` modifier",
				],
				fixedSource: """
				@Instantiable
				public final class UserService: Instantiable {
					public init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					private init(a: A, b: B) {
						self.a = a
						self.b = b
						c = C()
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				""",
			)
		}

		@Test
		func declaration_fixit_updatesInitializerWhenExistingInitializerIsMissingAccessModifierAndAnotherInitializerExistsWithExtraArgument() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class UserService: Instantiable {
					init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					public init(a: A, b: B, c: C, d: D) {
						self.a = a
						self.b = b
						self.c = c
						_ = d
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				""",
				expandedSource: """
				public final class UserService: Instantiable {
					init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					public init(a: A, b: B, c: C, d: D) {
						self.a = a
						self.b = b
						self.c = c
						_ = d
					}

					let a: A
					let b: B
					let c: C
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public` modifier",
				],
				fixedSource: """
				@Instantiable
				public final class UserService: Instantiable {
					public init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					public init(a: A, b: B, c: C, d: D) {
						self.a = a
						self.b = b
						self.c = c
						_ = d
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				""",
			)
		}

		@Test
		func extension_doesNotThrowErrorWhenMoreThanOneInstantiateMethodForSameBaseTypeWithDifferingGeneric() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Container: Instantiable {
				    public static func instantiate() -> Container<String> {
				        .init(value: "")
				    }
				    public static func instantiate() -> Container<Int> {
				        .init(value: 0)
				    }
				}
				""",
				expandedSource: """
				extension Container: Instantiable {
				    public static func instantiate() -> Container<String> {
				        .init(value: "")
				    }
				    public static func instantiate() -> Container<Int> {
				        .init(value: 0)
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_doesNotThrowErrorWhenFulfillingAdditionalType() {
			assertMacroExpansion(
				"""
				@Instantiable(fulfillingAdditionalTypes: [SendableContainer<String>.self])
				extension Container: Instantiable {
				    public static func instantiate() -> Container<String> {
				        .init(value: "")
				    }
				}
				""",
				expandedSource: """
				extension Container: Instantiable {
				    public static func instantiate() -> Container<String> {
				        .init(value: "")
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_fixit_addsFixitWhenNoConformancesDeclared() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class ExampleService {
				    public init() {}
				}
				""",
				expandedSource: """
				public final class ExampleService {
				    public init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type or extension must declare conformance to `Instantiable`.",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Declare conformance to `Instantiable`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Declare conformance to `Instantiable`",
				],
				fixedSource: """
				@Instantiable
				public final class ExampleService: Instantiable {
				    public init() {}
				}
				""",
			)
		}

		@Test
		func declaration_fixit_addsFixitWhenInstantiableConformanceMissing() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class ExampleService: CustomStringConvertible {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				""",
				expandedSource: """
				public final class ExampleService: CustomStringConvertible {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type or extension must declare conformance to `Instantiable`.",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Declare conformance to `Instantiable`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Declare conformance to `Instantiable`",
				],
				fixedSource: """
				@Instantiable
				public final class ExampleService: CustomStringConvertible, Instantiable {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				""",
			)
		}

		@Test
		func declaration_fixit_addsFixitWhenInstantiableConformanceMissingAndConformsElsewhereIsFalse() {
			assertMacroExpansion(
				"""
				@Instantiable(conformsElsewhere: false)
				public final class ExampleService: CustomStringConvertible {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				""",
				expandedSource: """
				public final class ExampleService: CustomStringConvertible {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type or extension must declare conformance to `Instantiable`.",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Declare conformance to `Instantiable`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Declare conformance to `Instantiable`",
				],
				fixedSource: """
				@Instantiable(conformsElsewhere: false)
				public final class ExampleService: CustomStringConvertible, Instantiable {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				""",
			)
		}

		@Test
		func declaration_doesNotAddFixitWhenRetroactiveInstantiableConformanceExists() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class ExampleService: @retroactive Instantiable, @retroactive CustomStringConvertible {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				""",
				expandedSource: """
				public final class ExampleService: @retroactive Instantiable, @retroactive CustomStringConvertible {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_fixit_addsFixitWhenMultipleInjectableMacrosOnTopOfSingleProperty() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Received @Instantiated let receivedA: ReceivedA
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "A property can be decorated with only one of @Instantiated, @Received, or @Forwarded.",
						line: 7,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Remove excessive attached macros"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Remove excessive attached macros",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Received let receivedA: ReceivedA
				}
				""",
			)
		}

		@Test
		func declaration_fixit_addsFixitWhenInjectableParameterHasInitializer() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA = .init()
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA = .init()
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`receivedA` must not have a default value: SafeDI passes every @Instantiated, @Received, and @Forwarded property in through the initializer. Remove `= .init()`.",
						line: 7,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Remove `= .init()`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Remove `= .init()`",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA 
				}
				""",
			)
		}

		@Test
		func declaration_fixit_addsFixitWhenInjectableActorIsNotPublicOrOpen() {
			assertMacroExpansion(
				"""
				@Instantiable
				actor ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				""",
				expandedSource: """
				actor ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must be `public` or `open`.",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public` modifier",
				],
				fixedSource: """
				@Instantiable
				public actor ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				""",
			)
		}

		@Test
		func declaration_fixit_addsFixitWhenInjectableClassIsNotPublicOrOpen() {
			assertMacroExpansion(
				"""
				@Instantiable
				class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				""",
				expandedSource: """
				class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must be `public` or `open`.",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public` modifier",
				],
				fixedSource: """
				@Instantiable
				public class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				""",
			)
		}

		@Test
		func declaration_fixit_addsFixitWhenInjectableFinalClassIsNotPublicOrOpen() {
			assertMacroExpansion(
				"""
				@Instantiable
				final class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				""",
				expandedSource: """
				final class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must be `public` or `open`.",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public` modifier",
				],
				fixedSource: """
				@Instantiable
				public final class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				""",
			)
		}

		@Test
		func declaration_fixit_addsFixitWhenInjectableClassIsInternal() {
			assertMacroExpansion(
				"""
				@Instantiable
				internal class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				""",
				expandedSource: """
				internal class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must be `public` or `open`.",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public` modifier",
				],
				fixedSource: """
				@Instantiable
				public class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				""",
			)
		}

		@Test
		func declaration_fixit_addsFixitWhenInjectableClassIsFileprivate() {
			assertMacroExpansion(
				"""
				@Instantiable
				fileprivate class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				""",
				expandedSource: """
				fileprivate class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must be `public` or `open`.",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public` modifier",
				],
				fixedSource: """
				@Instantiable
				public class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				""",
			)
		}

		@Test
		func declaration_fixit_addsFixitWhenInjectableClassIsPrivate() {
			assertMacroExpansion(
				"""
				@Instantiable
				private class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				""",
				expandedSource: """
				private class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must be `public` or `open`.",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public` modifier",
				],
				fixedSource: """
				@Instantiable
				public class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				""",
			)
		}

		@Test
		func declaration_fixit_addsFixitWhenInjectableStructIsNotPublicOrOpen() {
			assertMacroExpansion(
				"""
				@Instantiable
				struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				""",
				expandedSource: """
				struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must be `public` or `open`.",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public` modifier",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				""",
			)
		}

		@Test
		func declaration_fixit_addsFixitMissingRequiredInitializerWhenPropertyIsMissingInitializerAndThereAreNoDependencies() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    let uninitializedProperty: Int
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    let uninitializedProperty: Int
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type with no @Instantiated, @Received, or @Forwarded-decorated properties must have a `public` or `open` initializer that either takes no parameters or has a default value for each parameter.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init() {
				// The following properties are not decorated with the @Instantiated, @Received, or @Forwarded macros, do not have default values, and are not computed properties.
				uninitializedProperty = <#T##assign_uninitializedProperty#>
				}

				    let uninitializedProperty: Int
				}
				""",
			)
		}

		@Test
		func declaration_fixit_addsFixitMissingRequiredInitializerWhenPropertyIsMissingInitializer() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let receivedA: ReceivedA

				    let uninitializedProperty: Int
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    let receivedA: ReceivedA

				    let uninitializedProperty: Int
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. Parameters in this initializer that do not correspond to a decorated property must have default values.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(receivedA: ReceivedA) {
				self.receivedA = receivedA

				// The following properties are not decorated with the @Instantiated, @Received, or @Forwarded macros, do not have default values, and are not computed properties.
				uninitializedProperty = <#T##assign_uninitializedProperty#>
				}

				    @Instantiated let receivedA: ReceivedA

				    let uninitializedProperty: Int
				}
				""",
			)
		}

		@Test
		func declaration_fixit_addsFixitMissingRequiredInitializerWhenMultiplePropertiesAreMissingInitializer() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let receivedA: ReceivedA

				    var uninitializedProperty1: Int
				    let uninitializedProperty2: Int, uninitializedProperty3: Int, initializedProperty = "init"
				    let (uninitializedProperty4, uninitializedProperty5): (Int, Int)
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    let receivedA: ReceivedA

				    var uninitializedProperty1: Int
				    let uninitializedProperty2: Int, uninitializedProperty3: Int, initializedProperty = "init"
				    let (uninitializedProperty4, uninitializedProperty5): (Int, Int)
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. Parameters in this initializer that do not correspond to a decorated property must have default values.",
						line: 2,
						column: 44,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(receivedA: ReceivedA) {
				self.receivedA = receivedA

				// The following properties are not decorated with the @Instantiated, @Received, or @Forwarded macros, do not have default values, and are not computed properties.
				uninitializedProperty1 = <#T##assign_uninitializedProperty1#>
				uninitializedProperty2 = <#T##assign_uninitializedProperty2#>
				uninitializedProperty3 = <#T##assign_uninitializedProperty3#>
				(uninitializedProperty4, uninitializedProperty5) = <#T##assign_(uninitializedProperty4, uninitializedProperty5)#>
				}

				    @Instantiated let receivedA: ReceivedA

				    var uninitializedProperty1: Int
				    let uninitializedProperty2: Int, uninitializedProperty3: Int, initializedProperty = "init"
				    let (uninitializedProperty4, uninitializedProperty5): (Int, Int)
				}
				""",
			)
		}

		@Test
		func extension_fixit_addsFixitWhenNoConformancesDeclared() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type or extension must declare conformance to `Instantiable`.",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Declare conformance to `Instantiable`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Declare conformance to `Instantiable`",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiableConformanceMissing() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: CustomStringConvertible {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				""",
				expandedSource: """
				extension ExampleService: CustomStringConvertible {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type or extension must declare conformance to `Instantiable`.",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Declare conformance to `Instantiable`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Declare conformance to `Instantiable`",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: CustomStringConvertible, Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				""",
			)
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiableConformanceMissingAndConformsElsewhereIsFalse() {
			assertMacroExpansion(
				"""
				@Instantiable(conformsElsewhere: false)
				extension ExampleService: CustomStringConvertible {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				""",
				expandedSource: """
				extension ExampleService: CustomStringConvertible {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type or extension must declare conformance to `Instantiable`.",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Declare conformance to `Instantiable`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Declare conformance to `Instantiable`",
				],
				fixedSource: """
				@Instantiable(conformsElsewhere: false)
				extension ExampleService: CustomStringConvertible, Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				""",
			)
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodMissing() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension of `ExampleService` must have a `public static func instantiate() -> ExampleService` method.",
						line: 2,
						column: 41,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public static func instantiate() -> ExampleService` method"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public static func instantiate() -> ExampleService` method",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				public static func instantiate() -> ExampleService
				{}


				}
				""",
			)
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodIsNotPublic() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension must have an `instantiate()` method that is both `public` and `static`.",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Set `public static` modifiers"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Set `public static` modifiers",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodIsNotStatic() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public func instantiate() -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension must have an `instantiate()` method that is both `public` and `static`.",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Set `public static` modifiers"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Set `public static` modifiers",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodIsNotStaticOrPublic() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    func instantiate() -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension must have an `instantiate()` method that is both `public` and `static`.",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Set `public static` modifiers"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Set `public static` modifiers",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodReturnsIncorrectType() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> OtherExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> OtherExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension’s `instantiate()` method must return the extended type, `ExampleService`.",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Make `instantiate()` return `ExampleService`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Make `instantiate()` return `ExampleService`",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodReturnsTypeWrappedInArray() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> [ExampleService] { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> [ExampleService] { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension’s `instantiate()` method must return the extended type, `ExampleService`.",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Make `instantiate()` return `ExampleService`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Make `instantiate()` return `ExampleService`",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodIsAsync() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() async -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() async -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension’s `instantiate()` method must not throw or be async.",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Remove effect specifiers"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Remove effect specifiers",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodThrows() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() throws -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() throws -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension’s `instantiate()` method must not throw or be async.",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Remove effect specifiers"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Remove effect specifiers",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodIsAsyncAndThrows() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() async throws -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() async throws -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension’s `instantiate()` method must not throw or be async.",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Remove effect specifiers"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Remove effect specifiers",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodHasGenericParameter() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate<T>() -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate<T>() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension’s `instantiate()` method must not have a generic parameter.",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Remove generic parameter"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Remove generic parameter",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodHasGenericWhereClause() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Array: Instantiable {
				    public static func instantiate() -> Array where Element == String { fatalError() }
				}
				""",
				expandedSource: """
				extension Array: Instantiable {
				    public static func instantiate() -> Array where Element == String { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension must not have a generic `where` clause. To build a specialization of a generic type, return that specialization from an `instantiate()` method instead.",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Remove generic `where` clause"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Remove generic `where` clause",
				],
				fixedSource: """
				@Instantiable
				extension Array: Instantiable {
				    public static func instantiate() -> Array { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_fixit_addsFixitWhenExtensionHasGenericWhereClause() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Array: Instantiable where Element == String {
				    public static func instantiate() -> Array { fatalError() }
				}
				""",
				expandedSource: """
				extension Array: Instantiable where Element == String {
				    public static func instantiate() -> Array { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension must not have a generic `where` clause. To build a specialization of a generic type, return that specialization from an `instantiate()` method instead.",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Remove generic `where` clause"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Remove generic `where` clause",
				],
				fixedSource: """
				@Instantiable
				extension Array: Instantiable {
				    public static func instantiate() -> Array { fatalError() }
				}
				""",
			)
		}

		@Test
		func declaration_fixit_generatesRequiredInitializer_whenOnlyInitializerIsAsyncAndThrows() {
			// No fix-it addresses either reason the initializer cannot construct the type, as when it has one of them.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class ExampleService: Instantiable {
				    public init() async throws {}
				}
				""",
				expandedSource: """
				public final class ExampleService: Instantiable {
				    public init() async throws {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 49,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public final class ExampleService: Instantiable {
				public init() {}

				    public init() async throws {}
				}
				""",
			)
		}

		@Test
		func declaration_fixit_generatesRequiredInitializer_whenOnlyInitializerIsFailableAndAsync() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class ExampleService: Instantiable {
				    public init?() async {}
				}
				""",
				expandedSource: """
				public final class ExampleService: Instantiable {
				    public init?() async {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 2,
						column: 49,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add required initializer"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add required initializer",
				],
				fixedSource: """
				@Instantiable
				public final class ExampleService: Instantiable {
				public init() {}

				    public init?() async {}
				}
				""",
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenHandWrittenMockIsAsyncAndThrows() {
			// No fix-it addresses either reason the mock cannot construct the type, so the mock has nothing to fix, as
			// when it has one of them.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class ExampleService: Instantiable {
				    public init(dependency: Dependency) {}

				    public static func mock(dependency: Dependency) async throws -> ExampleService { fatalError() }

				    @Received let dependency: Dependency
				}
				""",
				expandedSource: """
				public final class ExampleService: Instantiable {
				    public init(dependency: Dependency) {}

				    public static func mock(dependency: Dependency) async throws -> ExampleService { fatalError() }

				    let dependency: Dependency
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_expandsWithoutIssue_whenHandWrittenMockIsAsyncAndThrows() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(dependency: Dependency) -> Service { fatalError() }

				    public static func mock(dependency: Dependency) async throws -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(dependency: Dependency) -> Service { fatalError() }

				    public static func mock(dependency: Dependency) async throws -> Service { fatalError() }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_fixit_addsMissingArgument_whenOnlyInitializerIsAsyncAndThrowsAndMissesAnArgument() {
			// A fix-it addresses one of the initializer's reasons, so the initializer is the one to fix.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class ExampleService: Instantiable {
				    public init() async throws {
				        _ = "keep me"
				    }

				    @Received let dependency: Dependency
				}
				""",
				expandedSource: """
				public final class ExampleService: Instantiable {
				    public init() async throws {
				        _ = "keep me"
				    }

				    let dependency: Dependency
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. This initializer has no parameter for `dependency: Dependency`.",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for dependency: Dependency"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add arguments for dependency: Dependency",
				],
				fixedSource: """
				@Instantiable
				public final class ExampleService: Instantiable {
				    public init(dependency: Dependency) async throws {
				        self.dependency = dependency
				        _ = "keep me"
				    }

				    @Received let dependency: Dependency
				}
				""",
			)
		}

		// MARK: mockAttributes Tests

		@Test
		func expandsWithoutIssueWhenMockAttributesIsProvided() {
			assertMacroExpansion(
				"""
				@Instantiable(mockAttributes: "@MainActor")
				public final class ExampleService: Instantiable {
				    public init() {}
				}
				""",
				expandedSource: """
				public final class ExampleService: Instantiable {
				    public init() {}
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func throwsErrorWhenMockAttributesIsNotStringLiteral() {
			assertMacroExpansion(
				"""
				@Instantiable(mockAttributes: someVariable)
				public final class ExampleService: Instantiable {
				    public init() {}
				}
				""",
				expandedSource: """
				public final class ExampleService: Instantiable {
				    public init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `mockAttributes` must be a string literal.",
						line: 1,
						column: 1,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		// MARK: generateMock Tests

		@Test
		func expandsWithoutIssue_whenGenerateMockIsTrue() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true)
				public struct ExampleService: Instantiable {
				    public init() {}
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init() {}
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func expandsWithoutIssue_whenGenerateMockIsFalse() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: false)
				public struct ExampleService: Instantiable {
				    public init() {}
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init() {}
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func throwsError_whenGenerateMockIsNotBoolLiteral() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: someVariable)
				public final class ExampleService: Instantiable {
				    public init() {}
				}
				""",
				expandedSource: """
				public final class ExampleService: Instantiable {
				    public init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `generateMock` must be a Bool literal (`true` or `false`).",
						line: 1,
						column: 1,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func throwsError_whenCustomMockNameIsNotStringLiteralOrNil() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: someVariable)
				public final class ExampleService: Instantiable {
				    public init() {}
				}
				""",
				expandedSource: """
				public final class ExampleService: Instantiable {
				    public init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `customMockName` must be a string literal or `nil`.",
						line: 1,
						column: 1,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesDiagnostic_whenGenerateMockIsTrueAndUserDefinedMockExists() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true)
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() -> MyService {
				        MyService()
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() -> MyService {
				        MyService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: #"@Instantiable-decorated type with `generateMock: true` cannot also have a hand-written `mock()` method because the generated and hand-written methods would have ambiguous signatures. Rename your method and add `customMockName` to `@Instantiable`."#,
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: #"Rename method to `customMock` and add `customMockName: "customMock"` to `@Instantiable`"#),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesDiagnostic_whenGenerateMockIsTrueAndUserDefinedMockExistsWithOtherArguments() {
			assertMacroExpansion(
				"""
				@MainActor @Instantiable(isRoot: true, generateMock: true)
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() -> MyService {
				        MyService()
				    }
				}
				""",
				expandedSource: """
				@MainActor
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() -> MyService {
				        MyService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: #"@Instantiable-decorated type with `generateMock: true` cannot also have a hand-written `mock()` method because the generated and hand-written methods would have ambiguous signatures. Rename your method and add `customMockName` to `@Instantiable`."#,
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: #"Rename method to `customMock` and add `customMockName: "customMock"` to `@Instantiable`"#),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func noDiagnostic_whenGenerateMockIsFalseAndUserDefinedMockExists() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() -> MyService {
				        MyService()
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() -> MyService {
				        MyService()
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		// MARK: customMockName Tests

		@Test
		func producesDiagnostic_whenCustomMockNameIsSetWithoutGenerateMock() {
			assertMacroExpansion(
				"""
				@Instantiable(customMockName: "customMock")
				public struct MyService: Instantiable {
				    public init() {}

				    public static func customMock() -> MyService {
				        MyService()
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init() {}

				    public static func customMock() -> MyService {
				        MyService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`customMockName` requires `generateMock: true` or `mockOnly: true`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `generateMock: true` or `mockOnly: true` to `@Instantiable`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct MyService: Instantiable {
				    public init() {}

				    public static func customMock() -> MyService {
				        MyService()
				    }
				}
				""",
			)
		}

		@Test
		func fixItInsertsGenerateMockBeforeCustomMockName_whenOtherArgumentsArePresent() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true, customMockName: "customMock")
				public struct MyService: Instantiable {
				    public init() {}

				    public static func customMock() -> MyService {
				        MyService()
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init() {}

				    public static func customMock() -> MyService {
				        MyService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`customMockName` requires `generateMock: true` or `mockOnly: true`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `generateMock: true` or `mockOnly: true` to `@Instantiable`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(isRoot: true, generateMock: true, customMockName: "customMock")
				public struct MyService: Instantiable {
				    public init() {}

				    public static func customMock() -> MyService {
				        MyService()
				    }
				}
				""",
			)
		}

		@Test
		func producesDiagnostic_whenCustomMockNameMethodIsNotFound() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct MyService: Instantiable {
				    public init() {}
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`customMockName` names `customMock`, but this declaration has no method named `customMock`. Add a `public static func customMock(…)` method.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `public static func customMock(…)` method"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesDiagnostic_whenCustomMockNameMethodIsNotFoundAndTypeHasDependencies() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct MyService: Instantiable {
				    public init(dependency: Dependency) {
				        self.dependency = dependency
				    }
				    @Received let dependency: Dependency
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init(dependency: Dependency) {
				        self.dependency = dependency
				    }
				    let dependency: Dependency
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`customMockName` names `customMock`, but this declaration has no method named `customMock`. Add a `public static func customMock(…)` method.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `public static func customMock(…)` method"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesDiagnostic_whenCustomMockNameMethodIsNotFoundAndTypeHasMultipleDependencies() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct MyService: Instantiable {
				    public init(dependencyA: DependencyA, dependencyB: DependencyB) {
				        self.dependencyA = dependencyA
				        self.dependencyB = dependencyB
				    }
				    @Received let dependencyA: DependencyA
				    @Received let dependencyB: DependencyB
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init(dependencyA: DependencyA, dependencyB: DependencyB) {
				        self.dependencyA = dependencyA
				        self.dependencyB = dependencyB
				    }
				    let dependencyA: DependencyA
				    let dependencyB: DependencyB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`customMockName` names `customMock`, but this declaration has no method named `customMock`. Add a `public static func customMock(…)` method.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `public static func customMock(…)` method"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func noDiagnostic_whenCustomMockNameIsSetAndMethodExists() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct MyService: Instantiable {
				    public init() {}

				    public static func customMock() -> MyService {
				        MyService()
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init() {}

				    public static func customMock() -> MyService {
				        MyService()
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesDiagnostic_whenCustomMockNameIsSetWithoutGenerateMock() {
			assertMacroExpansion(
				"""
				@Instantiable(customMockName: "customMock")
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func customMock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func customMock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`customMockName` requires `generateMock: true` or `mockOnly: true`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `generateMock: true` or `mockOnly: true` to `@Instantiable`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(generateMock: true, customMockName: "customMock")
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func customMock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
			)
		}

		@Test
		func extension_fixItInsertsGenerateMockBeforeCustomMockName_whenOtherArgumentsArePresent() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true, customMockName: "customMock")
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func customMock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func customMock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`customMockName` requires `generateMock: true` or `mockOnly: true`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `generateMock: true` or `mockOnly: true` to `@Instantiable`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(isRoot: true, generateMock: true, customMockName: "customMock")
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func customMock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
			)
		}

		@Test
		func extension_producesDiagnostic_whenCustomMockNameMethodIsNotFound() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`customMockName` names `customMock`, but this declaration has no method named `customMock`. Add a `public static func customMock(…)` method.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `public static func customMock(…)` method"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_noDiagnostic_whenCustomMockNameIsSetAndMethodExists() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func customMock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func customMock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesDiagnostic_whenMockMethodExistsAlongsideCustomMockName_withRemoveFixIt() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct MyService: Instantiable {
				    public init() {}

				    public static func customMock() -> MyService {
				        MyService()
				    }

				    public static func mock() -> MyService {
				        MyService()
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init() {}

				    public static func customMock() -> MyService {
				        MyService()
				    }

				    public static func mock() -> MyService {
				        MyService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: #"This `mock()` method conflicts with the `mock()` that `generateMock: true` generates. This type’s hand-written mock is `customMock`, which `customMockName` names; remove this method or rename it."#,
						line: 9,
						column: 5,
						fixIts: [
							FixItSpec(message: #"Remove this `mock()` method"#),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesDiagnostic_whenMockMethodHasNonDependencyParameterWithoutDefault_andNoDependencies() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock(notADependency: NotADependency) -> MyService {
				        MyService()
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock(notADependency: NotADependency) -> MyService {
				        MyService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This `mock()` method’s parameter `notADependency: NotADependency` does not correspond to a dependency, so it must have a default value.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add default values to `mock()` non-dependency parameters for notADependency: NotADependency"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesDiagnostic_whenUnlabeledDefaultPrecedesUnlabeledRequiredParameterOnInit() {
			// Mock override surface can't elide the earlier `_`-labeled default
			// (Swift requires the positional slot to be filled when the later
			// unlabeled param is required) and can't expose an unlabeled
			// parameter as a labeled field on `SafeDIMockConfiguration`.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct Child: Instantiable {
				    public init(_ enabled: Bool = false, _ leaf: Leaf) {
				        self.leaf = leaf
				    }
				    @Instantiated let leaf: Leaf
				}
				""",
				expandedSource: """
				public struct Child: Instantiable {
				    public init(_ enabled: Bool = false, _ leaf: Leaf) {
				        self.leaf = leaf
				    }
				    let leaf: Leaf
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Unlabeled parameter `enabled: Bool` has a default value but is followed by unlabeled required parameter `leaf: Leaf`, so a generated `mock()` cannot leave `enabled` out of its call. Add an argument label to `enabled`, move unlabeled parameters with defaults after the required ones, or remove the default.",
						line: 3,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add argument label `enabled`"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesDiagnostic_whenDefaultExpressionReferencesSelfOnInit() {
			// `Self.defaultName` binds to the type under decoration inside the
			// init, but SafeDI's generated mock may inline the default
			// expression inside another type's override struct, where `Self`
			// would bind to the wrong type.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyType: Instantiable {
				    public init(name: String = Self.defaultName) {
				        self.name = name
				    }
				    public static let defaultName = "fallback"
				    let name: String
				}
				""",
				expandedSource: """
				public struct MyType: Instantiable {
				    public init(name: String = Self.defaultName) {
				        self.name = name
				    }
				    public static let defaultName = "fallback"
				    let name: String
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The default value of `name` refers to `Self`. A generated `mock()` repeats this default outside `MyType`, where `Self` names a different type. Write `MyType` instead of `Self`, or remove the default.",
						line: 3,
						column: 17,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesDiagnostic_whenDefaultExpressionReferencesSelfOnCustomMock() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct MyType: Instantiable {
				    public init() {}
				    public static let defaultName = "fallback"
				    public static func customMock(name: String = Self.defaultName) -> MyType {
				        MyType()
				    }
				}
				""",
				expandedSource: """
				public struct MyType: Instantiable {
				    public init() {}
				    public static let defaultName = "fallback"
				    public static func customMock(name: String = Self.defaultName) -> MyType {
				        MyType()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The default value of `name` refers to `Self`. A generated `mock()` repeats this default outside `MyType`, where `Self` names a different type. Write `MyType` instead of `Self`, or remove the default.",
						line: 5,
						column: 35,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesNoDiagnostic_whenInitDefaultReferencesSelfButCustomMockExists() {
			// When the type has a `customMock` method, SafeDI uses the mock
			// method (not the init) to construct the instance for mocks, so
			// init defaults never reach the override surface. `Self.*` in an
			// init default is safe in that case.
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct MyType: Instantiable {
				    public init(name: String = Self.defaultName) {
				        self.name = name
				    }
				    public static let defaultName = "fallback"
				    public static func customMock() -> MyType { MyType() }
				    let name: String
				}
				""",
				expandedSource: """
				public struct MyType: Instantiable {
				    public init(name: String = Self.defaultName) {
				        self.name = name
				    }
				    public static let defaultName = "fallback"
				    public static func customMock() -> MyType { MyType() }
				    let name: String
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesNoDiagnostic_whenDefaultExpressionReferencesSelfOnUnlabeledNonDependency() {
			// `_`-labeled non-dependency defaults are elided from the mock
			// call site (`ScopeGenerator.callSiteArguments` filters them and
			// `rootDefaultParameters` excludes them), so Swift's default-
			// argument thunk fires in the callee's scope where `Self.*`
			// resolves correctly.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyType: Instantiable {
				    public init(_ value: Int = Self.defaultValue) {
				        self.value = value
				    }
				    public static let defaultValue = 42
				    let value: Int
				}
				""",
				expandedSource: """
				public struct MyType: Instantiable {
				    public init(_ value: Int = Self.defaultValue) {
				        self.value = value
				    }
				    public static let defaultValue = 42
				    let value: Int
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesNoDiagnostic_whenDefaultExpressionReferencesSelfOnDependencyParameter() {
			// Dependency parameters are always threaded explicitly at the mock
			// call site — their default expressions never reach the override
			// surface — so `Self.*` inside a dep default is safe.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyType: Instantiable {
				    public init(service: Service = Self.makeService()) {
				        self.service = service
				    }
				    public static func makeService() -> Service { Service() }
				    @Instantiated let service: Service
				}
				""",
				expandedSource: """
				public struct MyType: Instantiable {
				    public init(service: Service = Self.makeService()) {
				        self.service = service
				    }
				    public static func makeService() -> Service { Service() }
				    let service: Service
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesNoDiagnostic_whenDefaultExpressionReferencesSelfOnDependencyParameterWrittenWithoutBackticks() {
			// `default` names the property declared as `` `default` ``, so the parameter is a dependency parameter.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyType: Instantiable {
				    public init(default: Service = Self.makeService()) {
				        self.default = `default`
				    }
				    public static func makeService() -> Service { Service() }
				    @Instantiated let `default`: Service
				}
				""",
				expandedSource: """
				public struct MyType: Instantiable {
				    public init(default: Service = Self.makeService()) {
				        self.default = `default`
				    }
				    public static func makeService() -> Service { Service() }
				    let `default`: Service
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesNoDiagnostic_whenDependencyParameterWrittenWithoutBackticksHasReservedArgumentLabel() {
			// A dependency parameter's argument label is not a `mock()` parameter, so SafeDI reserves nothing for it.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyType: Instantiable {
				    public init(safeDIBuilder default: Service = Service()) {
				        self.default = `default`
				    }
				    @Instantiated let `default`: Service
				}
				""",
				expandedSource: """
				public struct MyType: Instantiable {
				    public init(safeDIBuilder default: Service = Service()) {
				        self.default = `default`
				    }
				    let `default`: Service
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesNoDiagnostic_whenDefaultExpressionReferencesFileScopedSymbol() {
			// Module-scoped and file-scoped references are fine — they resolve
			// the same way from any caller, including the generated override
			// struct.
			assertMacroExpansion(
				"""
				public let sharedDefaultName = "fallback"

				@Instantiable
				public struct MyType: Instantiable {
				    public init(name: String = sharedDefaultName) {
				        self.name = name
				    }
				    let name: String
				}
				""",
				expandedSource: """
				public let sharedDefaultName = "fallback"
				public struct MyType: Instantiable {
				    public init(name: String = sharedDefaultName) {
				        self.name = name
				    }
				    let name: String
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesDiagnostic_whenDefaultExpressionCallsSelfAsConstructor() {
			// `Self()` as a default binds to the decorated type in the callee
			// but to the caller's type if the default is inlined at the call
			// site — same failure mode as `Self.member`, caught via the bare
			// `Self` DeclReferenceExpr match.
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct MyType: Instantiable {
				    public init() {}
				    public static func customMock(fallback: MyType = Self()) -> MyType {
				        MyType()
				    }
				}
				""",
				expandedSource: """
				public struct MyType: Instantiable {
				    public init() {}
				    public static func customMock(fallback: MyType = Self()) -> MyType {
				        MyType()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The default value of `fallback` refers to `Self`. A generated `mock()` repeats this default outside `MyType`, where `Self` names a different type. Write `MyType` instead of `Self`, or remove the default.",
						line: 4,
						column: 35,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesNoDiagnostic_whenSecondaryInitDefaultReferencesSelf() {
			// Only the first `isValid(forFulfilling:)` init is used for mock
			// construction (see `InstantiableVisitor:377`). Secondary inits
			// with `Self.*` defaults never reach the override surface, so
			// diagnosing them would be a false positive.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyType: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }
				    public convenience init(title: String = Self.defaultTitle) {
				        self.init(service: Service())
				    }
				    public static let defaultTitle = "fallback"
				    @Instantiated let service: Service
				}
				""",
				expandedSource: """
				public struct MyType: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }
				    public convenience init(title: String = Self.defaultTitle) {
				        self.init(service: Service())
				    }
				    public static let defaultTitle = "fallback"
				    let service: Service
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesDiagnostic_whenDefaultExpressionReferencesSelfInArrayGeneric() {
			// `[Self]()` places `Self` inside an `ArrayTypeSyntax` nested in an
			// expression — caught via `TypeDescription.containsSelf`'s `.array`
			// recursion.
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct MyType: Instantiable {
				    public init() {}
				    public static func customMock(fallback: [MyType] = [Self]()) -> MyType {
				        MyType()
				    }
				}
				""",
				expandedSource: """
				public struct MyType: Instantiable {
				    public init() {}
				    public static func customMock(fallback: [MyType] = [Self]()) -> MyType {
				        MyType()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The default value of `fallback` refers to `Self`. A generated `mock()` repeats this default outside `MyType`, where `Self` names a different type. Write `MyType` instead of `Self`, or remove the default.",
						line: 4,
						column: 35,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesDiagnostic_whenDefaultExpressionReferencesSelfDotSelf() {
			// `Self.self` parses as a member access on a `DeclReferenceExpr` —
			// caught by the `DeclReferenceExprSyntax` visitor.
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct MyType: Instantiable {
				    public init() {}
				    public static func customMock(metatype: MyType.Type = Self.self) -> MyType {
				        MyType()
				    }
				}
				""",
				expandedSource: """
				public struct MyType: Instantiable {
				    public init() {}
				    public static func customMock(metatype: MyType.Type = Self.self) -> MyType {
				        MyType()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The default value of `metatype` refers to `Self`. A generated `mock()` repeats this default outside `MyType`, where `Self` names a different type. Write `MyType` instead of `Self`, or remove the default.",
						line: 4,
						column: 35,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesDiagnostic_whenDefaultExpressionReferencesSelfInTypeExpression() {
			// `Optional<Self>.none`, `Result<Self, E>.failure(...)`, and
			// similar defaults place `Self` inside an `IdentifierTypeSyntax`
			// in a generic argument clause — not an expression-level
			// `DeclReferenceExpr`. Those must still be flagged so the
			// override struct's caller-scope `Self` binding doesn't silently
			// produce the wrong type.
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct MyType: Instantiable {
				    public init() {}
				    public static func customMock(fallback: Optional<MyType> = Optional<Self>.none) -> MyType {
				        MyType()
				    }
				}
				""",
				expandedSource: """
				public struct MyType: Instantiable {
				    public init() {}
				    public static func customMock(fallback: Optional<MyType> = Optional<Self>.none) -> MyType {
				        MyType()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The default value of `fallback` refers to `Self`. A generated `mock()` repeats this default outside `MyType`, where `Self` names a different type. Write `MyType` instead of `Self`, or remove the default.",
						line: 4,
						column: 35,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesDiagnostic_whenExtensionCustomMockDefaultReferencesSelf() {
			// Extension-based customMock goes through a different validation
			// branch than concrete customMock. `Self` on a non-dependency
			// default must be caught there too.
			assertMacroExpansion(
				"""
				public struct MyType {}

				@Instantiable(generateMock: true, customMockName: "customMock")
				extension MyType: Instantiable {
				    public static func instantiate() -> MyType { MyType() }
				    public static func customMock(fallback: String = Self.defaultName) -> MyType {
				        MyType()
				    }
				    public static let defaultName = "fallback"
				}
				""",
				expandedSource: """
				public struct MyType {}
				extension MyType: Instantiable {
				    public static func instantiate() -> MyType { MyType() }
				    public static func customMock(fallback: String = Self.defaultName) -> MyType {
				        MyType()
				    }
				    public static let defaultName = "fallback"
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The default value of `fallback` refers to `Self`. A generated `mock()` repeats this default outside `MyType`, where `Self` names a different type. Write `MyType` instead of `Self`, or remove the default.",
						line: 6,
						column: 35,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesNoDiagnostic_whenDefaultExpressionReferencesMemberOfModuleType() {
			// Member access whose base isn't `Self` — e.g., `Config.fallback` —
			// resolves identically at the caller and the callee, so the
			// diagnostic must not fire. Exercises the non-`Self` branch of
			// the MemberAccessExpr visitor.
			assertMacroExpansion(
				"""
				public enum Config {
				    public static let fallback = "fallback"
				}

				@Instantiable
				public struct MyType: Instantiable {
				    public init(name: String = Config.fallback) {
				        self.name = name
				    }
				    let name: String
				}
				""",
				expandedSource: """
				public enum Config {
				    public static let fallback = "fallback"
				}
				public struct MyType: Instantiable {
				    public init(name: String = Config.fallback) {
				        self.name = name
				    }
				    let name: String
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func producesNoDiagnostic_whenTrailingUnlabeledParametersAllHaveDefaults() {
			// `init(_ a: Int = 0, _ b: Int = 1)` is fine — both trailing `_`
			// defaults are elided together as a suffix, call site becomes
			// `Type()`.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyType: Instantiable {
				    public init(_ a: Int = 0, _ b: Int = 1) {}
				}
				""",
				expandedSource: """
				public struct MyType: Instantiable {
				    public init(_ a: Int = 0, _ b: Int = 1) {}
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		// MARK: generateMock + Hand-Written Mock Coexistence Tests

		@Test
		func mockMethodWithGenerateMockAndDependenciesProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true)
				public struct MyService: Instantiable {
				    public init(dependency: Dependency) {
				        self.dependency = dependency
				    }
				    @Received let dependency: Dependency

				    public static func mock(dependency: Dependency) -> MyService {
				        MyService(dependency: dependency)
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init(dependency: Dependency) {
				        self.dependency = dependency
				    }
				    let dependency: Dependency

				    public static func mock(dependency: Dependency) -> MyService {
				        MyService(dependency: dependency)
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: #"@Instantiable-decorated type with `generateMock: true` cannot also have a hand-written `mock()` method because the generated and hand-written methods would have ambiguous signatures. Rename your method and add `customMockName` to `@Instantiable`."#,
						line: 8,
						column: 5,
						fixIts: [
							FixItSpec(message: #"Rename method to `customMock` and add `customMockName: "customMock"` to `@Instantiable`"#),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func mockMethodWithGenerateMockAndDefaultOnDependencyProducesNoDiagnostic_whenCustomMockNameIsSet() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct MyService: Instantiable {
				    public init(dependency: Dependency) {
				        self.dependency = dependency
				    }
				    @Received let dependency: Dependency

				    public static func customMock(dependency: Dependency = Dependency()) -> MyService {
				        MyService(dependency: dependency)
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init(dependency: Dependency) {
				        self.dependency = dependency
				    }
				    let dependency: Dependency

				    public static func customMock(dependency: Dependency = Dependency()) -> MyService {
				        MyService(dependency: dependency)
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func mockMethodWithGenerateMockAndDefaultOnNonDependencyProducesNoDiagnostic_whenCustomMockNameIsSet() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct MyService: Instantiable {
				    public init(dependency: Dependency) {
				        self.dependency = dependency
				    }
				    @Received let dependency: Dependency

				    public static func customMock(dependency: Dependency, extra: Bool = false) -> MyService {
				        MyService(dependency: dependency)
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init(dependency: Dependency) {
				        self.dependency = dependency
				    }
				    let dependency: Dependency

				    public static func customMock(dependency: Dependency, extra: Bool = false) -> MyService {
				        MyService(dependency: dependency)
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func mockMethodWithNonDependencyMissingDefaultProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyService: Instantiable {
				    public init(dependency: Dependency) {
				        self.dependency = dependency
				    }
				    @Received let dependency: Dependency

				    public static func mock(dependency: Dependency, extra: Bool) -> MyService {
				        MyService(dependency: dependency)
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init(dependency: Dependency) {
				        self.dependency = dependency
				    }
				    let dependency: Dependency

				    public static func mock(dependency: Dependency, extra: Bool) -> MyService {
				        MyService(dependency: dependency)
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This `mock()` method’s parameter `extra: Bool` does not correspond to a dependency, so it must have a default value.",
						line: 8,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add default values to `mock()` non-dependency parameters for extra: Bool"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_mockMethodWithGenerateMockAndDependenciesProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true)
				extension ExampleService: Instantiable {
				    public static func instantiate(dependency: Dependency) -> ExampleService { fatalError() }

				    public static func mock(dependency: Dependency) -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate(dependency: Dependency) -> ExampleService { fatalError() }

				    public static func mock(dependency: Dependency) -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: #"@Instantiable-decorated type with `generateMock: true` cannot also have a hand-written `mock()` method because the generated and hand-written methods would have ambiguous signatures. Rename your method and add `customMockName` to `@Instantiable`."#,
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: #"Rename method to `customMock` and add `customMockName: "customMock"` to `@Instantiable`"#),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_mockMethodWithGenerateMockAndNoDependenciesProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true)
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: #"@Instantiable-decorated type with `generateMock: true` cannot also have a hand-written `mock()` method because the generated and hand-written methods would have ambiguous signatures. Rename your method and add `customMockName` to `@Instantiable`."#,
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: #"Rename method to `customMock` and add `customMockName: "customMock"` to `@Instantiable`"#),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_mockMethodWithGenerateMockAndCustomMockNameProducesNoDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				extension ExampleService: Instantiable {
				    public static func instantiate(dependency: Dependency) -> ExampleService { fatalError() }

				    public static func customMock(dependency: Dependency = Dependency()) -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate(dependency: Dependency) -> ExampleService { fatalError() }

				    public static func customMock(dependency: Dependency = Dependency()) -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_mockMethodWithNonDependencyMissingDefaultProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate(dependency: Dependency) -> ExampleService { fatalError() }

				    public static func mock(dependency: Dependency, extra: Bool) -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate(dependency: Dependency) -> ExampleService { fatalError() }

				    public static func mock(dependency: Dependency, extra: Bool) -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This `mock()` method’s parameter `extra: Bool` does not correspond to a dependency, so it must have a default value.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add default values to `mock()` non-dependency parameters for extra: Bool"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesDiagnostic_whenMockMethodExistsAlongsideCustomMockName() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func customMock() -> ExampleService {
				        ExampleService()
				    }

				    public static func mock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func customMock() -> ExampleService {
				        ExampleService()
				    }

				    public static func mock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: #"This `mock()` method conflicts with the `mock()` that `generateMock: true` generates. This type’s hand-written mock is `customMock`, which `customMockName` names; remove this method or rename it."#,
						line: 9,
						column: 5,
						fixIts: [
							FixItSpec(message: #"Remove this `mock()` method"#),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_secondMockOverloadWithNonDependencyMissingDefaultProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Container: Instantiable {
				    public static func instantiate() -> Container<Bool> { fatalError() }

				    public static func mock() -> Container<Bool> {
				        fatalError()
				    }

				    public static func mock(extra: Bool) -> Container<Int> {
				        fatalError()
				    }
				}
				""",
				expandedSource: """
				extension Container: Instantiable {
				    public static func instantiate() -> Container<Bool> { fatalError() }

				    public static func mock() -> Container<Bool> {
				        fatalError()
				    }

				    public static func mock(extra: Bool) -> Container<Int> {
				        fatalError()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This `mock()` method’s parameter `extra: Bool` does not correspond to a dependency, so it must have a default value.",
						line: 9,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add default values to `mock()` non-dependency parameters for extra: Bool"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		// MARK: Mock Method Validation Tests

		@Test
		func mockMethodMissingDependencyProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyService: Instantiable {
				    public init(dep: Dep) {
				        self.dep = dep
				    }
				    @Received let dep: Dep

				    public static func mock() -> MyService {
				        MyService(dep: Dep())
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init(dep: Dep) {
				        self.dep = dep
				    }
				    let dep: Dep

				    public static func mock() -> MyService {
				        MyService(dep: Dep())
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This `mock()` method has no parameter for `dep: Dep`. A hand-written mock must take a parameter for each @Instantiated, @Received, or @Forwarded-decorated property; extra parameters with default values are allowed.",
						line: 8,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add `mock()` arguments for dep: Dep"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `mock()` arguments for dep: Dep",
				],
				fixedSource: """
				@Instantiable
				public struct MyService: Instantiable {
				    public init(dep: Dep) {
				        self.dep = dep
				    }
				    @Received let dep: Dep

				    public static func mock(dep: Dep) -> MyService {
				        MyService(dep: Dep())
				    }
				}
				""",
			)
		}

		@Test
		func mockMethodMissingMultipleDependenciesProducesDiagnosticWithFixIt() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyService: Instantiable {
				    public init(depA: DepA, depB: DepB) {
				        self.depA = depA
				        self.depB = depB
				    }
				    @Received let depA: DepA
				    @Instantiated let depB: DepB

				    public static func mock() -> MyService {
				        MyService(depA: DepA(), depB: DepB())
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init(depA: DepA, depB: DepB) {
				        self.depA = depA
				        self.depB = depB
				    }
				    let depA: DepA
				    let depB: DepB

				    public static func mock() -> MyService {
				        MyService(depA: DepA(), depB: DepB())
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This `mock()` method has no parameter for `depA: DepA`, `depB: DepB`. A hand-written mock must take a parameter for each @Instantiated, @Received, or @Forwarded-decorated property; extra parameters with default values are allowed.",
						line: 10,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add `mock()` arguments for depA: DepA, depB: DepB"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `mock()` arguments for depA: DepA, depB: DepB",
				],
				fixedSource: """
				@Instantiable
				public struct MyService: Instantiable {
				    public init(depA: DepA, depB: DepB) {
				        self.depA = depA
				        self.depB = depB
				    }
				    @Received let depA: DepA
				    @Instantiated let depB: DepB

				    public static func mock(
				depA: DepA, depB: DepB
				) -> MyService {
				        MyService(depA: DepA(), depB: DepB())
				    }
				}
				""",
			)
		}

		@Test
		func mockMethodMissingDependency_namesCustomMockMethod_whenCustomMockNameIsSet() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "preview")
				public struct MyService: Instantiable {
				    public init(dep: Dep) {
				        self.dep = dep
				    }
				    @Received let dep: Dep

				    public static func preview() -> MyService {
				        MyService(dep: Dep())
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init(dep: Dep) {
				        self.dep = dep
				    }
				    let dep: Dep

				    public static func preview() -> MyService {
				        MyService(dep: Dep())
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This `preview()` method has no parameter for `dep: Dep`. A hand-written mock must take a parameter for each @Instantiated, @Received, or @Forwarded-decorated property; extra parameters with default values are allowed.",
						line: 8,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add `preview()` arguments for dep: Dep"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func mockMethodWithSeveralNonDependencyParametersWithoutDefaults_producesDiagnosticNamingEachParameter() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyService: Instantiable {
				    public init(dep: Dep) {
				        self.dep = dep
				    }
				    @Received let dep: Dep

				    public static func mock(dep: Dep, extra: Bool, count: Int) -> MyService {
				        MyService(dep: dep)
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init(dep: Dep) {
				        self.dep = dep
				    }
				    let dep: Dep

				    public static func mock(dep: Dep, extra: Bool, count: Int) -> MyService {
				        MyService(dep: dep)
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This `mock()` method’s parameters `extra: Bool`, `count: Int` do not correspond to a dependency, so they must have default values.",
						line: 8,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add default values to `mock()` non-dependency parameters for extra: Bool, count: Int"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_fixit_addsDefaultValueToBacktickedNonDependencyMockParameter_whenMockOnlyTypeMockLacksDefault() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true)
				public struct ExampleService {
				    @Received let dependency: Dependency

				    public static func mock(dependency: Dependency, `extra`: Bool) -> ExampleService {
				        fatalError()
				    }
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    let dependency: Dependency

				    public static func mock(dependency: Dependency, `extra`: Bool) -> ExampleService {
				        fatalError()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This `mock()` method’s parameter `extra: Bool` does not correspond to a dependency, so it must have a default value.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add default values to `mock()` non-dependency parameters for extra: Bool"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockOnly: true)
				public struct ExampleService {
				    @Received let dependency: Dependency

				    public static func mock(dependency: Dependency, `extra`: Bool = <#default#>) -> ExampleService {
				        fatalError()
				    }
				}
				""",
			)
		}

		@Test
		func extension_fixit_addsDefaultValueToBacktickedNonDependencyMockParameter_whenMockOnlyExtensionMockLacksDefault() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true)
				extension ExternalService {
				    public static func mock(`extra`: Bool) -> ExternalService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExternalService {
				    public static func mock(`extra`: Bool) -> ExternalService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This `mock()` method’s parameter `extra: Bool` does not correspond to a dependency, so it must have a default value.",
						line: 3,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add default values to `mock()` non-dependency parameters for extra: Bool"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockOnly: true)
				extension ExternalService {
				    public static func mock(`extra`: Bool = <#default#>) -> ExternalService { fatalError() }
				}
				""",
			)
		}

		@Test
		func mockMethodWithPartialDependenciesProducesFixItPreservingExistingParameters() {
			// mock() already has depA but is missing depB.
			// Fix-it should reorder: depA first, then add depB, preserving existing extra default params.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyService: Instantiable {
				    public init(depA: DepA, depB: DepB) {
				        self.depA = depA
				        self.depB = depB
				    }
				    @Received let depA: DepA
				    @Instantiated let depB: DepB

				    public static func mock(depA: DepA, extra: Bool = false) -> MyService {
				        MyService(depA: depA, depB: DepB())
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init(depA: DepA, depB: DepB) {
				        self.depA = depA
				        self.depB = depB
				    }
				    let depA: DepA
				    let depB: DepB

				    public static func mock(depA: DepA, extra: Bool = false) -> MyService {
				        MyService(depA: depA, depB: DepB())
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This `mock()` method has no parameter for `depB: DepB`. A hand-written mock must take a parameter for each @Instantiated, @Received, or @Forwarded-decorated property; extra parameters with default values are allowed.",
						line: 10,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add `mock()` arguments for depB: DepB"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func mockMethodMissingDependencyProducesFixItKeepingExtraParametersInSourceOrder() {
			// The extra parameters were appended in dictionary order, which changes from run to run.
			// Six parameters make keeping their order by chance unlikely.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyService: Instantiable {
				    public init(dependency: Dependency) {
				        self.dependency = dependency
				    }
				    @Received let dependency: Dependency

				    public static func mock(alpha: Int = 1, bravo: Int = 2, charlie: Int = 3, delta: Int = 4, echo: Int = 5, foxtrot: Int = 6) -> MyService {
				        MyService(dependency: Dependency())
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init(dependency: Dependency) {
				        self.dependency = dependency
				    }
				    let dependency: Dependency

				    public static func mock(alpha: Int = 1, bravo: Int = 2, charlie: Int = 3, delta: Int = 4, echo: Int = 5, foxtrot: Int = 6) -> MyService {
				        MyService(dependency: Dependency())
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This `mock()` method has no parameter for `dependency: Dependency`. A hand-written mock must take a parameter for each @Instantiated, @Received, or @Forwarded-decorated property; extra parameters with default values are allowed.",
						line: 8,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add `mock()` arguments for dependency: Dependency"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `mock()` arguments for dependency: Dependency",
				],
				fixedSource: """
				@Instantiable
				public struct MyService: Instantiable {
				    public init(dependency: Dependency) {
				        self.dependency = dependency
				    }
				    @Received let dependency: Dependency

				    public static func mock(dependency: Dependency, alpha: Int = 1, bravo: Int = 2, charlie: Int = 3, delta: Int = 4, echo: Int = 5, foxtrot: Int = 6) -> MyService {
				        MyService(dependency: Dependency())
				    }
				}
				""",
			)
		}

		@Test
		func mockMethodNotPublicProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyService: Instantiable {
				    public init() {}

				    static func mock() -> MyService {
				        MyService()
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init() {}

				    static func mock() -> MyService {
				        MyService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type’s `mock()` method must be `public` or `open`.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add `public` modifier to `mock()` method"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func mockMethodWithWrongReturnTypeProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() -> String {
				        "not a MyService"
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() -> String {
				        "not a MyService"
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type’s `mock()` method must return `Self` or `MyService`.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Change `mock()` return type to `MyService`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Change `mock()` return type to `MyService`",
				],
				fixedSource: """
				@Instantiable
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() -> MyService {
				        "not a MyService"
				    }
				}
				""",
			)
		}

		@Test
		func expansion_producesReturnTypeDiagnostic_whenNestedTypeMockReturnsQualifiedTypeName() {
			// The macro sees only the decorated declaration, so it cannot tell that `Feature.Consumer` names this type.
			assertMacroExpansion(
				"""
				public enum Feature {
				    @Instantiable
				    public final class Consumer: Instantiable {
				        public init() {}

				        public static func mock() -> Feature.Consumer {
				            Consumer()
				        }
				    }
				}
				""",
				expandedSource: """
				public enum Feature {
				    public final class Consumer: Instantiable {
				        public init() {}

				        public static func mock() -> Feature.Consumer {
				            Consumer()
				        }
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type’s `mock()` method must return `Self` or `Consumer`.",
						line: 6,
						column: 9,
						fixIts: [
							FixItSpec(message: "Change `mock()` return type to `Consumer`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Change `mock()` return type to `Consumer`",
				],
				fixedSource: """
				public enum Feature {
				    @Instantiable
				    public final class Consumer: Instantiable {
				        public init() {}

				        public static func mock() -> Consumer {
				            Consumer()
				        }
				    }
				}
				""",
			)
		}

		@Test
		func expansion_producesReturnTypeDiagnostic_whenMockReturnsTypealiasOfDecoratedType() {
			// The macro compares names and does not resolve typealiases.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Consumer: Instantiable {
				    public typealias Mocked = Consumer

				    public init() {}

				    public static func mock() -> Mocked {
				        Consumer()
				    }
				}
				""",
				expandedSource: """
				public final class Consumer: Instantiable {
				    public typealias Mocked = Consumer

				    public init() {}

				    public static func mock() -> Mocked {
				        Consumer()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type’s `mock()` method must return `Self` or `Consumer`.",
						line: 7,
						column: 5,
						fixIts: [
							FixItSpec(message: "Change `mock()` return type to `Consumer`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Change `mock()` return type to `Consumer`",
				],
				fixedSource: """
				@Instantiable
				public final class Consumer: Instantiable {
				    public typealias Mocked = Consumer

				    public init() {}

				    public static func mock() -> Consumer {
				        Consumer()
				    }
				}
				""",
			)
		}

		@Test
		func mockMethodWithNoReturnTypeProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() {
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() {
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type’s `mock()` method must return `Self` or `MyService`.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Change `mock()` return type to `MyService`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Change `mock()` return type to `MyService`",
				],
				fixedSource: """
				@Instantiable
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() -> MyService {
				    }
				}
				""",
			)
		}

		@Test
		func mockMethodReturningSelfProducesNoDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() -> Self {
				        MyService()
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() -> Self {
				        MyService()
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func mockMethodReturningTypeNameProducesNoDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() -> MyService {
				        MyService()
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() -> MyService {
				        MyService()
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func mockMethodReturningFulfillingAdditionalTypeProducesDiagnosticOnConcreteType() {
			assertMacroExpansion(
				"""
				@Instantiable(fulfillingAdditionalTypes: [MyServiceProtocol.self])
				public struct MyService: MyServiceProtocol, Instantiable {
				    public init() {}

				    public static func mock() -> MyServiceProtocol {
				        MyService()
				    }
				}
				""",
				expandedSource: """
				public struct MyService: MyServiceProtocol, Instantiable {
				    public init() {}

				    public static func mock() -> MyServiceProtocol {
				        MyService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type\u{2019}s `mock()` method must return `Self` or `MyService`.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Change `mock()` return type to `MyService`"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_mockMethodReturningFulfillingAdditionalTypeProducesNoDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable(fulfillingAdditionalTypes: [MyServiceProtocol.self])
				extension MyService: Instantiable {
				    public static func instantiate() -> MyService { MyService() }

				    public static func mock() -> MyServiceProtocol {
				        MyService()
				    }
				}
				""",
				expandedSource: """
				extension MyService: Instantiable {
				    public static func instantiate() -> MyService { MyService() }

				    public static func mock() -> MyServiceProtocol {
				        MyService()
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_mockMethodNotPublicProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    static func mock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    static func mock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type’s `mock()` method must be `public` or `open`.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add `public` modifier to `mock()` method"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `public` modifier to `mock()` method",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
			)
		}

		@Test
		func extension_mockMethodWithWrongReturnTypeProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> String {
				        ""
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> String {
				        ""
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension’s `mock()` method must return `ExampleService` or a type listed in `fulfillingAdditionalTypes`.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Change `mock()` return type to `ExampleService`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Change `mock()` return type to `ExampleService`",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> ExampleService {
				        ""
				    }
				}
				""",
			)
		}

		@Test
		func extension_mockMethodWithNoReturnTypeProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() {
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() {
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension’s `mock()` method must return `ExampleService` or a type listed in `fulfillingAdditionalTypes`.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Change `mock()` return type to `ExampleService`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Change `mock()` return type to `ExampleService`",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> ExampleService {
				    }
				}
				""",
			)
		}

		@Test
		func extension_mockMethodReturningSelfProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> Self {
				        ExampleService()
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> Self {
				        ExampleService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension’s `mock()` method must return `ExampleService` or a type listed in `fulfillingAdditionalTypes`.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Change `mock()` return type to `ExampleService`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Change `mock()` return type to `ExampleService`",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
			)
		}

		@Test
		func extension_mockMethodReturningExtendedTypeProducesNoDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_duplicateMockMethodsWithSameReturnTypeProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Container: Instantiable {
				    public static func instantiate() -> Container<Bool> {
				        Container(false)
				    }

				    public static func mock() -> Container<Bool> {
				        Container(true)
				    }

				    public static func mock() -> Container<Bool> {
				        Container(false)
				    }
				}
				""",
				expandedSource: """
				extension Container: Instantiable {
				    public static func instantiate() -> Container<Bool> {
				        Container(false)
				    }

				    public static func mock() -> Container<Bool> {
				        Container(true)
				    }

				    public static func mock() -> Container<Bool> {
				        Container(false)
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have at most one `mock()` method. Remove this duplicate.",
						line: 11,
						column: 5,
						fixIts: [
							FixItSpec(message: "Remove duplicate `mock()` method"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_multipleMockMethodsWithDifferentReturnTypesProducesNoDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Container: Instantiable {
				    public static func instantiate() -> Container<Bool> {
				        Container(false)
				    }
				    public static func instantiate() -> Container<Int> {
				        Container(0)
				    }

				    public static func mock() -> Container<Bool> {
				        Container(true)
				    }
				    public static func mock() -> Container<Int> {
				        Container(1)
				    }
				}
				""",
				expandedSource: """
				extension Container: Instantiable {
				    public static func instantiate() -> Container<Bool> {
				        Container(false)
				    }
				    public static func instantiate() -> Container<Int> {
				        Container(0)
				    }

				    public static func mock() -> Container<Bool> {
				        Container(true)
				    }
				    public static func mock() -> Container<Int> {
				        Container(1)
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_mockMethodMissingDependencyProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate(dependency: Dependency) -> ExampleService { fatalError() }

				    public static func mock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate(dependency: Dependency) -> ExampleService { fatalError() }

				    public static func mock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This `mock()` method has no parameter for `dependency: Dependency`. A hand-written mock must take a parameter for each @Instantiated, @Received, or @Forwarded-decorated property; extra parameters with default values are allowed.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add `mock()` arguments for dependency: Dependency"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Add `mock()` arguments for dependency: Dependency",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate(dependency: Dependency) -> ExampleService { fatalError() }

				    public static func mock(dependency: Dependency) -> ExampleService {
				        ExampleService()
				    }
				}
				""",
			)
		}

		@Test
		func extension_mockMethodWithMatchingDependencyProducesNoDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate(dependency: Dependency) -> ExampleService { fatalError() }

				    public static func mock(dependency: Dependency) -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate(dependency: Dependency) -> ExampleService { fatalError() }

				    public static func mock(dependency: Dependency) -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_mockMethodReturningGenericSpecializationProducesNoDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Container: Instantiable {
				    public static func instantiate() -> Container<String> {
				        Container("")
				    }

				    public static func mock() -> Container<String> {
				        Container("mock")
				    }
				}
				""",
				expandedSource: """
				extension Container: Instantiable {
				    public static func instantiate() -> Container<String> {
				        Container("")
				    }

				    public static func mock() -> Container<String> {
				        Container("mock")
				    }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_mockMethodWithArrayWrappedReturnTypeProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> [ExampleService] {
				        []
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> [ExampleService] {
				        []
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension’s `mock()` method must return `ExampleService` or a type listed in `fulfillingAdditionalTypes`.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Change `mock()` return type to `ExampleService`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Change `mock()` return type to `ExampleService`",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> ExampleService {
				        []
				    }
				}
				""",
			)
		}

		@Test
		func extension_mockMethodReturningSelfGetsDiagnosticWhileTypeNameMockIsValid() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> Self {
				        ExampleService()
				    }

				    public static func mock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> Self {
				        ExampleService()
				    }

				    public static func mock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension’s `mock()` method must return `ExampleService` or a type listed in `fulfillingAdditionalTypes`.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Change `mock()` return type to `ExampleService`"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesDiagnostic_whenGenerateMockIsTrueAndUserDefinedMockExists() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true)
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public static func mock() -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: #"@Instantiable-decorated type with `generateMock: true` cannot also have a hand-written `mock()` method because the generated and hand-written methods would have ambiguous signatures. Rename your method and add `customMockName` to `@Instantiable`."#,
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: #"Rename method to `customMock` and add `customMockName: "customMock"` to `@Instantiable`"#),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func mockMethodWithArrayWrappedReturnTypeProducesDiagnostic() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() -> [MyService] {
				        []
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() -> [MyService] {
				        []
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type’s `mock()` method must return `Self` or `MyService`.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Change `mock()` return type to `MyService`"),
						],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Change `mock()` return type to `MyService`",
				],
				fixedSource: """
				@Instantiable
				public struct MyService: Instantiable {
				    public init() {}

				    public static func mock() -> MyService {
				        []
				    }
				}
				""",
			)
		}

		@Test
		func multipleMockMethodsProducesDiagnosticOnSecond() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct MyService: Instantiable {
				    public init(dependency: Dependency) {
				        self.dependency = dependency
				    }
				    @Received let dependency: Dependency

				    public static func mock(dependency: Dependency) -> MyService {
				        MyService(dependency: dependency)
				    }

				    public static func mock() -> MyService {
				        MyService(dependency: Dependency())
				    }
				}
				""",
				expandedSource: """
				public struct MyService: Instantiable {
				    public init(dependency: Dependency) {
				        self.dependency = dependency
				    }
				    let dependency: Dependency

				    public static func mock(dependency: Dependency) -> MyService {
				        MyService(dependency: dependency)
				    }

				    public static func mock() -> MyService {
				        MyService(dependency: Dependency())
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have at most one `mock()` method. Remove this duplicate.",
						line: 12,
						column: 5,
						fixIts: [
							FixItSpec(message: "Remove duplicate `mock()` method"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		// MARK: mockOnly Tests

		@Test
		func declaration_expandsWithoutIssueWhenMockOnlyIsTrue() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true)
				public struct ExternalService {
				    @Received let database: Database
				    public static func mock(database: Database) -> ExternalService { fatalError() }
				}
				""",
				expandedSource: """
				public struct ExternalService {
				    let database: Database
				    public static func mock(database: Database) -> ExternalService { fatalError() }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_expandsWithoutIssueOnExtensionWhenMockOnlyIsTrue() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true)
				extension ExternalService {
				    public static func mock() -> ExternalService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExternalService {
				    public static func mock() -> ExternalService { fatalError() }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_throwsErrorWhenMockOnlyAndGenerateMockBothTrue() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true, generateMock: true)
				public struct ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`mockOnly` and `generateMock` cannot both be `true`: a `mockOnly` declaration provides a hand-written mock. To generate a mock, set `generateMock: true` on the production `@Instantiable` declaration instead.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Remove `generateMock: true`"),
						],
					),
					DiagnosticSpec(
						message: "@Instantiable-decorated type with `generateMock: true` cannot also have a hand-written `mock()` method because the generated and hand-written methods would have ambiguous signatures. Rename your method and add `customMockName` to `@Instantiable`.",
						line: 3,
						column: 5,
						fixIts: [
							FixItSpec(message: "Rename method to `customMock` and add `customMockName: \"customMock\"` to `@Instantiable`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockOnly: true)
				public struct ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
			)
		}

		@Test
		func declaration_throwsErrorWhenMockOnlyAndIsRootBothTrue() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true, mockOnly: true)
				public struct ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`mockOnly` types cannot be marked `isRoot`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Remove `isRoot: true`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockOnly: true)
				public struct ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
			)
		}

		@Test
		func declaration_throwsErrorWhenMockOnlyTypeDeclarationMissingMockMethod() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true)
				public struct ExampleService {
				    @Received let database: Database
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    let database: Database
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable(mockOnly: true) requires a `public static func mock(…) -> ExampleService` method.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `public static func mock(…) -> ExampleService` method"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockOnly: true)
				public struct ExampleService {
				    @Received let database: Database
				public static func mock(database: Database) -> ExampleService {ExampleService(database: database)}


				}
				""",
			)
		}

		@Test
		func declaration_fixItPassesArgumentUnderUnescapedLabel_whenMockOnlyTypeMissingMockMethodHasKeywordLabeledProperty() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true)
				public struct ExampleService {
				    @Received let `default`: Database
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    let `default`: Database
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable(mockOnly: true) requires a `public static func mock(…) -> ExampleService` method.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `public static func mock(…) -> ExampleService` method"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockOnly: true)
				public struct ExampleService {
				    @Received let `default`: Database
				public static func mock(`default`: Database) -> ExampleService {ExampleService(default: `default`)}


				}
				""",
			)
		}

		@Test
		func extension_throwsErrorWhenMockOnlyExtensionMissingMockMethod() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true)
				extension ExternalService {
				}
				""",
				expandedSource: """
				extension ExternalService {
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable(mockOnly: true) requires a `public static func mock(…) -> ExternalService` method.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `public static func mock(…) -> ExternalService` method"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockOnly: true)
				extension ExternalService {
				public static func mock() -> ExternalService {ExternalService.instantiate()}


				}
				""",
			)
		}

		@Test
		func declaration_expandsWithoutIssueWhenMockOnlyAndConformsElsewhereBothTrue() {
			assertMacroExpansion(
				"""
				@Instantiable(conformsElsewhere: true, mockOnly: true)
				public struct ExternalService {
				    public static func mock() -> ExternalService { fatalError() }
				}
				""",
				expandedSource: """
				public struct ExternalService {
				    public static func mock() -> ExternalService { fatalError() }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_throwsErrorWhenMockOnlyMockMissingDependencyArguments() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true)
				public struct ExampleService {
				    @Received let database: Database
				    @Instantiated let cache: CacheService
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    let database: Database
				    let cache: CacheService
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This `mock()` method has no parameter for `database: Database`, `cache: CacheService`. A hand-written mock must take a parameter for each @Instantiated, @Received, or @Forwarded-decorated property; extra parameters with default values are allowed.",
						line: 5,
						column: 5,
						fixIts: [
							FixItSpec(message: "Add `mock()` arguments for database: Database, cache: CacheService"),
						],
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_throwsErrorWhenMockOnlyAndGenerateMockBothTrue() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true, generateMock: true)
				extension ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`mockOnly` and `generateMock` cannot both be `true`: a `mockOnly` declaration provides a hand-written mock. To generate a mock, set `generateMock: true` on the production `@Instantiable` declaration instead.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Remove `generateMock: true`"),
						],
					),
					DiagnosticSpec(
						message: "@Instantiable-decorated type with `generateMock: true` cannot also have a hand-written `mock()` method because the generated and hand-written methods would have ambiguous signatures. Rename your method and add `customMockName` to `@Instantiable`.",
						line: 3,
						column: 5,
						fixIts: [
							FixItSpec(message: "Rename method to `customMock` and add `customMockName: \"customMock\"` to `@Instantiable`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockOnly: true)
				extension ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_throwsErrorWhenMockOnlyAndIsRootBothTrue() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true, mockOnly: true)
				extension ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`mockOnly` types cannot be marked `isRoot`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Remove `isRoot: true`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockOnly: true)
				extension ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
			)
		}

		@Test
		func declaration_throwsErrorWhenMockOnlyArgumentIsNotBoolLiteral() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: someVariable)
				public struct ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `mockOnly` must be a Bool literal (`true` or `false`).",
						line: 1,
						column: 1,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_throwsErrorWhenMockOnlyWithCustomMockNameButMethodIsMissing() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true, customMockName: "preview")
				public struct ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable(mockOnly: true) requires a `public static func preview(…) -> ExampleService` method.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `public static func preview(…) -> ExampleService` method"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockOnly: true, customMockName: "preview")
				public struct ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				public static func preview() -> ExampleService {ExampleService()}


				}
				""",
			)
		}

		@Test
		func declaration_fixItRemovesIsRoot_whenIsRootIsFirstOfThreeArguments() {
			assertMacroExpansion(
				"""
				@Instantiable(isRoot: true, mockOnly: true, mockAttributes: "@MainActor")
				public struct ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`mockOnly` types cannot be marked `isRoot`.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Remove `isRoot: true`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockOnly: true, mockAttributes: "@MainActor")
				public struct ExampleService {
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
			)
		}

		@Test
		func declaration_fixItRemovesGenerateMock_whenGenerateMockIsLastArgument() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true, generateMock: true)
				public struct ExampleService: Instantiable {
				    public init() {}
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init() {}
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`mockOnly` and `generateMock` cannot both be `true`: a `mockOnly` declaration provides a hand-written mock. To generate a mock, set `generateMock: true` on the production `@Instantiable` declaration instead.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Remove `generateMock: true`"),
						],
					),
					DiagnosticSpec(
						message: "@Instantiable-decorated type with `generateMock: true` cannot also have a hand-written `mock()` method because the generated and hand-written methods would have ambiguous signatures. Rename your method and add `customMockName` to `@Instantiable`.",
						line: 4,
						column: 5,
						fixIts: [
							FixItSpec(message: "Rename method to `customMock` and add `customMockName: \"customMock\"` to `@Instantiable`"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockOnly: true)
				public struct ExampleService: Instantiable {
				    public init() {}
				    public static func mock() -> ExampleService { fatalError() }
				}
				""",
			)
		}

		@Test
		func declaration_fixItGeneratesMockStub_whenMockOnlyTypeDeclarationHasMultipleDependencies() {
			assertMacroExpansion(
				"""
				@Instantiable(mockOnly: true)
				public struct ExampleService {
				    @Received let database: Database
				    @Instantiated let cache: CacheService
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    let database: Database
				    let cache: CacheService
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable(mockOnly: true) requires a `public static func mock(…) -> ExampleService` method.",
						line: 1,
						column: 1,
						fixIts: [
							FixItSpec(message: "Add `public static func mock(…) -> ExampleService` method"),
						],
					),
				],
				macros: instantiableTestMacros,
				fixedSource: """
				@Instantiable(mockOnly: true)
				public struct ExampleService {
				    @Received let database: Database
				    @Instantiated let cache: CacheService
				public static func mock(database: Database, cache: CacheService) -> ExampleService {ExampleService(database: database, cache: cache)}


				}
				""",
			)
		}

		// MARK: Reserved Name Tests

		@Test
		func declaration_producesReservedNameDiagnostic_whenInstantiatedPropertyLabelBeginsWithReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(__safeDI_editor: Editor) {
				        self.__safeDI_editor = __safeDI_editor
				    }

				    @Instantiated let __safeDI_editor: Editor
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(__safeDI_editor: Editor) {
				        self.__safeDI_editor = __safeDI_editor
				    }

				    let __safeDI_editor: Editor
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_editor` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 7,
						column: 23,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedNameDiagnostic_whenReceivedPropertyLabelBeginsWithReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(__safeDI_editor: Draft?) {
				        self.__safeDI_editor = __safeDI_editor
				    }

				    @Received(onlyIfAvailable: true) let __safeDI_editor: Draft?
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(__safeDI_editor: Draft?) {
				        self.__safeDI_editor = __safeDI_editor
				    }

				    let __safeDI_editor: Draft?
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_editor` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 7,
						column: 42,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedNameDiagnostic_whenForwardedPropertyLabelBeginsWithReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(__safeDI_user: User) {
				        self.__safeDI_user = __safeDI_user
				    }

				    @Forwarded let __safeDI_user: User
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(__safeDI_user: User) {
				        self.__safeDI_user = __safeDI_user
				    }

				    let __safeDI_user: User

				    public typealias ForwardedProperties = User
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_user` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 7,
						column: 20,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedNameDiagnostic_whenAliasFulfillingDependencyNameBeginsWithReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(editorVendor: EditorVendor) {
				        self.editorVendor = editorVendor
				    }

				    @Received(fulfilledByDependencyNamed: "__safeDI_editor", ofType: Editor.self) let editorVendor: EditorVendor
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(editorVendor: EditorVendor) {
				        self.editorVendor = editorVendor
				    }

				    let editorVendor: EditorVendor
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_editor` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 7,
						column: 43,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesReservedNameDiagnostic_whenInstantiateParameterNameBeginsWithReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate(__safeDI_editor: Editor) -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate(__safeDI_editor: Editor) -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_editor` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 3,
						column: 36,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_fixit_namesParameterAfterItsArgumentLabel_whenInstantiateDependencyParameterIsNamedUnderscore() {
			// SafeDI names an `instantiate(…)` dependency by its parameter’s inner name, so `_` names none.
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(first _: First) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(first _: First) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This parameter of `instantiate(…)` has no default value, so it is a dependency, which SafeDI names by the parameter’s inner name. `_` names no dependency, so nothing can fulfill it. Name the parameter, or give it a default value.",
						line: 3,
						column: 42,
						severity: .error,
						fixIts: [FixItSpec(message: "Name the parameter `first`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Name the parameter `first`"],
				fixedSource: """
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(first: First) -> Service { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_fixit_namesEachParameterAfterItsArgumentLabel_whenTwoInstantiateDependencyParametersAreNamedUnderscore() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(first _: First, second _: Second) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(first _: First, second _: Second) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This parameter of `instantiate(…)` has no default value, so it is a dependency, which SafeDI names by the parameter’s inner name. `_` names no dependency, so nothing can fulfill it. Name the parameter, or give it a default value.",
						line: 3,
						column: 42,
						severity: .error,
						fixIts: [FixItSpec(message: "Name the parameter `first`")],
					),
					DiagnosticSpec(
						message: "This parameter of `instantiate(…)` has no default value, so it is a dependency, which SafeDI names by the parameter’s inner name. `_` names no dependency, so nothing can fulfill it. Name the parameter, or give it a default value.",
						line: 3,
						column: 59,
						severity: .error,
						fixIts: [FixItSpec(message: "Name the parameter `second`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Name the parameter `first`", "Name the parameter `second`"],
				fixedSource: """
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(first: First, second: Second) -> Service { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_fixit_namesOnlyTheUnnamedParameter_whenInstantiateDependencyParameterNamedUnderscoreIsBesideANamedOne() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(first _: First, second: Second) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(first _: First, second: Second) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This parameter of `instantiate(…)` has no default value, so it is a dependency, which SafeDI names by the parameter’s inner name. `_` names no dependency, so nothing can fulfill it. Name the parameter, or give it a default value.",
						line: 3,
						column: 42,
						severity: .error,
						fixIts: [FixItSpec(message: "Name the parameter `first`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Name the parameter `first`"],
				fixedSource: """
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(first: First, second: Second) -> Service { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_expandsWithoutIssue_whenDefaultValuedInstantiateParameterIsNamedUnderscore() {
			// A parameter with a default value is not a dependency, so it needs no name.
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(first _: First = First()) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(first _: First = First()) -> Service { fatalError() }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesDiagnosticWithoutFixit_whenInstantiateDependencyParameterHasNeitherArgumentLabelNorName() {
			// No argument label offers a name.
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(_: First, _ _: Second) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(_: First, _ _: Second) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This parameter of `instantiate(…)` has no default value, so it is a dependency, which SafeDI names by the parameter’s inner name. `_` names no dependency, so nothing can fulfill it. Name the parameter, or give it a default value.",
						line: 3,
						column: 36,
						severity: .error,
					),
					DiagnosticSpec(
						message: "This parameter of `instantiate(…)` has no default value, so it is a dependency, which SafeDI names by the parameter’s inner name. `_` names no dependency, so nothing can fulfill it. Name the parameter, or give it a default value.",
						line: 3,
						column: 48,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesDiagnosticWithoutFixit_whenNamingParameterAfterItsArgumentLabelWouldRedeclareAnotherParameter() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(first _: First, first: Second) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(first _: First, first: Second) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This parameter of `instantiate(…)` has no default value, so it is a dependency, which SafeDI names by the parameter’s inner name. `_` names no dependency, so nothing can fulfill it. Name the parameter, or give it a default value.",
						line: 3,
						column: 42,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesDiagnosticsWithoutFixits_whenTwoParametersNamedUnderscoreShareAnArgumentLabel() {
			// Naming either parameter after the label would leave the other no name to take.
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(first _: First, first _: Second) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(first _: First, first _: Second) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This parameter of `instantiate(…)` has no default value, so it is a dependency, which SafeDI names by the parameter’s inner name. `_` names no dependency, so nothing can fulfill it. Name the parameter, or give it a default value.",
						line: 3,
						column: 42,
						severity: .error,
					),
					DiagnosticSpec(
						message: "This parameter of `instantiate(…)` has no default value, so it is a dependency, which SafeDI names by the parameter’s inner name. `_` names no dependency, so nothing can fulfill it. Name the parameter, or give it a default value.",
						line: 3,
						column: 58,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesDiagnosticWithoutFixit_whenParameterNamedUnderscoreHasReservedArgumentLabel() {
			// A dependency named after the label would be rejected as reserved.
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(safeDIOverrides _: First) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(safeDIOverrides _: First) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This parameter of `instantiate(…)` has no default value, so it is a dependency, which SafeDI names by the parameter’s inner name. `_` names no dependency, so nothing can fulfill it. Name the parameter, or give it a default value.",
						line: 3,
						column: 52,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_fixit_namesParameterAfterKeywordArgumentLabel_whenInstantiateDependencyParameterIsNamedUnderscore() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(default _: First) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(default _: First) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This parameter of `instantiate(…)` has no default value, so it is a dependency, which SafeDI names by the parameter’s inner name. `_` names no dependency, so nothing can fulfill it. Name the parameter, or give it a default value.",
						line: 3,
						column: 44,
						severity: .error,
						fixIts: [FixItSpec(message: "Name the parameter `default`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Name the parameter `default`"],
				fixedSource: """
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(default: First) -> Service { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_fixit_keepsParameterType_whenInstantiateDependencyParameterNamedUnderscoreHasClosureType() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(first _: @escaping () -> Void) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(first _: @escaping () -> Void) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This parameter of `instantiate(…)` has no default value, so it is a dependency, which SafeDI names by the parameter’s inner name. `_` names no dependency, so nothing can fulfill it. Name the parameter, or give it a default value.",
						line: 3,
						column: 42,
						severity: .error,
						fixIts: [FixItSpec(message: "Name the parameter `first`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Name the parameter `first`"],
				fixedSource: """
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(first: @escaping () -> Void) -> Service { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_fixit_keepsParameterType_whenInstantiateDependencyParameterNamedUnderscoreHasSendableClosureType() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(first _: @escaping @Sendable () -> Void) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(first _: @escaping @Sendable () -> Void) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This parameter of `instantiate(…)` has no default value, so it is a dependency, which SafeDI names by the parameter’s inner name. `_` names no dependency, so nothing can fulfill it. Name the parameter, or give it a default value.",
						line: 3,
						column: 42,
						severity: .error,
						fixIts: [FixItSpec(message: "Name the parameter `first`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Name the parameter `first`"],
				fixedSource: """
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(first: @escaping @Sendable () -> Void) -> Service { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_fixit_keepsParameterType_whenInstantiateDependencyParameterNamedUnderscoreHasOptionalType() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(first _: First?) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(first _: First?) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This parameter of `instantiate(…)` has no default value, so it is a dependency, which SafeDI names by the parameter’s inner name. `_` names no dependency, so nothing can fulfill it. Name the parameter, or give it a default value.",
						line: 3,
						column: 42,
						severity: .error,
						fixIts: [FixItSpec(message: "Name the parameter `first`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Name the parameter `first`"],
				fixedSource: """
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(first: First?) -> Service { fatalError() }
				}
				""",
			)
		}

		@Test
		func extension_fixit_keepsParameterType_whenInstantiateDependencyParameterNamedUnderscoreHasWrapperType() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(first _: Instantiator<First>) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(first _: Instantiator<First>) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This parameter of `instantiate(…)` has no default value, so it is a dependency, which SafeDI names by the parameter’s inner name. `_` names no dependency, so nothing can fulfill it. Name the parameter, or give it a default value.",
						line: 3,
						column: 42,
						severity: .error,
						fixIts: [FixItSpec(message: "Name the parameter `first`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Name the parameter `first`"],
				fixedSource: """
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(first: Instantiator<First>) -> Service { fatalError() }
				}
				""",
			)
		}

		@Test
		func declaration_producesDiagnostic_whenTwoPropertyNamesAreEncodedDifferently() {
			// Swift compares names byte for byte, so these are two properties; `String`, which SafeDI matches names by, calls them equal.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Service: Instantiable {
				    @Instantiated let caf\u{E9}: First
				    @Instantiated let cafe\u{301}: Second
				    public init(caf\u{E9}: First, cafe\u{301}: Second) {}
				}
				""",
				expandedSource: """
				public final class Service: Instantiable {
				    let caf\u{E9}: First
				    let cafe\u{301}: Second
				    public init(caf\u{E9}: First, cafe\u{301}: Second) {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The names `caf\u{E9}` (U+0063 U+0061 U+0066 U+00E9) and `cafe\u{301}` (U+0063 U+0061 U+0066 U+0065 U+0301) look the same but are encoded differently, so SafeDI cannot tell them apart. Rename one of them.",
						line: 4,
						column: 23,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesDiagnostic_whenPropertyNameIsEncodedDifferentlyFromForwardedPropertyName() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Service: Instantiable {
				    @Forwarded let caf\u{E9}: First
				    @Received let cafe\u{301}: Second
				    public init(caf\u{E9}: First, cafe\u{301}: Second) {}
				}
				""",
				expandedSource: """
				public final class Service: Instantiable {
				    let caf\u{E9}: First
				    let cafe\u{301}: Second
				    public init(caf\u{E9}: First, cafe\u{301}: Second) {}

				    public typealias ForwardedProperties = First
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The names `caf\u{E9}` (U+0063 U+0061 U+0066 U+00E9) and `cafe\u{301}` (U+0063 U+0061 U+0066 U+0065 U+0301) look the same but are encoded differently, so SafeDI cannot tell them apart. Rename one of them.",
						line: 4,
						column: 19,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesDiagnosticAtEachLaterSpelling_whenThreeNamesAreEncodedDifferently() {
			// Each later spelling is reported once, at its first occurrence, beside the first spelling it cannot be told apart from.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Service: Instantiable {
				    @Instantiated let \u{C5}: First
				    @Instantiated let \u{212B}: Second
				    @Instantiated let A\u{30A}: Third
				    public init(\u{C5}: First, \u{212B}: Second, A\u{30A}: Third) {}
				}
				""",
				expandedSource: """
				public final class Service: Instantiable {
				    let \u{C5}: First
				    let \u{212B}: Second
				    let A\u{30A}: Third
				    public init(\u{C5}: First, \u{212B}: Second, A\u{30A}: Third) {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The names `\u{C5}` (U+00C5) and `\u{212B}` (U+212B) look the same but are encoded differently, so SafeDI cannot tell them apart. Rename one of them.",
						line: 4,
						column: 23,
						severity: .error,
					),
					DiagnosticSpec(
						message: "The names `\u{C5}` (U+00C5) and `A\u{30A}` (U+0041 U+030A) look the same but are encoded differently, so SafeDI cannot tell them apart. Rename one of them.",
						line: 5,
						column: 23,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenTwoPropertyNamesAreByteIdentical() {
			// The compiler reports the redeclaration of a name spelled the same way twice in one clause.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Service: Instantiable {
				    @Instantiated let caf\u{E9}: First
				    @Instantiated let caf\u{E9}: Second
				    public init(caf\u{E9}: First, caf\u{E9}: Second) {}
				}
				""",
				expandedSource: """
				public final class Service: Instantiable {
				    let caf\u{E9}: First
				    let caf\u{E9}: Second
				    public init(caf\u{E9}: First, caf\u{E9}: Second) {}
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesDiagnostic_whenInitializerParameterNameIsEncodedDifferentlyFromThePropertyItFulfills() {
			// SafeDI matches the parameter to the property by name, and generated code passes the property under the parameter’s spelling.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Service: Instantiable {
				    @Received let caf\u{E9}: First
				    public init(cafe\u{301}: First) {}
				}
				""",
				expandedSource: """
				public final class Service: Instantiable {
				    let caf\u{E9}: First
				    public init(cafe\u{301}: First) {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The names `caf\u{E9}` (U+0063 U+0061 U+0066 U+00E9) and `cafe\u{301}` (U+0063 U+0061 U+0066 U+0065 U+0301) look the same but are encoded differently, so SafeDI cannot tell them apart. Rename one of them.",
						line: 4,
						column: 17,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesDiagnostic_whenDefaultValuedInitializerParameterNameIsEncodedDifferentlyFromPropertyName() {
			// A generated mock offers a default-valued parameter as an override, which SafeDI matches to the property by name.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Service: Instantiable {
				    @Instantiated let caf\u{E9}: First
				    public init(caf\u{E9}: First, cafe\u{301}: Second = Second()) {}
				}
				""",
				expandedSource: """
				public final class Service: Instantiable {
				    let caf\u{E9}: First
				    public init(caf\u{E9}: First, cafe\u{301}: Second = Second()) {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The names `caf\u{E9}` (U+0063 U+0061 U+0066 U+00E9) and `cafe\u{301}` (U+0063 U+0061 U+0066 U+0065 U+0301) look the same but are encoded differently, so SafeDI cannot tell them apart. Rename one of them.",
						line: 4,
						column: 31,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesDiagnostic_whenMockParameterNameIsEncodedDifferentlyFromPropertyName() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Service: Instantiable {
				    @Received let caf\u{E9}: First
				    public init(caf\u{E9}: First) {}
				    public static func mock(cafe\u{301}: First) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				public final class Service: Instantiable {
				    let caf\u{E9}: First
				    public init(caf\u{E9}: First) {}
				    public static func mock(cafe\u{301}: First) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The names `caf\u{E9}` (U+0063 U+0061 U+0066 U+00E9) and `cafe\u{301}` (U+0063 U+0061 U+0066 U+0065 U+0301) look the same but are encoded differently, so SafeDI cannot tell them apart. Rename one of them.",
						line: 5,
						column: 29,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesDiagnostic_whenAliasFulfillingNameIsEncodedDifferentlyFromPropertyName() {
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Service: Instantiable {
				    @Instantiated let caf\u{E9}: Dependency
				    @Received(fulfilledByDependencyNamed: "cafe\u{301}", ofType: Dependency.self) let renamed: Dependency
				    public init(caf\u{E9}: Dependency, renamed: Dependency) {}
				}
				""",
				expandedSource: """
				public final class Service: Instantiable {
				    let caf\u{E9}: Dependency
				    let renamed: Dependency
				    public init(caf\u{E9}: Dependency, renamed: Dependency) {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The names `caf\u{E9}` (U+0063 U+0061 U+0066 U+00E9) and `cafe\u{301}` (U+0063 U+0061 U+0066 U+0065 U+0301) look the same but are encoded differently, so SafeDI cannot tell them apart. Rename one of them.",
						line: 4,
						column: 43,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesOnlyEncodingDiagnostic_whenSameTypedPropertiesWithDifferentDecoratorsAreEncodedDifferently() {
			// SafeDI matches both parameters to the first property, but the initializer error that would follow is not reported beside the one that explains it.
			assertMacroExpansion(
				"""
				@Instantiable
				public final class Service: Instantiable {
				    @Instantiated let caf\u{E9}: Dependency
				    @Received let cafe\u{301}: Dependency
				    public init(caf\u{E9}: Dependency, cafe\u{301}: Dependency) {}
				}
				""",
				expandedSource: """
				public final class Service: Instantiable {
				    let caf\u{E9}: Dependency
				    let cafe\u{301}: Dependency
				    public init(caf\u{E9}: Dependency, cafe\u{301}: Dependency) {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The names `caf\u{E9}` (U+0063 U+0061 U+0066 U+00E9) and `cafe\u{301}` (U+0063 U+0061 U+0066 U+0065 U+0301) look the same but are encoded differently, so SafeDI cannot tell them apart. Rename one of them.",
						line: 4,
						column: 19,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesDiagnostic_whenTwoInstantiateDependencyParameterNamesAreEncodedDifferently() {
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(caf\u{E9}: First, cafe\u{301}: Second) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(caf\u{E9}: First, cafe\u{301}: Second) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The names `caf\u{E9}` (U+0063 U+0061 U+0066 U+00E9) and `cafe\u{301}` (U+0063 U+0061 U+0066 U+0065 U+0301) look the same but are encoded differently, so SafeDI cannot tell them apart. Rename one of them.",
						line: 3,
						column: 50,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_producesDiagnostic_whenDefaultValuedParameterNameIsEncodedDifferentlyFromDependencyParameterName() {
			// A generated mock offers a default-valued parameter as an override, which SafeDI matches to the dependency by name.
			assertMacroExpansion(
				"""
				@Instantiable
				extension Service: Instantiable {
				    public static func instantiate(caf\u{E9}: First, cafe\u{301}: Second = Second()) -> Service { fatalError() }
				}
				""",
				expandedSource: """
				extension Service: Instantiable {
				    public static func instantiate(caf\u{E9}: First, cafe\u{301}: Second = Second()) -> Service { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The names `caf\u{E9}` (U+0063 U+0061 U+0066 U+00E9) and `cafe\u{301}` (U+0063 U+0061 U+0066 U+0065 U+0301) look the same but are encoded differently, so SafeDI cannot tell them apart. Rename one of them.",
						line: 3,
						column: 50,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func extension_expandsWithoutIssue_whenOnlyInstantiateParameterArgumentLabelBeginsWithReservedPrefix() {
			// The dependency is named by the parameter's inner name. Its argument label only labels the
			// argument in the call SafeDI generates, which binds nothing.
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate(__safeDI_editor editor: Editor) -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate(__safeDI_editor editor: Editor) -> ExampleService { fatalError() }
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_fixit_renamesArgumentLabelAndKeepsParameterName_whenInitializerDefaultParameterLabelBeginsWithReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(__safeDI_retryCount: Int = 3) {
				        self.retryCount = __safeDI_retryCount
				    }

				    let retryCount: Int
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(__safeDI_retryCount: Int = 3) {
				        self.retryCount = __safeDI_retryCount
				    }

				    let retryCount: Int
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_retryCount` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 3,
						column: 17,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `__safeDI_retryCount` to `retryCount`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Rename `__safeDI_retryCount` to `retryCount`"],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(retryCount __safeDI_retryCount: Int = 3) {
				        self.retryCount = __safeDI_retryCount
				    }

				    let retryCount: Int
				}
				""",
			)
		}

		@Test
		func declaration_fixit_removesRepeatedParameterName_whenInitializerDefaultParameterNameMatchesArgumentLabelWithoutReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(__safeDI_retryCount retryCount: Int = 3) {
				        self.retryCount = retryCount
				    }

				    let retryCount: Int
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(__safeDI_retryCount retryCount: Int = 3) {
				        self.retryCount = retryCount
				    }

				    let retryCount: Int
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_retryCount` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 3,
						column: 17,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `__safeDI_retryCount` to `retryCount`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Rename `__safeDI_retryCount` to `retryCount`"],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(retryCount: Int = 3) {
				        self.retryCount = retryCount
				    }

				    let retryCount: Int
				}
				""",
			)
		}

		@Test
		func declaration_fixit_renamesOnlyArgumentLabel_whenInitializerDefaultParameterHasAnotherParameterName() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(__safeDI_retryCount count: Int = 3) {
				        self.retryCount = count
				    }

				    let retryCount: Int
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(__safeDI_retryCount count: Int = 3) {
				        self.retryCount = count
				    }

				    let retryCount: Int
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_retryCount` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 3,
						column: 17,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `__safeDI_retryCount` to `retryCount`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Rename `__safeDI_retryCount` to `retryCount`"],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(retryCount count: Int = 3) {
				        self.retryCount = count
				    }

				    let retryCount: Int
				}
				""",
			)
		}

		@Test
		func declaration_fixit_renamesArgumentLabel_whenCustomMockDefaultParameterLabelBeginsWithReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct ExampleService: Instantiable {
				    public init() {}
				    public static func customMock(__safeDI_delay: Double = 0) -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init() {}
				    public static func customMock(__safeDI_delay: Double = 0) -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_delay` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 4,
						column: 35,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `__safeDI_delay` to `delay`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Rename `__safeDI_delay` to `delay`"],
				fixedSource: """
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct ExampleService: Instantiable {
				    public init() {}
				    public static func customMock(delay __safeDI_delay: Double = 0) -> ExampleService {
				        ExampleService()
				    }
				}
				""",
			)
		}

		@Test
		func extension_fixit_renamesArgumentLabel_whenCustomMockDefaultParameterLabelBeginsWithReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				    public static func customMock(__safeDI_delay: Double = 0) -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				    public static func customMock(__safeDI_delay: Double = 0) -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_delay` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 4,
						column: 35,
						severity: .error,
						fixIts: [FixItSpec(message: "Rename `__safeDI_delay` to `delay`")],
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: ["Rename `__safeDI_delay` to `delay`"],
				fixedSource: """
				@Instantiable(generateMock: true, customMockName: "customMock")
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				    public static func customMock(delay __safeDI_delay: Double = 0) -> ExampleService { fatalError() }
				}
				""",
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenLabelContainsReservedPrefixAfterItsStart() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(my__safeDI_editor: Editor, my__safeDI_retryCount: Int = 3) {
				        self.my__safeDI_editor = my__safeDI_editor
				    }

				    @Instantiated let my__safeDI_editor: Editor
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(my__safeDI_editor: Editor, my__safeDI_retryCount: Int = 3) {
				        self.my__safeDI_editor = my__safeDI_editor
				    }

				    let my__safeDI_editor: Editor
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenPropertiesAndInitializerParametersAreEscapedDifferently() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(default: Editor, editor: Editor) {
				        self.default = `default`
				        self.editor = editor
				    }

				    @Instantiated let `default`: Editor
				    @Instantiated let `editor`: Editor
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(default: Editor, editor: Editor) {
				        self.default = `default`
				        self.editor = editor
				    }

				    let `default`: Editor
				    let `editor`: Editor
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenLabelBeginsWithSingleUnderscoreSafeDI() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(_safeDI_editor: Editor, _safeDIUser: User, _safeDI_retryCount: Int = 3) {
				        self._safeDI_editor = _safeDI_editor
				        self._safeDIUser = _safeDIUser
				    }

				    @Instantiated let _safeDI_editor: Editor
				    @Received let _safeDIUser: User
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(_safeDI_editor: Editor, _safeDIUser: User, _safeDI_retryCount: Int = 3) {
				        self._safeDI_editor = _safeDI_editor
				        self._safeDIUser = _safeDIUser
				    }

				    let _safeDI_editor: Editor
				    let _safeDIUser: User
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenUnlabeledDefaultParameterNameBeginsWithReservedPrefix() {
			// An unlabeled default is elided from the call SafeDI generates, so its name binds nothing.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(_ __safeDI_retryCount: Int = 3) {
				        self.retryCount = __safeDI_retryCount
				    }

				    let retryCount: Int
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(_ __safeDI_retryCount: Int = 3) {
				        self.retryCount = __safeDI_retryCount
				    }

				    let retryCount: Int
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedNameDiagnosticWithoutFixit_whenLabelIsOnlyReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(__safeDI_: Int = 3) {}
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(__safeDI_: Int = 3) {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 3,
						column: 17,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedNameDiagnosticWithoutFixit_whenLabelWithoutReservedPrefixIsKeyword() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(__safeDI_class: Int = 3) {}
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(__safeDI_class: Int = 3) {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_class` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 3,
						column: 17,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedNameDiagnosticWithoutFixit_whenLabelWithoutReservedPrefixBeginsWithDigit() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(__safeDI_1stRetryCount: Int = 3) {}
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(__safeDI_1stRetryCount: Int = 3) {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_1stRetryCount` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 3,
						column: 17,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedNameDiagnosticWithoutFixit_whenLabelWithoutReservedPrefixBeginsWithReservedPrefix() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(__safeDI___safeDI_retryCount: Int = 3) {}
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(__safeDI___safeDI_retryCount: Int = 3) {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI___safeDI_retryCount` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 3,
						column: 17,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedNameDiagnosticWithoutFixit_whenLabelWithoutReservedPrefixIsAnotherParameterLabel() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(retryCount: Int = 3, __safeDI_retryCount: Int = 3) {}
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(retryCount: Int = 3, __safeDI_retryCount: Int = 3) {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_retryCount` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 3,
						column: 38,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedNameDiagnosticWithoutFixit_whenLabelWithoutReservedPrefixIsAnotherParameterLabelInBackticks() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(`retryCount`: Int = 3, __safeDI_retryCount: Int = 3) {}
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(`retryCount`: Int = 3, __safeDI_retryCount: Int = 3) {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_retryCount` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 3,
						column: 40,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedNameDiagnosticWithoutFixit_whenLabelWithoutReservedPrefixIsDependencyLabel() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(retryCount: Int, __safeDI_retryCount: Int = 3) {
				        self.retryCount = retryCount
				    }

				    @Received let retryCount: Int
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(retryCount: Int, __safeDI_retryCount: Int = 3) {
				        self.retryCount = retryCount
				    }

				    let retryCount: Int
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_retryCount` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 3,
						column: 34,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test(arguments: ReservedExactName.all)
		func declaration_producesReservedNameDiagnostic_whenInstantiatedPropertyLabelIsReservedExactly(_ reserved: ReservedExactName) {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(\(reserved.name): Editor) {
				        self.\(reserved.name) = \(reserved.name)
				    }

				    @Instantiated let \(reserved.name): Editor
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(\(reserved.name): Editor) {
				        self.\(reserved.name) = \(reserved.name)
				    }

				    let \(reserved.name): Editor
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: reserved.message,
						line: 7,
						column: 23,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test(arguments: ReservedExactName.all)
		func declaration_producesReservedNameDiagnostic_whenReceivedPropertyLabelIsReservedExactly(_ reserved: ReservedExactName) {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(\(reserved.name): Editor) {
				        self.\(reserved.name) = \(reserved.name)
				    }

				    @Received let \(reserved.name): Editor
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(\(reserved.name): Editor) {
				        self.\(reserved.name) = \(reserved.name)
				    }

				    let \(reserved.name): Editor
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: reserved.message,
						line: 7,
						column: 19,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test(arguments: ReservedExactName.all)
		func declaration_producesReservedNameDiagnostic_whenForwardedPropertyLabelIsReservedExactly(_ reserved: ReservedExactName) {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(\(reserved.name): User) {
				        self.\(reserved.name) = \(reserved.name)
				    }

				    @Forwarded let \(reserved.name): User
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(\(reserved.name): User) {
				        self.\(reserved.name) = \(reserved.name)
				    }

				    let \(reserved.name): User

				    public typealias ForwardedProperties = User
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: reserved.message,
						line: 7,
						column: 20,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test(arguments: ReservedExactName.all)
		func declaration_producesReservedNameDiagnostic_whenAliasFulfillingDependencyNameIsReservedExactly(_ reserved: ReservedExactName) {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(editorVendor: EditorVendor) {
				        self.editorVendor = editorVendor
				    }

				    @Received(fulfilledByDependencyNamed: "\(reserved.name)", ofType: Editor.self) let editorVendor: EditorVendor
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(editorVendor: EditorVendor) {
				        self.editorVendor = editorVendor
				    }

				    let editorVendor: EditorVendor
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: reserved.message,
						line: 7,
						column: 43,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test(arguments: ReservedExactName.all)
		func extension_producesReservedNameDiagnostic_whenInstantiateParameterNameIsReservedExactly(_ reserved: ReservedExactName) {
			assertMacroExpansion(
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate(\(reserved.name): Editor) -> ExampleService { fatalError() }
				}
				""",
				expandedSource: """
				extension ExampleService: Instantiable {
				    public static func instantiate(\(reserved.name): Editor) -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: reserved.message,
						line: 3,
						column: 36,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test(arguments: ReservedExactName.all)
		func declaration_producesReservedNameDiagnosticWithoutFixit_whenInitializerDefaultParameterLabelIsReservedExactly(_ reserved: ReservedExactName) {
			// An exactly reserved label has no evident replacement, so no rename is offered.
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(\(reserved.name): Int = 3) {}
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(\(reserved.name): Int = 3) {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: reserved.message,
						line: 3,
						column: 17,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test(arguments: ReservedExactName.all)
		func declaration_producesReservedNameDiagnosticWithoutFixit_whenCustomMockDefaultParameterLabelIsReservedExactly(_ reserved: ReservedExactName) {
			assertMacroExpansion(
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct ExampleService: Instantiable {
				    public init() {}
				    public static func customMock(\(reserved.name): Double = 0) -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init() {}
				    public static func customMock(\(reserved.name): Double = 0) -> ExampleService {
				        ExampleService()
				    }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: reserved.message,
						line: 4,
						column: 35,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_expandsWithoutIssue_whenLabelOnlyContainsReservedExactName() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(safeDIOverridesProvider: Editor, mySafeDIBuilder: Editor, SafeDIOverrides: Editor, instantiator: Editor, Instantiators: Editor, safeDIBuilderCount: Int = 3) {
				        self.safeDIOverridesProvider = safeDIOverridesProvider
				        self.mySafeDIBuilder = mySafeDIBuilder
				        self.SafeDIOverrides = SafeDIOverrides
				        self.instantiator = instantiator
				        self.Instantiators = Instantiators
				    }

				    @Instantiated let safeDIOverridesProvider: Editor
				    @Instantiated let mySafeDIBuilder: Editor
				    @Instantiated let SafeDIOverrides: Editor
				    @Instantiated let instantiator: Editor
				    @Instantiated let Instantiators: Editor
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(safeDIOverridesProvider: Editor, mySafeDIBuilder: Editor, SafeDIOverrides: Editor, instantiator: Editor, Instantiators: Editor, safeDIBuilderCount: Int = 3) {
				        self.safeDIOverridesProvider = safeDIOverridesProvider
				        self.mySafeDIBuilder = mySafeDIBuilder
				        self.SafeDIOverrides = SafeDIOverrides
				        self.instantiator = instantiator
				        self.Instantiators = Instantiators
				    }

				    let safeDIOverridesProvider: Editor
				    let mySafeDIBuilder: Editor
				    let SafeDIOverrides: Editor
				    let instantiator: Editor
				    let Instantiators: Editor
				}
				""",
				macros: instantiableTestMacros,
			)
		}

		@Test
		func declaration_producesReservedNameDiagnosticWithoutFixit_whenLabelWithoutReservedPrefixIsReservedExactly() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(__safeDI_safeDIOverrides: Int = 3) {}
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    public init(__safeDI_safeDIOverrides: Int = 3) {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`__safeDI_safeDIOverrides` begins with `__safeDI_`, a prefix SafeDI reserves for names in the code it generates. Rename it so that it does not begin with `__safeDI_`.",
						line: 3,
						column: 17,
						severity: .error,
					),
				],
				macros: instantiableTestMacros,
			)
		}

		// MARK: ReservedExactName

		/// A name SafeDI reserves exactly, with the diagnostic a name spelled the same gets.
		struct ReservedExactName: CustomTestStringConvertible, Sendable {
			let name: String
			let message: String

			var testDescription: String {
				name
			}

			static let all = [
				ReservedExactName(
					name: "safeDIOverrides",
					message: "`safeDIOverrides` is reserved: it is the name of the parameter through which a generated `mock()` takes its overrides, and a name spelled the same would collide with it in generated code. Rename it.",
				),
				ReservedExactName(
					name: "safeDIBuilder",
					message: "`safeDIBuilder` is reserved: it is the name of the property of a generated `SafeDIMockConfiguration` that overrides how its type is built, and a name spelled the same would collide with it in generated code. Rename it.",
				),
			] + [
				"Instantiator",
				"SendableInstantiator",
				"ErasedInstantiator",
				"SendableErasedInstantiator",
				"LazilyInstantiated",
				"SendableLazilyInstantiated",
			].map {
				ReservedExactName(
					name: $0,
					message: "`\($0)` is reserved: generated code constructs the `\($0)` type by that name, and a name spelled the same would hide the type from it. Rename it.",
				)
			}
		}
	}
#endif
