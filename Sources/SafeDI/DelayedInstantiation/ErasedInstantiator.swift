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

/// A SafeDI dependency designed for the deferred instantiation of a type-erased instance of a
/// type decorated with `@Instantiable`.
///
/// - SeeAlso: `Instantiator`
/// - SeeAlso: `SendableInstantiator`
/// - SeeAlso: `SendableErasedInstantiator`
public final class ErasedInstantiator<ForwardedProperties, Instantiable> {
    /// - Parameter instantiator: A closure that takes `ForwardedProperties` and returns an instance of `Instantiable`.
    public init(_ instantiator: @escaping (ForwardedProperties) -> Instantiable) {
        self.instantiator = instantiator
    }

    /// - Parameter instantiator: A closure that returns an instance of `Instantiable`.
    public init(_ instantiator: @escaping () -> Instantiable) where ForwardedProperties == Void {
        self.instantiator = { _ in instantiator() }
    }

    /// Instantiates and returns a new instance of the `@Instantiable` type, using the provided arguments.
    ///
    /// - Parameter arguments: Arguments required for instantiation.
    /// - Returns: An `Instantiable` instance.
    public func instantiate(_ arguments: ForwardedProperties) -> Instantiable {
        instantiator(arguments)
    }

    /// Instantiates and returns a new instance of the `@Instantiable` type.
    ///
    /// - Returns: An `Instantiable` instance.
    public func instantiate() -> Instantiable where ForwardedProperties == Void {
        instantiator(())
    }

    private let instantiator: (ForwardedProperties) -> Instantiable
}
