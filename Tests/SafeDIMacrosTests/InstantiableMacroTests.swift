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
import XCTest

import SafeDICore

#if canImport(SafeDIMacros)
    @testable import SafeDIMacros

    final class InstantiableMacroTests: XCTestCase {
        let testMacros: [String: Macro.Type] = [
            InstantiableVisitor.macroName: InstantiableMacro.self,
            Dependency.Source.instantiatedRawValue: InjectableMacro.self,
            Dependency.Source.receivedRawValue: InjectableMacro.self,
            Dependency.Source.forwardedRawValue: InjectableMacro.self,
        ]

        // MARK: XCTestCase

        override func invokeTest() {
            withMacroTesting(macros: testMacros) {
                super.invokeTest()
            }
        }

        // MARK: Behavior Tests

        func test_providingMacros_containsInstantiable() {
            XCTAssertTrue(SafeDIMacroPlugin().providingMacros.contains(where: { $0 == InstantiableMacro.self }))
        }

        func test_extension_expandsWithoutIssueOnTypeDeclarationWhenInstantiableConformanceMissingAndConformsElsewhereIsTrue() {
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

        func test_extension_expandsWithoutIssueOnExtensionWhenInstantiableConformanceMissingAndConformsElsewhereIsTrue() {
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

        func test_declaration_throwsErrorWhenOnProtocol() {
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

        func test_declaration_throwsErrorWhenOnEnum() {
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

        func test_declaration_throwsErrorWhenFulfillingAdditionalTypesIncludesAnOptional() {
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

        func test_declaration_throwsErrorWhenFulfillingAdditionalTypesIsAPropertyReference() {
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

        func test_declaration_throwsErrorWhenFulfillingAdditionalTypesIsAClosure() {
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

        func test_declaration_doesNotThrowWhenRootHasInstantiatedAndRenamedDependencies() {
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

        func test_declaration_throwsErrorWhenRootHasReceivedDependency() {
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

        func test_declaration_throwsErrorWhenRootHasForwardedDependency() {
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

        func test_extension_throwsErrorWhenFulfillingAdditionalTypesIsAPropertyReference() {
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

        func test_extension_throwsErrorWhenFulfillingAdditionalTypesIsAClosure() {
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

        func test_extension_throwsErrorWhenMoreThanOneInstantiateMethodForSameType() {
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

        func test_extension_doesNotThrowWhenRootHasNoDependencies() {
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

        func test_extension_throwsErrorWhenRootHasDependencies() {
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

        func test_declaration_fixit_generatesRequiredInitializerWithoutAnyDependenciesOnStruct() {
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

        func test_declaration_fixit_generatesRequiredInitializerWithoutAnyDependenciesOnClass() {
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

        func test_declaration_fixit_generatesRequiredInitializerWithoutAnyDependenciesOnActor() {
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

        func test_declaration_doesNotGenerateFixitWithoutDependenciesIfItAlreadyExists() {
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

        func test_declaration_fixit_generatesRequiredInitializerWithoutAnyDependenciesAndInitializedVariable() {
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

        func test_declaration_fixit_generatesRequiredInitializerWithoutAnyDependenciesAndVariableWithAccessor() {
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

        func test_declaration_fixit_generatesRequiredInitializerEvenWhenPropertyDecoratedWithUnknownMacro() {
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

        func test_declaration_fixit_generatesRequiredInitializerEvenWhenPropertyDecoratedWithUnknownMacroInIfConfig() {
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

        func test_declaration_doesNotGenerateRequiredInitializerWithDependenciesIfItAlreadyExists() {
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

        func test_declaration_doesNotGenerateRequiredInitializerIfItAlreadyExistsWithClosureDependency() {
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

        func test_declaration_doesNotGenerateRequiredInitializerIfItAlreadyExistsWithSendableClosureDependency() {
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

        func test_declaration_doesNotGenerateRequiredInitializerIfItAlreadyExistsWithTupleWrappedClosureDependency() {
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

        func test_declaration_doesNotGenerateRequiredInitializerIfItAlreadyExistsWithDefaultArguments() {
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

        func test_declaration_doesNotGenerateRequiredInitializerWithDependenciesSatisfyingInitializerIfItAlreadyExistsWithDefaultArguments() {
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

        func test_declaration_fixit_generatesRequiredInitializerWithDependencies() {
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

        func test_declaration_fixit_generatesRequiredInitializerWithDependenciesWhenNestedTypesHaveUninitializedProperties() {
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

        func test_declaration_fixit_generatesRequiredInitializerWithDependenciesWhenPropertyHasInitializerAndNoType() {
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

        func test_declaration_fixit_generatesRequiredInitializerWithDependenciesWhenPropertyHasInitializerAndType() {
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

        func test_declaration_fixit_generatesRequiredInitializerWithDependenciesWhenPropertyIsOptional() {
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

        func test_declaration_fixit_generatesRequiredInitializerWithDependenciesWhenPropertyIsStatic() {
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

        func test_declaration_fixit_generatesRequiredInitializerWhenDependencyMissingFromInit() {
            assertMacro {
                """
                @Instantiable
                public struct ExampleService: Instantiable {
                    public init(forwardedA: ForwardedA, receivedA: ReceivedA) {
                        self.forwardedA = forwardedA
                        self.receivedA = receivedA
                        receivedB = ReceivedB()
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
                                                           ╰─ 🛑 @Instantiable-decorated type must have a `public` or `open` initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.
                                                              ✏️ Add required initializer
                    public init(forwardedA: ForwardedA, receivedA: ReceivedA) {
                        self.forwardedA = forwardedA
                        self.receivedA = receivedA
                        receivedB = ReceivedB()
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

                    public init(forwardedA: ForwardedA, receivedA: ReceivedA) {
                        self.forwardedA = forwardedA
                        self.receivedA = receivedA
                        receivedB = ReceivedB()
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

                    public init(forwardedA: ForwardedA, receivedA: ReceivedA) {
                        self.forwardedA = forwardedA
                        self.receivedA = receivedA
                        receivedB = ReceivedB()
                    }

                    let forwardedA: ForwardedA
                    let receivedA: ReceivedA
                    let receivedB: ReceivedB

                    public typealias ForwardedProperties = ForwardedA
                }
                """
            }
        }

        func test_declaration_fixit_generatesInitWithForwardedPropertiesWhenThereAreMultipleForwardedProperties() {
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

        func test_declaration_fixit_generatesRequiredInitializerWithClosureDependency() {
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

        func test_declaration_fixit_generatesFixitForRequiredInitializerWithSendableClosureDependency() {
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

        func test_declaration_fixit_generatesRequiredInitializerWhenInstantiatorDependencyMissingFromInit() {
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

        func test_extension_doesNotThrowErrorWhenMoreThanOneInstantiateMethodForSameBaseTypeWithDifferingGeneric() {
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

        func test_extension_doesNotThrowErrorWhenFulfillingAdditionalType() {
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

        func test_declaration_fixit_addsFixitWhenNoConformancesDeclared() {
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

        func test_declaration_fixit_addsFixitWhenInstantiableConformanceMissing() {
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

        func test_declaration_fixit_addsFixitWhenInstantiableConformanceMissingAndConformsElsewhereIsFalse() {
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

        func test_declaration_doesNotAddFixitWhenRetroactiveInstantiableConformanceExists() {
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

        func test_declaration_fixit_addsFixitWhenMultipleInjectableMacrosOnTopOfSingleProperty() {
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

        func test_declaration_fixit_addsFixitWhenInjectableParameterHasInitializer() {
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

        func test_declaration_fixit_addsFixitWhenInjectableActorIsNotPublicOrOpen() {
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

        func test_declaration_fixit_addsFixitWhenInjectableClassIsNotPublicOrOpen() {
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

        func test_declaration_fixit_addsFixitWhenInjectableFinalClassIsNotPublicOrOpen() {
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

        func test_declaration_fixit_addsFixitWhenInjectableClassIsInternal() {
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

        func test_declaration_fixit_addsFixitWhenInjectableClassIsFileprivate() {
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

        func test_declaration_fixit_addsFixitWhenInjectableClassIsPrivate() {
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

        func test_declaration_fixit_addsFixitWhenInjectableStructIsNotPublicOrOpen() {
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

        func test_declaration_fixit_addsFixitMissingRequiredInitializerWhenPropertyIsMissingInitializerAndThereAreNoDependencies() {
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

        func test_declaration_fixit_addsFixitMissingRequiredInitializerWhenPropertyIsMissingInitializer() {
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

        func test_declaration_fixit_addsFixitMissingRequiredInitializerWhenMultiplePropertiesAreMissingInitializer() {
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

        func test_extension_fixit_addsFixitWhenNoConformancesDeclared() {
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

        func test_extension_fixit_addsFixitWhenInstantiableConformanceMissing() {
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

        func test_extension_fixit_addsFixitWhenInstantiableConformanceMissingAndConformsElsewhereIsFalse() {
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

        func test_extension_fixit_addsFixitWhenInstantiateMethodMissing() {
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

        func test_extension_fixit_addsFixitWhenInstantiateMethodIsNotPublic() {
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

        func test_extension_fixit_addsFixitWhenInstantiateMethodIsNotStatic() {
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

        func test_extension_fixit_addsFixitWhenInstantiateMethodIsNotStaticOrPublic() {
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

        func test_extension_fixit_addsFixitWhenInstantiateMethodReturnsIncorrectType() {
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

        func test_extension_fixit_addsFixitWhenInstantiateMethodReturnsTypeWrappedInArray() {
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

        func test_extension_fixit_addsFixitWhenInstantiateMethodIsAsync() {
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

        func test_extension_fixit_addsFixitWhenInstantiateMethodThrows() {
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

        func test_extension_fixit_addsFixitWhenInstantiateMethodIsAsyncAndThrows() {
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

        func test_extension_fixit_addsFixitWhenInstantiateMethodHasGenericParameter() {
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

        func test_extension_fixit_addsFixitWhenInstantiateMethodHasGenericWhereClause() {
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

        func test_extension_fixit_addsFixitWhenExtensionHasGenericWhereClause() {
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
