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

import MacroTesting
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

#if canImport(SafeDIMacros)
	@testable import SafeDIMacros

	@Suite(
		.macros(
			[
				InstantiableVisitor.macroName: InstantiableMacro.self,
				Dependency.Source.instantiatedRawValue: InjectableMacro.self,
				Dependency.Source.receivedRawValue: InjectableMacro.self,
				Dependency.Source.forwardedRawValue: InjectableMacro.self,
			]
		)
	)
	struct InstantiableMacroTests {
		// MARK: Behavior Tests

		@Test
		func providingMacros_containsInstantiable() {
			#expect(SafeDIMacroPlugin().providingMacros.contains(where: { $0 == InstantiableMacro.self }))
		}

		@Test
		func extension_expandsWithoutIssueOnTypeDeclarationWhenInstantiableConformanceMissingAndConformsElsewhereIsTrue() {
			assertMacro {
				"""
				@Instantiable(conformsElsewhere: true)
				public final class ExampleService {
				    public init() {}
				}
				"""
			} expansion: {
				"""
				public final class ExampleService {
				    public init() {}
				}
				"""
			}
		}

		@Test
		func extension_expandsWithoutIssueOnExtensionWhenInstantiableConformanceMissingAndConformsElsewhereIsTrue() {
			assertMacro {
				"""
				@Instantiable(conformsElsewhere: true)
				extension ExampleService: CustomStringConvertible {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				"""
			} expansion: {
				"""
				extension ExampleService: CustomStringConvertible {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				"""
			}
		}

		// MARK: Error tests

		@Test
		func declaration_throwsErrorWhenOnProtocol() {
			assertMacro {
				"""
				@Instantiable
				public protocol ExampleService {}
				"""
			} diagnostics: {
				"""
				@Instantiable
				┬────────────
				╰─ 🛑 @Instantiable must decorate an extension on a type or a class, struct, or actor declaration
				public protocol ExampleService {}
				"""
			}
		}

		@Test
		func declaration_throwsErrorWhenOnEnum() {
			assertMacro {
				"""
				@Instantiable
				public enum ExampleService: Instantiable {}
				"""
			} diagnostics: {
				"""
				@Instantiable
				┬────────────
				╰─ 🛑 @Instantiable must decorate an extension on a type or a class, struct, or actor declaration
				public enum ExampleService: Instantiable {}
				"""
			}
		}

		@Test
		func declaration_throwsErrorWhenFulfillingAdditionalTypesIncludesAnOptional() {
			assertMacro {
				"""
				@Instantiable(fulfillingAdditionalTypes: [AnyObject?.self])
				public final class ExampleService: Instantiable {}
				"""
			} diagnostics: {
				"""
				@Instantiable(fulfillingAdditionalTypes: [AnyObject?.self])
				┬──────────────────────────────────────────────────────────
				╰─ 🛑 The argument `fulfillingAdditionalTypes` must not include optionals
				public final class ExampleService: Instantiable {}
				"""
			}
		}

		@Test
		func declaration_throwsErrorWhenFulfillingAdditionalTypesIsAPropertyReference() {
			assertMacro {
				"""
				let fulfillingAdditionalTypes: [Any.Type] = [AnyObject.self]
				@Instantiable(fulfillingAdditionalTypes: fulfillingAdditionalTypes)
				public final class ExampleService: Instantiable {}
				"""
			} diagnostics: {
				"""
				let fulfillingAdditionalTypes: [Any.Type] = [AnyObject.self]
				@Instantiable(fulfillingAdditionalTypes: fulfillingAdditionalTypes)
				┬──────────────────────────────────────────────────────────────────
				╰─ 🛑 The argument `fulfillingAdditionalTypes` must be an inlined array
				public final class ExampleService: Instantiable {}
				"""
			}
		}

		@Test
		func declaration_throwsErrorWhenFulfillingAdditionalTypesIsAClosure() {
			assertMacro {
				"""
				@Instantiable(fulfillingAdditionalTypes: { [AnyObject.self] }())
				public final class ExampleService: Instantiable {}
				"""
			} diagnostics: {
				"""
				@Instantiable(fulfillingAdditionalTypes: { [AnyObject.self] }())
				┬───────────────────────────────────────────────────────────────
				╰─ 🛑 The argument `fulfillingAdditionalTypes` must be an inlined array
				public final class ExampleService: Instantiable {}
				"""
			}
		}

		@Test
		func declaration_doesNotThrowWhenRootHasInstantiatedAndRenamedDependencies() {
			assertMacro {
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
				"""
			} expansion: {
				"""
				public final class Foo: Instantiable {
				    public init(dependency: Dependency, renamedDependency: Dependency, renamed2Dependency: Dependency) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    private let dependency: Dependency
				    private let renamedDependency: Dependency
				    private let renamed2Dependency: Dependency
				}
				"""
			}
		}

		@Test
		func declaration_throwsErrorWhenRootHasReceivedDependency() {
			assertMacro {
				"""
				@Instantiable(isRoot: true)
				public final class Foo: Instantiable {
				    public init(dependency: Dependency) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received private let dependency: Dependency 
				}
				"""
			} diagnostics: {
				"""
				@Instantiable(isRoot: true)
				┬──────────────────────────
				╰─ 🛑 Types decorated with `@Instantiable(isRoot: true)` must only have dependencies that are all `@Instantiated` or `@Received(fulfilledByDependencyNamed:ofType:)`, where the latter properties can be fulfilled by `@Instantiated` or `@Received(fulfilledByDependencyNamed:ofType:)` properties declared on this type.

				The following dependencies were found on Foo that violated this contract:
				dependency: Dependency
				public final class Foo: Instantiable {
				    public init(dependency: Dependency) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received private let dependency: Dependency 
				}
				"""
			}
		}

		@Test
		func declaration_throwsErrorWhenRootHasForwardedDependency() {
			assertMacro {
				"""
				@Instantiable(isRoot: true)
				public final class Foo: Instantiable {
				    public init(dependency: Dependency) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Forwarded private let dependency: Dependency 
				}
				"""
			} diagnostics: {
				"""
				@Instantiable(isRoot: true)
				┬──────────────────────────
				╰─ 🛑 Types decorated with `@Instantiable(isRoot: true)` must only have dependencies that are all `@Instantiated` or `@Received(fulfilledByDependencyNamed:ofType:)`, where the latter properties can be fulfilled by `@Instantiated` or `@Received(fulfilledByDependencyNamed:ofType:)` properties declared on this type.

				The following dependencies were found on Foo that violated this contract:
				dependency: Dependency
				public final class Foo: Instantiable {
				    public init(dependency: Dependency) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Forwarded private let dependency: Dependency 
				}
				"""
			}
		}

		@Test
		func extension_throwsErrorWhenFulfillingAdditionalTypesIsAPropertyReference() {
			assertMacro {
				"""
				let fulfillingAdditionalTypes: [Any.Type] = [AnyObject.self]
				@Instantiable(fulfillingAdditionalTypes: fulfillingAdditionalTypes)
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			} diagnostics: {
				"""
				let fulfillingAdditionalTypes: [Any.Type] = [AnyObject.self]
				@Instantiable(fulfillingAdditionalTypes: fulfillingAdditionalTypes)
				┬──────────────────────────────────────────────────────────────────
				╰─ 🛑 The argument `fulfillingAdditionalTypes` must be an inlined array
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			}
		}

		@Test
		func extension_throwsErrorWhenFulfillingAdditionalTypesIsAClosure() {
			assertMacro {
				"""
				@Instantiable(fulfillingAdditionalTypes: { [AnyObject.self] }())
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable(fulfillingAdditionalTypes: { [AnyObject.self] }())
				┬───────────────────────────────────────────────────────────────
				╰─ 🛑 The argument `fulfillingAdditionalTypes` must be an inlined array
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			}
		}

		@Test
		func extension_throwsErrorWhenMoreThanOneInstantiateMethodForSameType() {
			assertMacro {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				    public static func instantiate(user: User) -> ExampleService { fatalError() }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				┬────────────
				╰─ 🛑 @Instantiable-decorated extension must have a single `instantiate(…)` method that returns `ExampleService`
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				    public static func instantiate(user: User) -> ExampleService { fatalError() }
				}
				"""
			}
		}

		@Test
		func extension_doesNotThrowWhenRootHasNoDependencies() {
			assertMacro {
				"""
				@Instantiable(isRoot: true)
				extension Foo: Instantiable {
				    public static func instantiate() -> Foo { fatalError() }
				}
				"""
			} expansion: {
				"""
				extension Foo: Instantiable {
				    public static func instantiate() -> Foo { fatalError() }
				}
				"""
			}
		}

		@Test
		func extension_throwsErrorWhenRootHasDependencies() {
			assertMacro {
				"""
				@Instantiable(isRoot: true)
				extension Foo: Instantiable {
				    public static func instantiate(bar: Bar) -> Foo { fatalError() }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable(isRoot: true)
				┬──────────────────────────
				╰─ 🛑 Types decorated with `@Instantiable(isRoot: true)` must only have dependencies that are all `@Instantiated` or `@Received(fulfilledByDependencyNamed:ofType:)`, where the latter properties can be fulfilled by `@Instantiated` or `@Received(fulfilledByDependencyNamed:ofType:)` properties declared on this type.

				The following dependencies were found on Foo that violated this contract:
				bar: Bar
				extension Foo: Instantiable {
				    public static func instantiate(bar: Bar) -> Foo { fatalError() }
				}
				"""
			}
		}

		// MARK: FixIt tests

		@Test
		func declaration_fixit_generatesRequiredInitializerWithoutAnyDependenciesOnStruct() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				                                           ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				                                              ✏️ Add required initializer
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				public init() {}

				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				public init() {}

				}
				"""
			}
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithoutAnyDependenciesOnClass() {
			assertMacro {
				"""
				@Instantiable
				public class ExampleService: Instantiable {
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public class ExampleService: Instantiable {
				                                          ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				                                             ✏️ Add required initializer
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public class ExampleService: Instantiable {
				public init() {}

				}
				"""
			} expansion: {
				"""
				public class ExampleService: Instantiable {
				public init() {}

				}
				"""
			}
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithoutAnyDependenciesOnActor() {
			assertMacro {
				"""
				@Instantiable
				public actor ExampleService: Instantiable {
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public actor ExampleService: Instantiable {
				                                          ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				                                             ✏️ Add required initializer
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public actor ExampleService: Instantiable {
				public init() {}

				}
				"""
			} expansion: {
				"""
				public actor ExampleService: Instantiable {
				public init() {}

				}
				"""
			}
		}

		@Test
		func declaration_doesNotGenerateFixitWithoutDependenciesIfItAlreadyExists() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init() {}
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				    public init() {}
				}
				"""
			}
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithoutAnyDependenciesAndInitializedVariable() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    var initializedVariable = "test"
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				                                           ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				                                              ✏️ Add required initializer
				    var initializedVariable = "test"
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				public init() {}

				    var initializedVariable = "test"
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				public init() {}

				    var initializedVariable = "test"
				}
				"""
			}
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithoutAnyDependenciesAndVariableWithAccessor() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    var initializedVariable { "test" }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				                                           ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				                                              ✏️ Add required initializer
				    var initializedVariable { "test" }
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				public init() {}

				    var initializedVariable { "test" }
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				public init() {}

				    var initializedVariable { "test" }
				}
				"""
			}
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerEvenWhenPropertyDecoratedWithUnknownMacro() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated @Unknown let instantiatedA: InstantiatedA
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				                                           ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				                                              ✏️ Add required initializer
				    @Instantiated @Unknown let instantiatedA: InstantiatedA
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    @Instantiated @Unknown let instantiatedA: InstantiatedA
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    @Unknown let instantiatedA: InstantiatedA
				}
				"""
			}
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerEvenWhenPropertyDecoratedWithUnknownMacroInIfConfig() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated
				    #if DEBUG
				    @Unknown
				    #endif
				    let instantiatedA: InstantiatedA
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				                                           ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				                                              ✏️ Add required initializer
				    @Instantiated
				    #if DEBUG
				    @Unknown
				    #endif
				    let instantiatedA: InstantiatedA
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}
				    let instantiatedA: InstantiatedA
				}
				"""
			}
		}

		@Test
		func declaration_doesNotGenerateRequiredInitializerWithDependenciesIfItAlreadyExists() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let instantiatedA: InstantiatedA

				    public init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				    let instantiatedA: InstantiatedA

				    public init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }
				}
				"""
			}
		}

		@Test
		func declaration_doesNotGenerateRequiredInitializerIfItAlreadyExistsWithClosureDependency() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(block closure: @escaping () -> Void) {
				        self.closure = closure
				    }
				    @Forwarded let closure: () -> Void
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				    public init(block closure: @escaping () -> Void) {
				        self.closure = closure
				    }
				    let closure: () -> Void

				    public typealias ForwardedProperties = () -> Void
				}
				"""
			}
		}

		@Test
		func declaration_doesNotGenerateRequiredInitializerIfItAlreadyExistsWithSendableClosureDependency() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(closure: @escaping @Sendable () -> Void) {
				        self.closure = closure
				    }
				    @Forwarded let closure: @Sendable () -> Void
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				    public init(closure: @escaping @Sendable () -> Void) {
				        self.closure = closure
				    }
				    let closure: @Sendable () -> Void

				    public typealias ForwardedProperties = @Sendable () -> Void
				}
				"""
			}
		}

		@Test
		func declaration_doesNotGenerateRequiredInitializerIfItAlreadyExistsWithTupleWrappedClosureDependency() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(closure: @escaping @Sendable () -> Void) {
				        self.closure = closure
				    }
				    @Forwarded let closure: (() -> Void)
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				    public init(closure: @escaping @Sendable () -> Void) {
				        self.closure = closure
				    }
				    let closure: (() -> Void)

				    public typealias ForwardedProperties = () -> Void
				}
				"""
			}
		}

		@Test
		func declaration_doesNotGenerateRequiredInitializerIfItAlreadyExistsWithDefaultArguments() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    let nonInjectedProperty: Int

				    public init(nonInjectedProperty: Int = 5) {
				        self.nonInjectedProperty = nonInjectedProperty
				    }
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				    let nonInjectedProperty: Int

				    public init(nonInjectedProperty: Int = 5) {
				        self.nonInjectedProperty = nonInjectedProperty
				    }
				}
				"""
			}
		}

		@Test
		func declaration_doesNotGenerateRequiredInitializerWithDependenciesSatisfyingInitializerIfItAlreadyExistsWithDefaultArguments() {
			assertMacro {
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
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				    let instantiatedA: InstantiatedA

				    let nonInjectedProperty: Int

				    public init(instantiatedA: InstantiatedA, nonInjectedProperty: Int = 5) {
				        self.instantiatedA = instantiatedA
				        self.nonInjectedProperty = nonInjectedProperty
				    }
				}
				"""
			}
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithDependencies() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let instantiatedA: InstantiatedA
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				                                           ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				                                              ✏️ Add required initializer
				    @Instantiated let instantiatedA: InstantiatedA
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    @Instantiated let instantiatedA: InstantiatedA
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    let instantiatedA: InstantiatedA
				}
				"""
			}
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithDependenciesWhenNestedTypesHaveUninitializedProperties() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public final class ExampleService: Instantiable {
				                                                ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				                                                   ✏️ Add required initializer
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
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithDependenciesWhenPropertyHasInitializerAndNoType() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let instantiatedA: InstantiatedA

				    let initializedProperty = 5
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				                                           ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				                                              ✏️ Add required initializer
				    @Instantiated let instantiatedA: InstantiatedA

				    let initializedProperty = 5
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    @Instantiated let instantiatedA: InstantiatedA

				    let initializedProperty = 5
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    let instantiatedA: InstantiatedA

				    let initializedProperty = 5
				}
				"""
			}
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithDependenciesWhenPropertyHasInitializerAndType() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let instantiatedA: InstantiatedA

				    let initializedProperty: Int = 5
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				                                           ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				                                              ✏️ Add required initializer
				    @Instantiated let instantiatedA: InstantiatedA

				    let initializedProperty: Int = 5
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    @Instantiated let instantiatedA: InstantiatedA

				    let initializedProperty: Int = 5
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    let instantiatedA: InstantiatedA

				    let initializedProperty: Int = 5
				}
				"""
			}
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithDependenciesWhenPropertyIsOptional() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let instantiatedA: InstantiatedA

				    var optionalProperty: Int?
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				                                           ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				                                              ✏️ Add required initializer
				    @Instantiated let instantiatedA: InstantiatedA

				    var optionalProperty: Int?
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    @Instantiated let instantiatedA: InstantiatedA

				    var optionalProperty: Int?
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    let instantiatedA: InstantiatedA

				    var optionalProperty: Int?
				}
				"""
			}
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithDependenciesWhenPropertyIsStatic() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let instantiatedA: InstantiatedA

				    // This won't compile but we should still generate an initializer.
				    public static let staticProperty: Int
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				                                           ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				                                              ✏️ Add required initializer
				    @Instantiated let instantiatedA: InstantiatedA

				    // This won't compile but we should still generate an initializer.
				    public static let staticProperty: Int
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				public init(instantiatedA: InstantiatedA) {
				self.instantiatedA = instantiatedA
				}

				    let instantiatedA: InstantiatedA

				    // This won't compile but we should still generate an initializer.
				    public static let staticProperty: Int
				}
				"""
			}
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenOnlyDependencyMissingFromInit() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init() {
						_ = "keep me"
					}

					@Received let receivedA: ReceivedA
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init() {
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				    ✏️ Add arguments for receivedA: ReceivedA
						_ = "keep me"
					}

					@Received let receivedA: ReceivedA
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(receivedA: ReceivedA) {
						self.receivedA = receivedA
						_ = "keep me"
					}

					@Received let receivedA: ReceivedA
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
					public init(receivedA: ReceivedA) {
						self.receivedA = receivedA
						_ = "keep me"
					}

					let receivedA: ReceivedA
				}
				"""
			}
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenSecondDependencyMissingFromInit() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(receivedA: ReceivedA) {
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				    ✏️ Add arguments for receivedB: ReceivedB
						self.receivedA = receivedA
						_ = "keep me"
					}

					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenSecondDependencyMissingFromInitAndNewlinesInArgumentList() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				    ✏️ Add arguments for receivedB: ReceivedB
						receivedA: ReceivedA
					) {
						self.receivedA = receivedA
						_ = "keep me"
					}

					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenFirstDependencyMissingFromInit() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(receivedA: ReceivedA, receivedB: ReceivedB) {
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				    ✏️ Add arguments for forwardedA: ForwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenMiddleDependencyMissingFromInit() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(forwardedA: ForwardedA, receivedB: ReceivedB) {
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				    ✏️ Add arguments for receivedA: ReceivedA
						self.forwardedA = forwardedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenMiddleDependencyMissingFromInitAndArgumentAlreadySet() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(forwardedA: ForwardedA, receivedB: ReceivedB) {
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				    ✏️ Add arguments for receivedA: ReceivedA
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenLastDependencyMissingFromInit() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(
				    ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				       ✏️ Add arguments for receivedB: ReceivedB
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
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenFirstDependencyMissingFromInitAndNonDependencyParameterExists() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				    ✏️ Add arguments for forwardedA: ForwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenMiddleDependencyMissingFromInitAndNonDependencyParameterExists() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				    ✏️ Add arguments for receivedA: ReceivedA
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
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenLastDependencyMissingFromInitAndNonDependencyParameterExists() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(forwardedA: ForwardedA, receivedA: ReceivedA, customizable: String = "") {
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				    ✏️ Add arguments for receivedB: ReceivedB
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenLastDependencyMissingFromInitAndEscapingDependencyParameterExists() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					public init(customizable: @escaping (String) -> Void, forwardedA: ForwardedA, receivedA: ReceivedA) {
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				    ✏️ Add arguments for receivedB: ReceivedB
						self.customizable = customizable
						self.forwardedA = forwardedA
						self.receivedA = receivedA
					}

					@Forwarded let customizable: (String) -> Void
					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenIncorrectAccessibilityOnInitAndOtherNonConformingInitializersExist() {
			assertMacro {
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
				"""
			} diagnostics: {
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
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer.
				    ✏️ Add `public` modifier
						self.forwardedA = forwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				"""
			} fixes: {
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenDependencyMissingFromInitAndOtherNonConformingInitializersExist() {
			assertMacro {
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
				"""
			} diagnostics: {
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
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				    ✏️ Add arguments for forwardedA: ForwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				"""
			} fixes: {
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesRequiredInitializerWhenDependencyMissingFromInitAndAccessibilityModifierMissing() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
					init(receivedA: ReceivedA, receivedB: ReceivedB, customizable: String = "") {
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				    ✏️ Add arguments for forwardedA: ForwardedA
						self.receivedA = receivedA
						self.receivedB = receivedB
					}

					@Forwarded let forwardedA: ForwardedA
					@Received let receivedA: ReceivedA
					@Received let receivedB: ReceivedB
				}
				"""
			} fixes: {
				"""
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
			}
		}

		@Test
		func declaration_fixit_generatesInitWithForwardedPropertiesWhenThereAreMultipleForwardedProperties() {
			assertMacro {
				"""
				@Instantiable
				public final class UserService: Instantiable {
				    @Forwarded let userID: String

				    @Forwarded let userName: String
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public final class UserService: Instantiable {
				                                             ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				                                                ✏️ Add required initializer
				    @Forwarded let userID: String

				    @Forwarded let userName: String
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWithClosureDependency() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Forwarded let closure: () -> Void
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				                                           ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				                                              ✏️ Add required initializer
				    @Forwarded let closure: () -> Void
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(closure: @escaping () -> Void) {
				self.closure = closure
				}

				    @Forwarded let closure: () -> Void
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				public init(closure: @escaping () -> Void) {
				self.closure = closure
				}

				    let closure: () -> Void

				    public typealias ForwardedProperties = () -> Void
				}
				"""
			}
		}

		@Test
		func declaration_fixit_generatesFixitForRequiredInitializerWithSendableClosureDependency() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Forwarded let closure: @Sendable () -> Void
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				                                           ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				                                              ✏️ Add required initializer
				    @Forwarded let closure: @Sendable () -> Void
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(closure: @escaping @Sendable () -> Void) {
				self.closure = closure
				}

				    @Forwarded let closure: @Sendable () -> Void
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				public init(closure: @escaping @Sendable () -> Void) {
				self.closure = closure
				}

				    let closure: @Sendable () -> Void

				    public typealias ForwardedProperties = @Sendable () -> Void
				}
				"""
			}
		}

		@Test
		func declaration_fixit_generatesRequiredInitializerWhenInstantiatorDependencyMissingFromInit() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated private let instantiatableAInstantiator: Instantiator<ReceivedA>
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				                                           ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
				                                              ✏️ Add required initializer
				    @Instantiated private let instantiatableAInstantiator: Instantiator<ReceivedA>
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				public init(instantiatableAInstantiator: Instantiator<ReceivedA>) {
				self.instantiatableAInstantiator = instantiatableAInstantiator
				}

				    @Instantiated private let instantiatableAInstantiator: Instantiator<ReceivedA>
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				public init(instantiatableAInstantiator: Instantiator<ReceivedA>) {
				self.instantiatableAInstantiator = instantiatableAInstantiator
				}

				    private let instantiatableAInstantiator: Instantiator<ReceivedA>
				}
				"""
			}
		}

		@Test
		func declaration_fixit_updatesInitWhenExistingInitIsMissingAccessModifier() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public final class UserService: Instantiable {
					init(a: A, b: B, c: C) {
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer.
				    ✏️ Add `public` modifier
						self.a = a
						self.b = b
						self.c = c
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesInitWhenExistingInitIsMissingAccessModifierWithOtherModifier() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public final class UserService: Instantiable {
					final init(a: A, b: B, c: C) {
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer.
				    ✏️ Add `public` modifier
						self.a = a
						self.b = b
						self.c = c
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesInitWhenExistingInitHasIncorrectAccessModifier() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public final class UserService: Instantiable {
					private init(a: A, b: B, c: C) {
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer.
				    ✏️ Add `public` modifier
						self.a = a
						self.b = b
						self.c = c
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesInitWhenExistingInitHasIncorrectAccessModifierWithCorrectEarlierModifier() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public final class UserService: Instantiable {
					final private init(a: A, b: B, c: C) {
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer.
				    ✏️ Add `public` modifier
						self.a = a
						self.b = b
						self.c = c
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesInitWhenExistingInitHasIncorrectAccessModifierWithCorrectLaterModifier() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public final class UserService: Instantiable {
					private final init(a: A, b: B, c: C) {
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer.
				    ✏️ Add `public` modifier
						self.a = a
						self.b = b
						self.c = c
					}

					@Received let a: A
					@Instantiated let b: B
					@Forwarded let c: C
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesInitWhenExistingInitIsMissingAccessModifierAndAnotherInitializerWithMissingArgument() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public final class UserService: Instantiable {
					init(a: A, b: B, c: C) {
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer.
				    ✏️ Add `public` modifier
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
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func declaration_fixit_updatesInitWhenExistingInitIsMissingAccessModifierAndAnotherInitializerExistsWithExtraArgument() {
			assertMacro {
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
				"""
			} diagnostics: {
				"""
				@Instantiable
				public final class UserService: Instantiable {
					init(a: A, b: B, c: C) {
				 ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer.
				    ✏️ Add `public` modifier
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
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func extension_doesNotThrowErrorWhenMoreThanOneInstantiateMethodForSameBaseTypeWithDifferingGeneric() {
			assertMacro {
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
				"""
			} expansion: {
				"""
				extension Container: Instantiable {
				    public static func instantiate() -> Container<String> {
				        .init(value: "")
				    }
				    public static func instantiate() -> Container<Int> {
				        .init(value: 0)
				    }
				}
				"""
			}
		}

		@Test
		func extension_doesNotThrowErrorWhenFulfillingAdditionalType() {
			assertMacro {
				"""
				@Instantiable(fulfillingAdditionalTypes: [SendableContainer<String>.self])
				extension Container: Instantiable {
				    public static func instantiate() -> Container<String> {
				        .init(value: "")
				    }
				}
				"""
			} expansion: {
				"""
				extension Container: Instantiable {
				    public static func instantiate() -> Container<String> {
				        .init(value: "")
				    }
				}
				"""
			}
		}

		@Test
		func declaration_fixit_addsFixitWhenNoConformancesDeclared() {
			assertMacro {
				"""
				@Instantiable
				public final class ExampleService {
				    public init() {}
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				┬────────────
				╰─ 🛑 @Instantiable-decorated type or extension must declare conformance to `Instantiable`
				   ✏️ Declare conformance to `Instantiable`
				public final class ExampleService {
				    public init() {}
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public final class ExampleService: Instantiable {
				    public init() {}
				}
				"""
			} expansion: {
				"""
				public final class ExampleService: Instantiable {
				    public init() {}
				}
				"""
			}
		}

		@Test
		func declaration_fixit_addsFixitWhenInstantiableConformanceMissing() {
			assertMacro {
				"""
				@Instantiable
				public final class ExampleService: CustomStringConvertible {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				┬────────────
				╰─ 🛑 @Instantiable-decorated type or extension must declare conformance to `Instantiable`
				   ✏️ Declare conformance to `Instantiable`
				public final class ExampleService: CustomStringConvertible {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public final class ExampleService: CustomStringConvertible, Instantiable {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				"""
			} expansion: {
				"""
				public final class ExampleService: CustomStringConvertible, Instantiable {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				"""
			}
		}

		@Test
		func declaration_fixit_addsFixitWhenInstantiableConformanceMissingAndConformsElsewhereIsFalse() {
			assertMacro {
				"""
				@Instantiable(conformsElsewhere: false)
				public final class ExampleService: CustomStringConvertible {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable(conformsElsewhere: false)
				┬──────────────────────────────────────
				╰─ 🛑 @Instantiable-decorated type or extension must declare conformance to `Instantiable`
				   ✏️ Declare conformance to `Instantiable`
				public final class ExampleService: CustomStringConvertible {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				"""
			} fixes: {
				"""
				@Instantiable(conformsElsewhere: false)
				public final class ExampleService: CustomStringConvertible, Instantiable {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				"""
			} expansion: {
				"""
				public final class ExampleService: CustomStringConvertible, Instantiable {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				"""
			}
		}

		@Test
		func declaration_doesNotAddFixitWhenRetroactiveInstantiableConformanceExists() {
			assertMacro {
				"""
				@Instantiable
				public final class ExampleService: @retroactive Instantiable, @retroactive CustomStringConvertible {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				"""
			} expansion: {
				"""
				public final class ExampleService: @retroactive Instantiable, @retroactive CustomStringConvertible {
				    public init() {}
				    public var description: String { "ExampleService" }
				}
				"""
			}
		}

		@Test
		func declaration_fixit_addsFixitWhenMultipleInjectableMacrosOnTopOfSingleProperty() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Received @Instantiated let receivedA: ReceivedA
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Received @Instantiated let receivedA: ReceivedA
				    ┬──────────────────────
				    ╰─ 🛑 Dependency can have at most one of @Instantiated, @Received, or @Forwarded attached macro
				       ✏️ Remove excessive attached macros
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Received let receivedA: ReceivedA
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				"""
			}
		}

		@Test
		func declaration_fixit_addsFixitWhenInjectableParameterHasInitializer() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA = .init()
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA = .init()
				    ┬───────────────────────────────────────────────
				    ╰─ 🛑 Dependency must not have hand-written initializer
				       ✏️ Remove initializer
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA 
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA 
				}
				"""
			}
		}

		@Test
		func declaration_fixit_addsFixitWhenInjectableActorIsNotPublicOrOpen() {
			assertMacro {
				"""
				@Instantiable
				actor ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				╰─ 🛑 @Instantiable-decorated type must be `public` or `open`
				   ✏️ Add `public` modifier
				actor ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public actor ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} expansion: {
				"""
				public actor ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				"""
			}
		}

		@Test
		func declaration_fixit_addsFixitWhenInjectableClassIsNotPublicOrOpen() {
			assertMacro {
				"""
				@Instantiable
				class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				╰─ 🛑 @Instantiable-decorated type must be `public` or `open`
				   ✏️ Add `public` modifier
				class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} expansion: {
				"""
				public class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				"""
			}
		}

		@Test
		func declaration_fixit_addsFixitWhenInjectableFinalClassIsNotPublicOrOpen() {
			assertMacro {
				"""
				@Instantiable
				final class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				╰─ 🛑 @Instantiable-decorated type must be `public` or `open`
				   ✏️ Add `public` modifier
				final class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public final class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} expansion: {
				"""
				public final class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				"""
			}
		}

		@Test
		func declaration_fixit_addsFixitWhenInjectableClassIsInternal() {
			assertMacro {
				"""
				@Instantiable
				internal class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				╰─ 🛑 @Instantiable-decorated type must be `public` or `open`
				   ✏️ Add `public` modifier
				internal class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} expansion: {
				"""
				public class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				"""
			}
		}

		@Test
		func declaration_fixit_addsFixitWhenInjectableClassIsFileprivate() {
			assertMacro {
				"""
				@Instantiable
				fileprivate class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				╰─ 🛑 @Instantiable-decorated type must be `public` or `open`
				   ✏️ Add `public` modifier
				fileprivate class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} expansion: {
				"""
				public class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				"""
			}
		}

		@Test
		func declaration_fixit_addsFixitWhenInjectableClassIsPrivate() {
			assertMacro {
				"""
				@Instantiable
				private class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				╰─ 🛑 @Instantiable-decorated type must be `public` or `open`
				   ✏️ Add `public` modifier
				private class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} expansion: {
				"""
				public class ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				"""
			}
		}

		@Test
		func declaration_fixit_addsFixitWhenInjectableStructIsNotPublicOrOpen() {
			assertMacro {
				"""
				@Instantiable
				struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				╰─ 🛑 @Instantiable-decorated type must be `public` or `open`
				   ✏️ Add `public` modifier
				struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    @Instantiated let receivedA: ReceivedA
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				    public init(receivedA: ReceivedA) {
				        self.receivedA = receivedA
				    }

				    let receivedA: ReceivedA
				}
				"""
			}
		}

		@Test
		func declaration_fixit_addsFixitMissingRequiredInitializerWhenPropertyIsMissingInitializerAndThereAreNoDependencies() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    let uninitializedProperty: Int
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				                                           ╰─ 🛑 @Instantiable-decorated type with no @Instantiated, @Received, or @Forwarded-decorated properties must have a `public` or `open` initializer that either takes no parameters or has a default value for each parameter.
				                                              ✏️ Add required initializer
				    let uninitializedProperty: Int
				}
				"""
			} fixes: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				public init() {
				// The following properties are not decorated with the @Instantiated, @Received, or @Forwarded macros, do not have default values, and are not computed properties.
				uninitializedProperty = <#T##assign_uninitializedProperty#>
				}

				    let uninitializedProperty: Int
				}
				"""
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				public init() {
				// The following properties are not decorated with the @Instantiated, @Received, or @Forwarded macros, do not have default values, and are not computed properties.
				uninitializedProperty = <#T##assign_uninitializedProperty#>
				}

				    let uninitializedProperty: Int
				}
				"""
			}
		}

		@Test
		func declaration_fixit_addsFixitMissingRequiredInitializerWhenPropertyIsMissingInitializer() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let receivedA: ReceivedA

				    let uninitializedProperty: Int
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				                                           ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. Parameters in this initializer that do not correspond to a decorated property must have default values.
				                                              ✏️ Add required initializer
				    @Instantiated let receivedA: ReceivedA

				    let uninitializedProperty: Int
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
				public struct ExampleService: Instantiable {
				public init(receivedA: ReceivedA) {
				self.receivedA = receivedA

				// The following properties are not decorated with the @Instantiated, @Received, or @Forwarded macros, do not have default values, and are not computed properties.
				uninitializedProperty = <#T##assign_uninitializedProperty#>
				}

				    let receivedA: ReceivedA

				    let uninitializedProperty: Int
				}
				"""
			}
		}

		@Test
		func declaration_fixit_addsFixitMissingRequiredInitializerWhenMultiplePropertiesAreMissingInitializer() {
			assertMacro {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @Instantiated let receivedA: ReceivedA

				    var uninitializedProperty1: Int
				    let uninitializedProperty2: Int, uninitializedProperty3: Int, initializedProperty = "init"
				    let (uninitializedProperty4, uninitializedProperty5): (Int, Int)
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				                                           ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property. Parameters in this initializer that do not correspond to a decorated property must have default values.
				                                              ✏️ Add required initializer
				    @Instantiated let receivedA: ReceivedA

				    var uninitializedProperty1: Int
				    let uninitializedProperty2: Int, uninitializedProperty3: Int, initializedProperty = "init"
				    let (uninitializedProperty4, uninitializedProperty5): (Int, Int)
				}
				"""
			} fixes: {
				"""
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
			} expansion: {
				"""
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
				"""
			}
		}

		@Test
		func extension_fixit_addsFixitWhenNoConformancesDeclared() {
			assertMacro {
				"""
				@Instantiable
				extension ExampleService {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				┬────────────
				╰─ 🛑 @Instantiable-decorated type or extension must declare conformance to `Instantiable`
				   ✏️ Declare conformance to `Instantiable`
				extension ExampleService {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			} fixes: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			} expansion: {
				"""
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			}
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiableConformanceMissing() {
			assertMacro {
				"""
				@Instantiable
				extension ExampleService: CustomStringConvertible {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				┬────────────
				╰─ 🛑 @Instantiable-decorated type or extension must declare conformance to `Instantiable`
				   ✏️ Declare conformance to `Instantiable`
				extension ExampleService: CustomStringConvertible {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				"""
			} fixes: {
				"""
				@Instantiable
				extension ExampleService: CustomStringConvertible, Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				"""
			} expansion: {
				"""
				extension ExampleService: CustomStringConvertible, Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				"""
			}
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiableConformanceMissingAndConformsElsewhereIsFalse() {
			assertMacro {
				"""
				@Instantiable(conformsElsewhere: false)
				extension ExampleService: CustomStringConvertible {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable(conformsElsewhere: false)
				┬──────────────────────────────────────
				╰─ 🛑 @Instantiable-decorated type or extension must declare conformance to `Instantiable`
				   ✏️ Declare conformance to `Instantiable`
				extension ExampleService: CustomStringConvertible {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				"""
			} fixes: {
				"""
				@Instantiable(conformsElsewhere: false)
				extension ExampleService: CustomStringConvertible, Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				"""
			} expansion: {
				"""
				extension ExampleService: CustomStringConvertible, Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }

				    public var description: String { "ExampleService" }
				}
				"""
			}
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodMissing() {
			assertMacro {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				                                        ╰─ 🛑 @Instantiable-decorated extension of ExampleService must have a `public static func instantiate() -> ExampleService` method
				                                           ✏️ Add `public static func instantiate() -> ExampleService` method
				}
				"""
			} fixes: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				public static func instantiate() -> ExampleService
				{}


				}
				"""
			} expansion: {
				"""
				extension ExampleService: Instantiable {
				public static func instantiate() -> ExampleService
				{}


				}
				"""
			}
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodIsNotPublic() {
			assertMacro {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    static func instantiate() -> ExampleService { fatalError() }
				    ┬───────────────────────────────────────────────────────────
				    ╰─ 🛑 @Instantiable-decorated extension must have an `instantiate()` method that is both `public` and `static`
				       ✏️ Set `public static` modifiers
				}
				"""
			} fixes: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			} expansion: {
				"""
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			}
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodIsNotStatic() {
			assertMacro {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public func instantiate() -> ExampleService { fatalError() }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public func instantiate() -> ExampleService { fatalError() }
				    ┬───────────────────────────────────────────────────────────
				    ╰─ 🛑 @Instantiable-decorated extension must have an `instantiate()` method that is both `public` and `static`
				       ✏️ Set `public static` modifiers
				}
				"""
			} fixes: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			} expansion: {
				"""
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			}
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodIsNotStaticOrPublic() {
			assertMacro {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    func instantiate() -> ExampleService { fatalError() }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    func instantiate() -> ExampleService { fatalError() }
				    ┬────────────────────────────────────────────────────
				    ╰─ 🛑 @Instantiable-decorated extension must have an `instantiate()` method that is both `public` and `static`
				       ✏️ Set `public static` modifiers
				}
				"""
			} fixes: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			} expansion: {
				"""
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			}
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodReturnsIncorrectType() {
			assertMacro {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> OtherExampleService { fatalError() }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> OtherExampleService { fatalError() }
				    ┬───────────────────────────────────────────────────────────────────────
				    ╰─ 🛑 @Instantiable-decorated extension’s `instantiate()` method must return the same base type as the extended type
				       ✏️ Make `instantiate()`’s return type the same base type as the extended type
				}
				"""
			} fixes: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			} expansion: {
				"""
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			}
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodReturnsTypeWrappedInArray() {
			assertMacro {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> [ExampleService] { fatalError() }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> [ExampleService] { fatalError() }
				    ┬────────────────────────────────────────────────────────────────────
				    ╰─ 🛑 @Instantiable-decorated extension’s `instantiate()` method must return the same base type as the extended type
				       ✏️ Make `instantiate()`’s return type the same base type as the extended type
				}
				"""
			} fixes: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			} expansion: {
				"""
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			}
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodIsAsync() {
			assertMacro {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() async -> ExampleService { fatalError() }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() async -> ExampleService { fatalError() }
				    ┬────────────────────────────────────────────────────────────────────────
				    ╰─ 🛑 @Instantiable-decorated extension’s `instantiate()` method must not throw or be async
				       ✏️ Remove effect specifiers
				}
				"""
			} fixes: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			} expansion: {
				"""
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			}
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodThrows() {
			assertMacro {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() throws -> ExampleService { fatalError() }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() throws -> ExampleService { fatalError() }
				    ┬─────────────────────────────────────────────────────────────────────────
				    ╰─ 🛑 @Instantiable-decorated extension’s `instantiate()` method must not throw or be async
				       ✏️ Remove effect specifiers
				}
				"""
			} fixes: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			} expansion: {
				"""
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			}
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodIsAsyncAndThrows() {
			assertMacro {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() async throws -> ExampleService { fatalError() }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() async throws -> ExampleService { fatalError() }
				    ┬───────────────────────────────────────────────────────────────────────────────
				    ╰─ 🛑 @Instantiable-decorated extension’s `instantiate()` method must not throw or be async
				       ✏️ Remove effect specifiers
				}
				"""
			} fixes: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			} expansion: {
				"""
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			}
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodHasGenericParameter() {
			assertMacro {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate<T>() -> ExampleService { fatalError() }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate<T>() -> ExampleService { fatalError() }
				    ┬─────────────────────────────────────────────────────────────────────
				    ╰─ 🛑 @Instantiable-decorated extension’s `instantiate()` method must not have a generic parameter
				       ✏️ Remove generic parameter
				}
				"""
			} fixes: {
				"""
				@Instantiable
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			} expansion: {
				"""
				extension ExampleService: Instantiable {
				    public static func instantiate() -> ExampleService { fatalError() }
				}
				"""
			}
		}

		@Test
		func extension_fixit_addsFixitWhenInstantiateMethodHasGenericWhereClause() {
			assertMacro {
				"""
				@Instantiable
				extension Array: Instantiable {
				    public static func instantiate() -> Array where Element == String { fatalError() }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				extension Array: Instantiable {
				    public static func instantiate() -> Array where Element == String { fatalError() }
				    ┬─────────────────────────────────────────────────────────────────────────────────
				    ╰─ 🛑 @Instantiable-decorated extension must not have a generic `where` clause
				       ✏️ Remove generic `where` clause
				}
				"""
			} fixes: {
				"""
				@Instantiable
				extension Array: Instantiable {
				    public static func instantiate() -> Array { fatalError() }
				}
				"""
			} expansion: {
				"""
				extension Array: Instantiable {
				    public static func instantiate() -> Array { fatalError() }
				}
				"""
			}
		}

		@Test
		func extension_fixit_addsFixitWhenExtensionHasGenericWhereClause() {
			assertMacro {
				"""
				@Instantiable
				extension Array: Instantiable where Element == String {
				    public static func instantiate() -> Array { fatalError() }
				}
				"""
			} diagnostics: {
				"""
				@Instantiable
				┬────────────
				╰─ 🛑 @Instantiable-decorated extension must not have a generic `where` clause
				   ✏️ Remove generic `where` clause
				extension Array: Instantiable where Element == String {
				    public static func instantiate() -> Array { fatalError() }
				}
				"""
			} fixes: {
				"""
				@Instantiable
				extension Array: Instantiable {
				    public static func instantiate() -> Array { fatalError() }
				}
				"""
			} expansion: {
				"""
				extension Array: Instantiable {
				    public static func instantiate() -> Array { fatalError() }
				}
				"""
			}
		}
	}
#endif
