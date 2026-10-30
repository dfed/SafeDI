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

/// A SafeDI dependency responsible for the deferred instantiation of an `@Instantiable`-decorated type.
/// This class facilitates the delayed creation of an `@Instantiable` instance, making it particularly
/// useful in scenarios where immediate instantiation is not necessary or desirable. `Instantiator`
/// facilitates control over memory usage and enables just-in-time instantiation.
///
/// This instantiator can be used to instantiate types across concurrency domains.
///
/// SafeDI creates each instance in a `@Sendable` function, so every initializer that function calls, anywhere in
/// the instance’s subtree, must be callable synchronously outside any actor, as must an extension’s
/// `instantiate(…)` and a hand-written mock method that a generated mock calls: a `@MainActor` class with a
/// `nonisolated init` is fine when its stored properties are `Sendable`, but a `@MainActor init` is not, whatever
/// the type’s own isolation. What the instance’s type, and every type in its subtree, receives from outside it must
/// be `Sendable` too, even when that type is itself `Sendable`, such as an actor; in a generated mock, so must the
/// subtree’s labeled default-valued initializer arguments and the dependencies in it that `mock()` takes as parameters.
///
/// - SeeAlso: `Instantiator`
/// - SeeAlso: `ErasedInstantiator`
/// - SeeAlso: `SendableErasedInstantiator`
public final class SendableInstantiator<T: Instantiable>: Sendable {
	/// - Parameter instantiator: A closure that takes `T.ForwardedProperties` and returns an instance of `T`.
	public init(_ instantiator: @escaping @Sendable (T.ForwardedProperties) -> T) {
		self.instantiator = instantiator
	}

	/// - Parameter instantiator: A closure that returns an instance of `T`.
	public init(_ instantiator: @escaping @Sendable () -> T) where T.ForwardedProperties == Void {
		self.instantiator = { _ in instantiator() }
	}

	/// Instantiates and returns a new instance of the `@Instantiable` type.
	/// - Returns: An instance of `T`.
	public func instantiate(_ forwardedProperties: T.ForwardedProperties) -> T {
		instantiator(forwardedProperties)
	}

	/// Instantiates and returns a new instance of the `@Instantiable` type.
	/// - Returns: An instance of `T`.
	public func instantiate() -> T where T.ForwardedProperties == Void {
		instantiator(())
	}

	private let instantiator: @Sendable (T.ForwardedProperties) -> T
}
