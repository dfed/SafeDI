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

/// A SafeDI dependency responsible for the lazy instantiation of an `@Instantiable` type.
/// This class facilitates the delayed creation of an `@Instantiable` instance, making it particularly
/// useful in scenarios where immediate instantiation is not necessary or desirable. `LazyInstantiator`
/// facilitates control over memory usage and enables just-in-time instantiation. Instantiation is thread-safe.
///
/// - SeeAlso: `LazyForwardingInstantiator`
public final class LazyInstantiator<InstantiableType> {
    /// - Parameter instantiator: A closure that returns an instance of `InstantiableType`.
    public init(_ instantiator: @escaping () -> InstantiableType) {
        self.instantiator = instantiator
    }

    /// Instantiates and returns a new instance of the `@Instantiable` type.
    /// - Returns: An `InstantiableType` instance.
    public func instantiate() -> InstantiableType {
        instantiator()
    }

    private let instantiator: () -> InstantiableType
}
