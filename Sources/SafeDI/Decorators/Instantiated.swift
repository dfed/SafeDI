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

/// Marks a SafeDI dependency that is instantiated when its enclosing type is instantiated.
///
/// An example of the macro in use:
///
///     @Instantiated private let dependency: DependencyType
///
/// Note that the access level of the dependency in the above example does not affect the dependency tree – a `private` dependency can still be `@Received` by `@Instantiable`-decorated types further down the dependency tree.
@attached(peer)
public macro Instantiated() = #externalMacro(module: "SafeDIMacros", type: "InjectableMacro")

/// Marks a SafeDI dependency that is instantiated when its enclosing type is instantiated.
///
/// Two examples of the macro in use:
///
///     @Instantiated(fulfilledByType: "ConcreteDependencyType") private let dependency: TypeErasedDependencyType
///
///     @Instantiated(fulfilledByType: "ConcreteView", erasedToConcreteExistential: true) private let dependencyBuilder: Instantiator<AnyView>
///
/// Note that the access level of the dependency in the above example does not affect the dependency tree – a `private` dependency can still be `@Received` by `@Instantiable`-decorated types further down the dependency tree.
///
/// - Parameters:
///   - concreteTypeName: The name of the concrete type that will be instantiated and assigned to this property. This parameter is only required when the decorated property’s type does not match an `@Instantiable` type or its `additionalTypes`. This parameter is particularly useful when working with a type-erased property.
///   - erasedToConcreteExistential: Whether the concrete type is being erased to a concrete existential type – a type that encapsulates a value conforming to a protocol without revealing the underlying type. Concrete type erasing types like `AnyView` fit this description. Set this parameter to `true` to encapsulate the created instance of `concreteTypeName` in a no-label initializer of the property’s type (e.g. `AnyView(ConcreteView())`).
///
///  - SeeAlso: [The Swift Programming Lanaguage’s explanation of existential types](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/opaquetypes/#Boxed-Protocol-Types)
@attached(peer)
public macro Instantiated(
    fulfilledByType concreteTypeName: StaticString,
    erasedToConcreteExistential: Bool = false
) = #externalMacro(module: "SafeDIMacros", type: "InjectableMacro")
