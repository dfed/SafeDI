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
/// An extension declaration decorated with `@InstantiableExtension` makes the extended type capable of having properties of other types decorated with `@Instantiable` or `@InstantiableExtension` injected into it. Decorating extensions with `@InstantiableExtension` enables third-party types to be instantiated by the SafeDI system.
/// Usage of this macro requires:
///
/// 1. The extension to implement a method `public static instantiate() -> ExtendedType` that defines the instantiation logic for the externally defined type.
/// 2. The extension to conform the extended type to `Instantiable`.
///
/// Example:
///
///     @InstantiableExtension
///     extension ThirdPartyType: Instantiable {
///         public static func instantiate() -> ThirdPartyType {
///             // Implementation returning an instance of ThirdPartyType
///         }
///     }
///
/// - Parameter additionalTypes: The types (in addition to the type decorated with this macro) of properties that can be decorated with `@Instantiated` and yield a result of this type. The types provided *must* be either superclasses of this type or protocols to which this type conforms.
@attached(member, names: arbitrary)
public macro InstantiableExtension(
    fulfillingAdditionalTypes additionalTypes: [Any.Type] = []
) = #externalMacro(module: "SafeDIMacros", type: "InstantiableMacro")
