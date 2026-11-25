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

	/// SafeDI's macros and wrappers spelled with SafeDI's module name (`@SafeDI.Instantiated`, `SafeDI.Instantiator<T>`)
	/// are read as their bare spellings are. `assertMacroExpansion` expands only a macro spelled as its key in the macros
	/// it is given, so `@SafeDI.Instantiable` itself is expanded by the compiler in `SafeDIToolQualifiedSpellingTests`,
	/// whose fixtures are compiled.
	struct InstantiableMacroQualifiedSpellingTests {
		@Test
		func declaration_fixit_generatesRequiredInitializer_whenDependencyMacrosAreQualifiedBySafeDI() {
			assertMacroExpansion(
				"""
				@Instantiable
				public struct ExampleService: Instantiable {
				    @SafeDI.Instantiated let child: Child
				    @SafeDI.Received let session: Session
				    @SafeDI.Forwarded let user: User
				}
				""",
				expandedSource: """
				public struct ExampleService: Instantiable {
				    @SafeDI.Instantiated let child: Child
				    @SafeDI.Received let session: Session
				    @SafeDI.Forwarded let user: User
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "@Instantiable-decorated type must have an initializer with a parameter for each @Instantiated, @Received, or @Forwarded-decorated property.",
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
				public init(
				child: Child,
				session: Session,
				user: User
				) {
				self.child = child
				self.session = session
				self.user = user
				}

				    @SafeDI.Instantiated let child: Child
				    @SafeDI.Received let session: Session
				    @SafeDI.Forwarded let user: User
				}
				""",
			)
		}

		@Test
		func expansion_warnsThatForwardingIsDeprecated_whenForwardedPropertyIsInstantiatorQualifiedBySafeDI() {
			// `SafeDI.Instantiator<Child>` is the instantiator a bare `Instantiator<Child>` is.
			assertMacroExpansion(
				"""
				public struct ExampleService {
				    @Forwarded let childBuilder: SafeDI.Instantiator<Child>
				}
				""",
				expandedSource: """
				public struct ExampleService {
				    let childBuilder: SafeDI.Instantiator<Child>
				}
				""",
				diagnostics: [
					DiagnosticSpec(
						message: "`@Forwarded` on an `Instantiator` property is deprecated and will be an error in SafeDI 3.0: declare it `@Instantiated` on this type, or receive it with `@Received` from an ancestor that declares it, or forward the value it builds.",
						line: 2,
						column: 34,
						severity: .warning,
					),
				],
				macros: injectableTestMacros,
			)
		}
	}
#endif
