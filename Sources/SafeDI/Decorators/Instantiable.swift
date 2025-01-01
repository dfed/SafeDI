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

/// Marks a type as capable of being instantiated by the SafeDI system.
///
/// A `class`, `struct`, or `actor` type declaration decorated with `@Instantiable` makes the type capable of having properties of other `@Instantiable`-decorated types injected into its initializer.
///
/// Example:
///
///     @Instantiable
///     public final class FirstPartyType: Instantiable {
///         public init(createdDependency: Dependency, receivedDependency: Dependency) {
///             self.createdDependency = createdDependency
///             self.receivedDependency = receivedDependency
///         }
///
///         /// A dependency instance that is instantiated when the `FirstPartyType` is instantiated.
///         @Instantiated private let createdDependency: Dependency
///         /// A dependency instance that was instantiated further up the dependency tree.
///         @Received private let receivedDependency: Dependency
///     }
///
/// An extension declaration decorated with `@Instantiable` makes the extended type capable of having properties of other `@Instantiable`-decorated types injected into it. Decorating extensions with `@Instantiable` enables third-party types to be instantiated by the SafeDI system.
/// Usage of this macro requires the extension to implement a method `public static func instantiate() -> ExtendedType` that defines the instantiation logic for the externally defined type.
///
/// Example:
///
///     @Instantiable
///     extension ThirdPartyType: Instantiable {
///         public static func instantiate() -> ThirdPartyType {
///             // Implementation returning an instance of ThirdPartyType
///         }
///     }
///
/// - Parameters:
///   - isRoot: Whether the decorated type represents a root of a dependency tree.
///   - additionalTypes: The types (in addition to the type decorated with this macro) of properties that can be decorated with `@Instantiated` and yield a result of this type. The types provided *must* be either superclasses of this type or protocols to which this type conforms.
///   - conformsElsewhere: Whether the decorated type already conforms to the `Instantiable` protocol elsewhere. If set to `true`, the macro does not enforce that this declaration conforms to `Instantiable`.
@attached(member, names: named(ForwardedProperties))
public macro Instantiable(
    isRoot: Bool = false,
    fulfillingAdditionalTypes additionalTypes: [Any.Type] = [],
    conformsElsewhere: Bool = false
) = #externalMacro(module: "SafeDIMacros", type: "InstantiableMacro")

/// A type that can be instantiated with runtime-injected properties.
public protocol Instantiable {
    /// The forwarded properties required to instantiate the type.
    /// Defaults to `Void`.
    associatedtype ForwardedProperties = Void
}
