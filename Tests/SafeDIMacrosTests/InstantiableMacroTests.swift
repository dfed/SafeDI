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
import SwiftSyntaxMacrosTestSupport
import Testing

import SafeDICore

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
		func extension_expandsWithoutIssueOnTypeDeclarationWhenInstantiableConformanceMissingAndConformsElsewhereIsTrue() {
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
				macros: instantiableTestMacros
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
				macros: instantiableTestMacros
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
				@Instantiable
				public protocol ExampleService {}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable must decorate an extension on a type or a class, struct, or actor declaration",
						line: 1,
						column: 1,
						severity: .error
					),
				],
				macros: instantiableTestMacros
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
				@Instantiable
				public enum ExampleService: Instantiable {}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable must decorate an extension on a type or a class, struct, or actor declaration",
						line: 1,
						column: 1,
						severity: .error
					),
				],
				macros: instantiableTestMacros
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
				@Instantiable(fulfillingAdditionalTypes: [AnyObject?.self])
				public final class ExampleService: Instantiable {}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `fulfillingAdditionalTypes` must not include optionals",
						line: 1,
						column: 1,
						severity: .error
					),
				],
				macros: instantiableTestMacros
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
				@Instantiable(fulfillingAdditionalTypes: fulfillingAdditionalTypes)
				public final class ExampleService: Instantiable {}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `fulfillingAdditionalTypes` must be an inlined array",
						line: 2,
						column: 1,
						severity: .error
					),
				],
				macros: instantiableTestMacros
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
				@Instantiable(fulfillingAdditionalTypes: { [AnyObject.self] }())
				public final class ExampleService: Instantiable {}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `fulfillingAdditionalTypes` must be an inlined array",
						line: 1,
						column: 1,
						severity: .error
					),
				],
				macros: instantiableTestMacros
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
				macros: instantiableTestMacros
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
				@Instantiable(isRoot: true)
				public final class Foo: Instantiable {
				    public init(dependency: Dependency) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received private let dependency: Dependency 
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: """
							Types decorated with `@Instantiable(isRoot: true)` must only have dependencies that are all `@Instantiated` or `@Received(fulfilledByDependencyNamed:ofType:)`, where the latter properties can be fulfilled by `@Instantiated` or `@Received(fulfilledByDependencyNamed:ofType:)` properties declared on this type.

							The following dependencies were found on Foo that violated this contract:
							dependency: Dependency
							""",
						line: 1,
						column: 1,
						severity: .error
					),
				],
				macros: instantiableTestMacros
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
				@Instantiable(isRoot: true)
				public final class Foo: Instantiable {
				    public init(dependency: Dependency) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Forwarded private let dependency: Dependency 
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: """
							Types decorated with `@Instantiable(isRoot: true)` must only have dependencies that are all `@Instantiated` or `@Received(fulfilledByDependencyNamed:ofType:)`, where the latter properties can be fulfilled by `@Instantiated` or `@Received(fulfilledByDependencyNamed:ofType:)` properties declared on this type.

							The following dependencies were found on Foo that violated this contract:
							dependency: Dependency
							""",
						line: 1,
						column: 1,
						severity: .error
					),
				],
				macros: instantiableTestMacros
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
				@Instantiable(fulfillingAdditionalTypes: fulfillingAdditionalTypes)
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `fulfillingAdditionalTypes` must be an inlined array",
						line: 2,
						column: 1,
						severity: .error
					),
				],
				macros: instantiableTestMacros
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
				@Instantiable(fulfillingAdditionalTypes: { [AnyObject.self] }())
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `fulfillingAdditionalTypes` must be an inlined array",
						line: 1,
						column: 1,
						severity: .error
					),
				],
				macros: instantiableTestMacros
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
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				    public static func instantiate(user: User) -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension must have a single `instantiate(…)` method that returns `ExampleService`",
						line: 1,
						column: 1,
						severity: .error
					),
				],
				macros: instantiableTestMacros
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
				macros: instantiableTestMacros
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
				@Instantiable(isRoot: true)
				extension Foo: Instantiable {
				    public static func instantiate(bar: Bar) -> Foo { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: """
							Types decorated with `@Instantiable(isRoot: true)` must only have dependencies that are all `@Instantiated` or `@Received(fulfilledByDependencyNamed:ofType:)`, where the latter properties can be fulfilled by `@Instantiated` or `@Received(fulfilledByDependencyNamed:ofType:)` properties declared on this type.

							The following dependencies were found on Foo that violated this contract:
							bar: Bar
							""",
						line: 1,
						column: 1,
						severity: .error
					),
				],
				macros: instantiableTestMacros
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
				public init() {}

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
						]
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
				"""
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
				public init() {}

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
						]
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
				"""
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
				public init() {}

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
						]
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
				"""
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
				macros: instantiableTestMacros
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
				public init() {}

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
						]
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
				"""
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
				public init() {}

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
						]
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
				"""
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
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

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
						]
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
				"""
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
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}
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
						]
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
				"""
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
				macros: instantiableTestMacros
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
				macros: instantiableTestMacros
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
				macros: instantiableTestMacros
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
				macros: instantiableTestMacros
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
				macros: instantiableTestMacros
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
				macros: instantiableTestMacros
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
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

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
						]
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
				"""
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
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

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
						]
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
				"""
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
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

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
						]
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
				"""
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
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

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
						]
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
				"""
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
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

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
						]
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
				"""
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
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

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
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenOnlyDependencyMissingFromInit() {
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
					public init(receivedA: ReceivedA) {
						self.receivedA = receivedA
						_ = "keep me"
					}

					let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedA: ReceivedA"),
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenSecondDependencyMissingFromInit() {
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
					public init(
				receivedA: ReceivedA,
				receivedB: ReceivedB
				) {
						self.receivedA = receivedA
						self.receivedB = receivedB
						_ = "keep me"
					}

					let receivedA: ReceivedA
					let receivedB: ReceivedB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedB: ReceivedB"),
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenSecondDependencyMissingFromInitAndNewlinesInArgumentList() {
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
				receivedA: ReceivedA,
				receivedB: ReceivedB
					) {
						self.receivedA = receivedA
						self.receivedB = receivedB
						_ = "keep me"
					}

					let receivedA: ReceivedA
					let receivedB: ReceivedB
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedB: ReceivedB"),
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenFirstDependencyMissingFromInit() {
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
					public init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB

					public typealias ForwardedProperties = ForwardedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for forwardedA: ForwardedA"),
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenMiddleDependencyMissingFromInit() {
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
					public init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB

					public typealias ForwardedProperties = ForwardedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedA: ReceivedA"),
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenMiddleDependencyMissingFromInitAndArgumentAlreadySet() {
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
					public init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB

					public typealias ForwardedProperties = ForwardedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedA: ReceivedA"),
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenLastDependencyMissingFromInit() {
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
						receivedA: ReceivedA,
						receivedB: ReceivedB
					) {
				        self.forwardedA = forwardedA
				        self.receivedA = receivedA
				        self.receivedB = receivedB
				    }

				    let forwardedA: ForwardedA
				    let receivedA: ReceivedA
				    let receivedB: ReceivedB

				    public typealias ForwardedProperties = ForwardedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedB: ReceivedB"),
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenFirstDependencyMissingFromInitAndNonDependencyParameterExists() {
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
					public init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB

					public typealias ForwardedProperties = ForwardedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for forwardedA: ForwardedA"),
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenMiddleDependencyMissingFromInitAndNonDependencyParameterExists() {
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
						receivedA: ReceivedA,
						receivedB: ReceivedB
					) {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB

					public typealias ForwardedProperties = ForwardedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedA: ReceivedA"),
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenLastDependencyMissingFromInitAndNonDependencyParameterExists() {
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
					public init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB

					public typealias ForwardedProperties = ForwardedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedB: ReceivedB"),
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenLastDependencyMissingFromInitAndEscapingDependencyParameterExists() {
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
					public init(customizable: @escaping (String) -> Void, forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB) {
						self.customizable = customizable
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					let customizable: (String) -> Void
					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB

					public typealias ForwardedProperties = (customizable: (String) -> Void, forwardedA: ForwardedA)
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for receivedB: ReceivedB"),
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenAllDependenciesMissingFromInit() {
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
					public init(
				received: Received,
				instantiated: Instantiated,
				forwarded: Forwarded
				) {
				self.received = received
				self.instantiated = instantiated
				self.forwarded = forwarded
					}

					let received: Received
					let instantiated: Instantiated
					let forwarded: Forwarded

					public typealias ForwardedProperties = Forwarded
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for received: Received, instantiated: Instantiated, forwarded: Forwarded"),
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenIncorrectAccessibilityOnInitAndOtherNonConformingInitializersExist() {
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

					public init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB

					public typealias ForwardedProperties = ForwardedA
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
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenDependencyMissingFromInitAndOtherNonConformingInitializersExist() {
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

					public init(forwardedA: ForwardedA, receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					let forwardedA: ForwardedA
					let receivedA: ReceivedA
					let receivedB: ReceivedB

					public typealias ForwardedProperties = ForwardedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 18,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for forwardedA: ForwardedA"),
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenDependencyMissingFromInitAndAccessibilityModifierMissing() {
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
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
						line: 3,
						column: 2,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add arguments for forwardedA: ForwardedA"),
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_generatesInitWithForwardedPropertiesWhenThereAreMultipleForwardedProperties() {
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
				public init(
				userID: String,
				userName: String
				) {
				self.userID = userID
				self.userName = userName
				}

				    let userID: String

				    let userName: String

				    public typealias ForwardedProperties = (userID: String, userName: String)
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
						]
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
				"""
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
				public init(closure: @escaping () -> Void) {
				self.closure = closure
				}

				    let closure: () -> Void

				    public typealias ForwardedProperties = () -> Void
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
						]
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
				"""
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
				public init(closure: @escaping @Sendable () -> Void) {
				self.closure = closure
				}

				    let closure: @Sendable () -> Void

				    public typealias ForwardedProperties = @Sendable () -> Void
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
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWhenInstantiatorDependencyMissingFromInit() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated private let instantiatableAInstantiator: Instantiator<ReceivedA>
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				public init(instantiatableAInstantiator: Instantiator<ReceivedA>) {
				self.instantiatableAInstantiator = instantiatableAInstantiator
				}

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
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesInitWhenExistingInitIsMissingAccessModifier() {
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
					public init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					let a: A
					let b: B
					let c: C

					public typealias ForwardedProperties = C
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
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesInitWhenExistingInitIsMissingAccessModifierWithOtherModifier() {
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
					public final init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					let a: A
					let b: B
					let c: C

					public typealias ForwardedProperties = C
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
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesInitWhenExistingInitHasIncorrectAccessModifier() {
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
					public init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					let a: A
					let b: B
					let c: C

					public typealias ForwardedProperties = C
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
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesInitWhenExistingInitHasIncorrectAccessModifierWithCorrectEarlierModifier() {
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
					final public init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					let a: A
					let b: B
					let c: C

					public typealias ForwardedProperties = C
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
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesInitWhenExistingInitHasIncorrectAccessModifierWithCorrectLaterModifier() {
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
					public final init(a: A, b: B, c: C) {
						self.a = a
						self.b = b
						self.c = c
					}

					let a: A
					let b: B
					let c: C

					public typealias ForwardedProperties = C
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
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesInitWhenExistingInitIsMissingAccessModifierAndAnotherInitializerWithMissingArgument() {
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

					let a: A
					let b: B
					let c: C

					public typealias ForwardedProperties = C
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
						]
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
				"""
			)
		}

		@Test
		func declaration_fixit_updatesInitWhenExistingInitIsMissingAccessModifierAndAnotherInitializerExistsWithExtraArgument() {
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

					let a: A
					let b: B
					let c: C

					public typealias ForwardedProperties = C
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
						]
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
				"""
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
				macros: instantiableTestMacros
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
				macros: instantiableTestMacros
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
				public final class ExampleService: Instantiable {
				    public init() {}
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type or extension must declare conformance to `Instantiable`",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Declare conformance to `Instantiable`"),
						]
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
				"""
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
				public final class ExampleService: CustomStringConvertible, Instantiable {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type or extension must declare conformance to `Instantiable`",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Declare conformance to `Instantiable`"),
						]
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
				"""
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
				public final class ExampleService: CustomStringConvertible, Instantiable {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type or extension must declare conformance to `Instantiable`",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Declare conformance to `Instantiable`"),
						]
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
				"""
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
				macros: instantiableTestMacros
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
						message: "Dependency can have at most one of @Instantiated, @Received, or @Forwarded attached macro",
						line: 7,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Remove excessive attached macros"),
						]
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
				"""
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

				    let receivedA: ReceivedA 
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Dependency must not have hand-written initializer",
						line: 7,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Remove initializer"),
						]
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Remove initializer",
				],
				fixedSource: """
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA 
				}
				"""
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
				public actor ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must be `public` or `open`",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						]
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
				"""
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
				public class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must be `public` or `open`",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						]
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
				"""
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
				public final class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must be `public` or `open`",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						]
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
				"""
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
				public class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must be `public` or `open`",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						]
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
				"""
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
				public class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must be `public` or `open`",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						]
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
				"""
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
				public class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must be `public` or `open`",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						]
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
				"""
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
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must be `public` or `open`",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public` modifier"),
						]
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
				"""
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
				public init() {
				// The following properties are not decorated with the @Instantiated, @Received, or @Forwarded macros, do not have default values, and are not computed properties.
				uninitializedProperty = <#T##assign_uninitializedProperty#>
				}

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
						]
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
				"""
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
				public init(receivedA: ReceivedA) {
				self.receivedA = receivedA

				// The following properties are not decorated with the @Instantiated, @Received, or @Forwarded macros, do not have default values, and are not computed properties.
				uninitializedProperty = <#T##assign_uninitializedProperty#>
				}

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
						]
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
				"""
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
				public init(receivedA: ReceivedA) {
				self.receivedA = receivedA

				// The following properties are not decorated with the @Instantiated, @Received, or @Forwarded macros, do not have default values, and are not computed properties.
				uninitializedProperty1 = <#T##assign_uninitializedProperty1#>
				uninitializedProperty2 = <#T##assign_uninitializedProperty2#>
				uninitializedProperty3 = <#T##assign_uninitializedProperty3#>
				(uninitializedProperty4, uninitializedProperty5) = <#T##assign_(uninitializedProperty4, uninitializedProperty5)#>
				}

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
						]
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
				"""
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
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type or extension must declare conformance to `Instantiable`",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Declare conformance to `Instantiable`"),
						]
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
				"""
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
				extension ExampleService: CustomStringConvertible, Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type or extension must declare conformance to `Instantiable`",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Declare conformance to `Instantiable`"),
						]
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
				"""
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
				extension ExampleService: CustomStringConvertible, Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type or extension must declare conformance to `Instantiable`",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Declare conformance to `Instantiable`"),
						]
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
				"""
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
				public static func instantiate() -> ExampleService
				{}


				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension of ExampleService must have a `public static func instantiate() -> ExampleService` method",
						line: 2,
						column: 41,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Add `public static func instantiate() -> ExampleService` method"),
						]
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
				"""
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
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension must have an `instantiate()` method that is both `public` and `static`",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Set `public static` modifiers"),
						]
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
				"""
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
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension must have an `instantiate()` method that is both `public` and `static`",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Set `public static` modifiers"),
						]
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
				"""
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
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension must have an `instantiate()` method that is both `public` and `static`",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Set `public static` modifiers"),
						]
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
				"""
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
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension’s `instantiate()` method must return the same base type as the extended type",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Make `instantiate()`’s return type the same base type as the extended type"),
						]
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Make `instantiate()`’s return type the same base type as the extended type",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
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
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension’s `instantiate()` method must return the same base type as the extended type",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Make `instantiate()`’s return type the same base type as the extended type"),
						]
					),
				],
				macros: instantiableTestMacros,
				applyFixIts: [
					"Make `instantiate()`’s return type the same base type as the extended type",
				],
				fixedSource: """
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
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
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension’s `instantiate()` method must not throw or be async",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Remove effect specifiers"),
						]
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
				"""
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
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension’s `instantiate()` method must not throw or be async",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Remove effect specifiers"),
						]
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
				"""
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
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension’s `instantiate()` method must not throw or be async",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Remove effect specifiers"),
						]
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
				"""
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
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension’s `instantiate()` method must not have a generic parameter",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Remove generic parameter"),
						]
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
				"""
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
				    public static func instantiate() -> Array { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension must not have a generic `where` clause",
						line: 3,
						column: 5,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Remove generic `where` clause"),
						]
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
				"""
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
				extension Array: Instantiable {
				    public static func instantiate() -> Array { fatalError() }
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated extension must not have a generic `where` clause",
						line: 1,
						column: 1,
						severity: .error,
						fixIts: [
							FixItSpec(message: "Remove generic `where` clause"),
						]
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
				"""
			)
		}
	}
#endif
