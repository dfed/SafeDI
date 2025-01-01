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

/// Marks a SafeDI dependency that is instantiated or forwarded by an `@Instantiable` instance higher up in the dependency tree.
///
/// An example of the macro in use:
///
///     @Received private let dependency: DependencyType
///
/// Note that the access level of the dependency in the above example does not affect the dependency tree – a `private` dependency can still be `@Received` by `@Instantiable`-decorated types further down the dependency tree.
@attached(peer)
public macro Received() = #externalMacro(module: "SafeDIMacros", type: "InjectableMacro")

/// Marks a SafeDI dependency that is instantiated or forwarded by an `@Instantiable` instance higher up in the dependency tree whose name and/or type is being changed from the dependency‘s initial declaration.
///
/// Two examples of the macro in use:
///
///     @Received(fulfilledByDependencyNamed: "dependency", ofType: "DependencyType") private let renamedDependency: DependencySuperType
///
///     @Received(fulfilledByDependencyNamed: "dependency", ofType: "DependencyType", erasedToConcreteExistential: true) private let typeErasedDependency: AnyDependencyType
///
/// Note that the access level of the dependency in the above example does not affect the dependency tree – a `private` dependency can still be `@Received` by `@Instantiable`-decorated types further down the dependency tree.
///
/// Renamed and retyped dependencies can be `@Received` by their new name and type by `@Instantiable` types further down the dependency tree.
///
/// - Parameters:
///   - fulfilledByDependencyNamed: The name of the property belonging to an `@Instantiable` instance higher up in the dependency tree whose name and/or type is being changed from the dependency‘s initial declaration.
///   - concreteType: The type of the property belonging to an `@Instantiable` instance higher up in the dependency tree whose name and/or type is being changed from the dependency‘s initial declaration.
///   - erasedToConcreteExistential: Whether the concrete type is being erased to a concrete existential type – a type that encapsulates a value conforming to a protocol without revealing the underlying type. Set this parameter to `true` to encapsulate the renamed or retyped instance of `concreteType` in a no-label initializer of the property’s type (e.g. `AnyDependencyType(dependency)`).
///
///  - SeeAlso: [The Swift Programming Lanaguage’s explanation of existential types](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/opaquetypes/#Boxed-Protocol-Types)
@attached(peer)
public macro Received<T>(
    fulfilledByDependencyNamed: StaticString,
    ofType concreteType: T.Type,
    erasedToConcreteExistential: Bool = false
) = #externalMacro(module: "SafeDIMacros", type: "InjectableMacro")
