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

	let injectableTestMacros: [String: Macro.Type] = [
		Dependency.Source.instantiatedRawValue: InjectableMacro.self,
		Dependency.Source.receivedRawValue: InjectableMacro.self,
		Dependency.Source.forwardedRawValue: InjectableMacro.self,
	]

	struct InjectableMacroTests {
		// MARK: Behavior Tests

		@Test
		func providingMacros_containsInjectable() {
			#expect(SafeDIMacroPlugin().providingMacros.contains(where: { $0 == InjectableMacro.self }))
		}

		@Test
		func propertyIsFulfilledByTypeWithStringLiteral_expandsWithoutIssue() {
			assertMacroExpansion(
				"""
				public struct ExampleService {
				    @Instantiated(fulfilledByType: "SomethingElse") let something: Something
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    let something: Something
				}
				""",
				macros: injectableTestMacros,
			)
		}

		@Test
		func propertyIsFulfilledByTypeWithStringLiteralNestedType_expandsWithoutIssue() {
			assertMacroExpansion(
				"""
				public struct ExampleService {
				    init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }

				    @Instantiated(fulfilledByType: "Module.ConcreteType") let instantiatedA: InstantiatedA
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }

				    let instantiatedA: InstantiatedA
				}
				""",
				macros: injectableTestMacros,
			)
		}

		@Test
		func propertyIsOnlyIfAvailableAndOptional_expandsWthoutIssue() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService {
					@Received(onlyIfAvailable: true) let receivedA: AnyReceivedA?
				}
				""",
				expandedSource: """
				@Instantiable
				public struct ExampleService {
					let receivedA: AnyReceivedA?
				}
				""",
				macros: injectableTestMacros,
			)
		}

		@Test
		func propertyIsOnlyIfAvailableAndDoubleOptional_expandsWthoutIssue() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService {
					@Received(onlyIfAvailable: true) let receivedA: AnyReceivedA??
				}
				""",
				expandedSource: """
				@Instantiable
				public struct ExampleService {
					let receivedA: AnyReceivedA??
				}
				""",
				macros: injectableTestMacros,
			)
		}

		// MARK: Fixit Tests

		@Test
		func fixit_addsFixitWhenInjectableParameterIsMutable() {
			assertMacroExpansion(
				"""
				public struct ExampleService {
				    init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }

				    @Instantiated var instantiatedA: InstantiatedA
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }

				    var instantiatedA: InstantiatedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "Dependency can not be mutable unless it is decorated with a property wrapper. Mutations to a dependency are not propagated through the dependency tree.",
						line: 6,
						column: 19,
						severity: .error,
						fixIts: [FixItSpec(message: "Replace `var` with `let`")],
					),
				],
				macros: injectableTestMacros,
				applyFixIts: ["Replace `var` with `let`"],
				fixedSource: """
				public struct ExampleService {
				    init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }

				    @Instantiated  let instantiatedA: InstantiatedA
				}
				""",
			)
		}

		@Test
		func fixit_doesNotAddFixitWhenInjectableParameterIsMutableWithPropertyWrapper() {
			assertMacroExpansion(
				"""
				import SwiftUI

				public struct ExampleView {
				    init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }

				    @ObservedObject
				    @Instantiated var instantiatedA: InstantiatedA

				    var body: some View {
				        Text("\\(ObjectIdentifier(instantiatedA))")
				    }
				}
				""",
				expandedSource: #"""
				import SwiftUI

				public struct ExampleView {
				    init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }

				    @ObservedObject
				    var instantiatedA: InstantiatedA

				    var body: some View {
				        Text("\(ObjectIdentifier(instantiatedA))")
				    }
				}
				"""#,
				macros: injectableTestMacros,
			)
		}

		// MARK: Error tests

		@Test
		func throwsErrorWhenUsingFulfilledByTypeOnInstantiator() {
			assertMacroExpansion(
				"""
				public struct ExampleService {
				    @Instantiated(fulfilledByType: "LoginViewController") let loginViewControllerBuilder: Instantiator<UIViewController>
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    let loginViewControllerBuilder: Instantiator<UIViewController>
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `fulfilledByType` can not be used on an `Instantiator` or `SendableInstantiator`. Use an `ErasedInstantiator` or `SendableErasedInstantiator` instead",
						line: 2,
						column: 5,
						severity: .error,
					),
				],
				macros: injectableTestMacros,
			)
		}

		@Test
		func throwsErrorWhenErasedInstantiatorUsedWithoutFulfilledByTypeArgument() {
			assertMacroExpansion(
				"""
				public struct ExampleService {
				    @Instantiated let loginViewControllerBuilder: ErasedInstantiator<UIViewController>
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    let loginViewControllerBuilder: ErasedInstantiator<UIViewController>
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`ErasedInstantiator` and `SendableErasedInstantiator` require use of the argument `fulfilledByType`",
						line: 2,
						column: 5,
						severity: .error,
					),
				],
				macros: injectableTestMacros,
			)
		}

		@Test
		func throwsErrorWhenInjectableMacroAttachedtoStaticProperty() {
			assertMacroExpansion(
				"""
				public struct ExampleService {
				    init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }

				    @Received static let instantiatedA: InstantiatedA
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }

				    static let instantiatedA: InstantiatedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This macro can not decorate `static` variables",
						line: 6,
						column: 5,
						severity: .error,
					),
				],
				macros: injectableTestMacros,
			)
		}

		@Test
		func throwsErrorWhenOnProtocol() {
			assertMacroExpansion(
				"""
				@Instantiated
				protocol ExampleService {}
				""",
				expandedSource: """
				protocol ExampleService {}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "This macro must decorate a instance variable",
						line: 1,
						column: 1,
						severity: .error,
					),
				],
				macros: injectableTestMacros,
			)
		}

		@Test
		func throwsErrorWhenFulfilledByTypeIsNotALiteral() {
			assertMacroExpansion(
				"""
				public struct ExampleService {
				    init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }

				    static let fulfilledByType = "ConcreteType"
				    @Instantiated(fulfilledByType: fulfilledByType) let instantiatedA: InstantiatedA
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }

				    static let fulfilledByType = "ConcreteType"
				    let instantiatedA: InstantiatedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `fulfilledByType` must be a string literal",
						line: 7,
						column: 5,
						severity: .error,
					),
				],
				macros: injectableTestMacros,
			)
		}

		@Test
		func throwsErrorWhenFulfilledByTypeIsNotAStringExpression() {
			assertMacroExpansion(
				"""
				public struct ExampleService {
				    init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }

				    static let fulfilledByType = "ConcreteType"
				    @Instantiated(fulfilledByType: "\\(Self.fulfilledByType)") let instantiatedA: InstantiatedA
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }

				    static let fulfilledByType = "ConcreteType"
				    let instantiatedA: InstantiatedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `fulfilledByType` must be a string literal",
						line: 7,
						column: 5,
						severity: .error,
					),
				],
				macros: injectableTestMacros,
			)
		}

		@Test
		func throwsErrorWhenFulfilledByTypeIsAnOptionalType() {
			assertMacroExpansion(
				"""
				public struct ExampleService {
				    init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }

				    @Instantiated(fulfilledByType: "ConcreteType?") let instantiatedA: InstantiatedA
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }

				    let instantiatedA: InstantiatedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `fulfilledByType` must refer to a simple type",
						line: 6,
						column: 5,
						severity: .error,
					),
				],
				macros: injectableTestMacros,
			)
		}

		@Test
		func throwsErrorWhenFulfilledByTypeIsAnImplicitlyUnwrappedType() {
			assertMacroExpansion(
				"""
				public struct ExampleService {
				    init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }

				    @Instantiated(fulfilledByType: "ConcreteType!") let instantiatedA: InstantiatedA
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    init(instantiatedA: InstantiatedA) {
				        self.instantiatedA = instantiatedA
				    }

				    let instantiatedA: InstantiatedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `fulfilledByType` must refer to a simple type",
						line: 6,
						column: 5,
						severity: .error,
					),
				],
				macros: injectableTestMacros,
			)
		}

		@Test
		func throwsErrorWhenfulfilledByDependencyNamedIsNotAStringLiteral() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService {
				    static let instantiatedAName: StaticString = "instantiatedA"
				    @Received(fulfilledByDependencyNamed: instantiatedAName, ofType: InstantiatedA.self) let receivedA: ReceivedA
				}
				""",
				expandedSource: """
				@Instantiable
				public struct ExampleService {
				    static let instantiatedAName: StaticString = "instantiatedA"
				    let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `fulfilledByDependencyNamed` must be a string literal",
						line: 4,
						column: 5,
						severity: .error,
					),
				],
				macros: injectableTestMacros,
			)
		}

		@Test
		func throwsErrorWhenOfTypeIsAnInvalidType() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService {
				    @Received(fulfilledByDependencyNamed: "instantiatedA", ofType: "InstantiatedA") let receivedA: ReceivedA
				}
				""",
				expandedSource: """
				@Instantiable
				public struct ExampleService {
				    let receivedA: ReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `ofType` must be a type literal",
						line: 3,
						column: 5,
						severity: .error,
					),
				],
				macros: injectableTestMacros,
			)
		}

		@Test
		func throwsErrorWhenIsExistentialIsAnInvalidType() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService {
				    static let erasedToConcreteExistential = true
				    @Received(fulfilledByDependencyNamed: "receivedA", ofType: ReceivedA.self, erasedToConcreteExistential: erasedToConcreteExistential) let receivedA: AnyReceivedA
				}
				""",
				expandedSource: """
				@Instantiable
				public struct ExampleService {
				    static let erasedToConcreteExistential = true
				    let receivedA: AnyReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `erasedToConcreteExistential` must be a bool literal",
						line: 4,
						column: 5,
						severity: .error,
					),
				],
				macros: injectableTestMacros,
			)
		}

		@Test
		func throwsErrorWhenOnlyIfAvailableIsAnInvalidType() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService {
					static let onlyIfAvailable = true
					@Received(onlyIfAvailable: onlyIfAvailable) let receivedA: AnyReceivedA?
				}
				""",
				expandedSource: """
				@Instantiable
				public struct ExampleService {
					static let onlyIfAvailable = true
					let receivedA: AnyReceivedA?
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The argument `onlyIfAvailable` must be a type literal",
						line: 4,
						column: 2,
						severity: .error,
					),
				],
				macros: injectableTestMacros,
			)
		}

		@Test
		func throwsErrorWhenOnlyIfAvailableIsNotOptional() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService {
					@Received(onlyIfAvailable: true) let receivedA: AnyReceivedA
				}
				""",
				expandedSource: """
				@Instantiable
				public struct ExampleService {
					let receivedA: AnyReceivedA
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "The type of a dependency decorated with `onlyIfAvailable: true` must be marked as optional utilizing the `?` spelling",
						line: 3,
						column: 39,
						severity: .error,
						fixIts: [FixItSpec(message: "Mark the type as optional using `?`")],
					),
				],
				macros: injectableTestMacros,
				applyFixIts: ["Mark the type as optional using `?`"],
				fixedSource: """
				@Instantiable
				public struct ExampleService {
					@Received(onlyIfAvailable: true) let receivedA: AnyReceivedA?
				}
				""",
			)
		}
	}
#endif
