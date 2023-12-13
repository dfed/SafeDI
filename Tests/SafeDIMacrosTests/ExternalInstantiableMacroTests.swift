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

final class ExternalInstantiableMacroTests: XCTestCase {
    let testMacros: [String: Macro.Type] = [
        ExternalInstantiableVisitor.macroName: ExternalInstantiableMacro.self,
        Dependency.Source.instantiated.rawValue: InjectableMacro.self,
        Dependency.Source.received.rawValue: InjectableMacro.self,
        Dependency.Source.forwarded.rawValue: InjectableMacro.self,
    ]

    // MARK: XCTestCase

    override func invokeTest() {
        withMacroTesting(macros: testMacros) {
            super.invokeTest()
        }
    }

    // MARK: Error tests

    func test_throwsErrorWhenOnActor() {
        assertMacro {
            """
            @ExternalInstantiable
            public actor ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable
            ┬────────────────────
            ╰─ 🛑 @ExternalInstantiable must decorate an extension
            public actor ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_throwsErrorWhenOnClass() {
        assertMacro {
            """
            @ExternalInstantiable
            public final class ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable
            ┬────────────────────
            ╰─ 🛑 @ExternalInstantiable must decorate an extension
            public final class ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_throwsErrorWhenOnEnum() {
        assertMacro {
            """
            @ExternalInstantiable
            public enum ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable
            ┬────────────────────
            ╰─ 🛑 @ExternalInstantiable must decorate an extension
            public enum ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_throwsErrorWhenOnProtocol() {
        assertMacro {
            """
            @ExternalInstantiable
            public protocol ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable
            ┬────────────────────
            ╰─ 🛑 @ExternalInstantiable must decorate an extension
            public protocol ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_throwsErrorWhenOnStruct() {
        assertMacro {
            """
            @ExternalInstantiable
            public struct ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable
            ┬────────────────────
            ╰─ 🛑 @ExternalInstantiable must decorate an extension
            public struct ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_throwsErrorWhenFulfillingAdditionalTypesIsAPropertyReference() {
        assertMacro {
            """
            let fulfillingAdditionalTypes: [Any.Type] = [AnyObject.self]
            @ExternalInstantiable(fulfillingAdditionalTypes: fulfillingAdditionalTypes)
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            let fulfillingAdditionalTypes: [Any.Type] = [AnyObject.self]
            @ExternalInstantiable(fulfillingAdditionalTypes: fulfillingAdditionalTypes)
            ┬──────────────────────────────────────────────────────────────────────────
            ╰─ 🛑 The argument `fulfillingAdditionalTypes` must be an inlined array
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_throwsErrorWhenFulfillingAdditionalTypesIsAClosure() {
        assertMacro {
            """
            @ExternalInstantiable(fulfillingAdditionalTypes: { [AnyObject.self] }())
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable(fulfillingAdditionalTypes: { [AnyObject.self] }())
            ┬───────────────────────────────────────────────────────────────────────
            ╰─ 🛑 The argument `fulfillingAdditionalTypes` must be an inlined array
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_throwsErrorWhenMoreThanOneInstantiateMethod() {
        assertMacro {
            """
            @ExternalInstantiable
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
                public static func instantiate(user: User) -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable
            ┬────────────────────
            ╰─ 🛑 @ExternalInstantiable-decorated extension must have a single `instantiate()` method
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
                public static func instantiate(user: User) -> ExampleService { fatalError() }
            }
            """
        }
    }

    // MARK: FixIt tests

    func test_fixit_addsFixitWhenInstantiateMethodMissing() {
        assertMacro {
            """
            @ExternalInstantiable
            extension ExampleService {
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable
            extension ExampleService {
                                      ╰─ 🛑 @ExternalInstantiable-decorated extension of ExampleService must have a `public static func instantiate() -> ExampleService` method
                                         ✏️ Add `public static func instantiate() -> ExampleService` method
            }
            """
        } fixes: {
            """
            @ExternalInstantiable
            extension ExampleService {
            public static func instantiate() -> ExampleService
            {}


            public static func instantiate() -> ExampleService
            {}
            """ // This is correct in Xcode: we only write the `instantiate()` method once.
        }
    }

    func test_fixit_addsFixitWhenInstantiateMethodIsNotPublic() {
        assertMacro {
            """
            @ExternalInstantiable
            extension ExampleService {
                static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable
            extension ExampleService {
                static func instantiate() -> ExampleService { fatalError() }
                ┬───────────────────────────────────────────────────────────
                ╰─ 🛑 @ExternalInstantiable-decorated extension must have an `instantiate()` method that is both `public` and `static`
                   ✏️ Set `public static` modifiers
            }
            """
        } fixes: {
            """
            @ExternalInstantiable
            extension ExampleService {
            public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } expansion: {
            """
            extension ExampleService {
            public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_fixit_addsFixitWhenInstantiateMethodIsNotStatic() {
        assertMacro {
            """
            @ExternalInstantiable
            extension ExampleService {
                public func instantiate() -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable
            extension ExampleService {
                public func instantiate() -> ExampleService { fatalError() }
                ┬───────────────────────────────────────────────────────────
                ╰─ 🛑 @ExternalInstantiable-decorated extension must have an `instantiate()` method that is both `public` and `static`
                   ✏️ Set `public static` modifiers
            }
            """
        } fixes: {
            """
            @ExternalInstantiable
            extension ExampleService {
            public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } expansion: {
            """
            extension ExampleService {
            public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_fixit_addsFixitWhenInstantiateMethodIsNotStaticOrPublic() {
        assertMacro {
            """
            @ExternalInstantiable
            extension ExampleService {
                func instantiate() -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable
            extension ExampleService {
                func instantiate() -> ExampleService { fatalError() }
                ┬────────────────────────────────────────────────────
                ╰─ 🛑 @ExternalInstantiable-decorated extension must have an `instantiate()` method that is both `public` and `static`
                   ✏️ Set `public static` modifiers
            }
            """
        } fixes: {
            """
            @ExternalInstantiable
            extension ExampleService {
            public static 
                func instantiate() -> ExampleService { fatalError() }
            }
            """
        } expansion: {
            """
            extension ExampleService {
            public static 
                func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_fixit_addsFixitWhenInstantiateMethodReturnsIncorrectType() {
        assertMacro {
            """
            @ExternalInstantiable
            extension ExampleService {
                public static func instantiate() -> OtherExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable
            extension ExampleService {
                public static func instantiate() -> OtherExampleService { fatalError() }
                ┬───────────────────────────────────────────────────────────────────────
                ╰─ 🛑 @ExternalInstantiable-decorated extension's `instantiate()` method must return the same type as the extended type
                   ✏️ Make `instantiate()`'s return type the same as the extended type
            }
            """
        } fixes: {
            """
            @ExternalInstantiable
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } expansion: {
            """
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_fixit_addsFixitWhenInstantiateMethodIsAsync() {
        assertMacro {
            """
            @ExternalInstantiable
            extension ExampleService {
                public static func instantiate() async -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable
            extension ExampleService {
                public static func instantiate() async -> ExampleService { fatalError() }
                ┬────────────────────────────────────────────────────────────────────────
                ╰─ 🛑 @ExternalInstantiable-decorated extension's `instantiate()` method must not throw or be async
                   ✏️ Remove effect specifiers
            }
            """
        } fixes: {
            """
            @ExternalInstantiable
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } expansion: {
            """
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_fixit_addsFixitWhenInstantiateMethodThrows() {
        assertMacro {
            """
            @ExternalInstantiable
            extension ExampleService {
                public static func instantiate() throws -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable
            extension ExampleService {
                public static func instantiate() throws -> ExampleService { fatalError() }
                ┬─────────────────────────────────────────────────────────────────────────
                ╰─ 🛑 @ExternalInstantiable-decorated extension's `instantiate()` method must not throw or be async
                   ✏️ Remove effect specifiers
            }
            """
        } fixes: {
            """
            @ExternalInstantiable
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } expansion: {
            """
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_fixit_addsFixitWhenInstantiateMethodIsAsyncAndThrows() {
        assertMacro {
            """
            @ExternalInstantiable
            extension ExampleService {
                public static func instantiate() async throws -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable
            extension ExampleService {
                public static func instantiate() async throws -> ExampleService { fatalError() }
                ┬───────────────────────────────────────────────────────────────────────────────
                ╰─ 🛑 @ExternalInstantiable-decorated extension's `instantiate()` method must not throw or be async
                   ✏️ Remove effect specifiers
            }
            """
        } fixes: {
            """
            @ExternalInstantiable
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } expansion: {
            """
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_fixit_addsFixitWhenInstantiateMethodHasGenericParameter() {
        assertMacro {
            """
            @ExternalInstantiable
            extension ExampleService {
                public static func instantiate<T>() -> ExampleService { fatalError() }
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable
            extension ExampleService {
                public static func instantiate<T>() -> ExampleService { fatalError() }
                ┬─────────────────────────────────────────────────────────────────────
                ╰─ 🛑 @ExternalInstantiable-decorated extension's `instantiate()` method must not have a generic parameter
                   ✏️ Remove generic parameter
            }
            """
        } fixes: {
            """
            @ExternalInstantiable
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        } expansion: {
            """
            extension ExampleService {
                public static func instantiate() -> ExampleService { fatalError() }
            }
            """
        }
    }

    func test_fixit_addsFixitWhenInstantiateMethodHasGenericWhereClause() {
        assertMacro {
            """
            @ExternalInstantiable
            extension Array {
                public static func instantiate() -> Array where Element == String { fatalError() }
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable
            extension Array {
                public static func instantiate() -> Array where Element == String { fatalError() }
                ┬─────────────────────────────────────────────────────────────────────────────────
                ╰─ 🛑 @ExternalInstantiable-decorated extension must not have a generic `where` clause
                   ✏️ Remove generic `where` clause
            }
            """
        } fixes: {
            """
            @ExternalInstantiable
            extension Array {
                public static func instantiate() -> Array { fatalError() }
            }
            """
        } expansion: {
            """
            extension Array {
                public static func instantiate() -> Array { fatalError() }
            }
            """
        }
    }

    func test_fixit_addsFixitWhenExtensionHasGenericWhereClause() {
        assertMacro {
            """
            @ExternalInstantiable
            extension Array where Element == String {
                public static func instantiate() -> Array { fatalError() }
            }
            """
        } diagnostics: {
            """
            @ExternalInstantiable
            ┬────────────────────
            ╰─ 🛑 @ExternalInstantiable-decorated extension must not have a generic `where` clause
               ✏️ Remove generic `where` clause
            extension Array where Element == String {
                public static func instantiate() -> Array { fatalError() }
            }
            """
        } fixes: {
            """
            @ExternalInstantiable
            extension Array {
                public static func instantiate() -> Array { fatalError() }
            }
            """
        } expansion: {
            """
            extension Array {
                public static func instantiate() -> Array { fatalError() }
            }
            """
        }
    }
}
#endif
