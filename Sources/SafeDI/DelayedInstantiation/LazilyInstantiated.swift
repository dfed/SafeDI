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

/// A SafeDI dependency that is instantiated the first time it is requested, and shared from then on.
/// Unlike an `Instantiator`, which creates a new instance on every call to `instantiate()`, a
/// `LazilyInstantiated` creates one instance: every read of `instance` returns the same one.
///
/// Types further down the dependency tree may receive the dependency as `LazilyInstantiated<T>`, which
/// keeps it uninstantiated, or as `T`, which instantiates it when the receiving type is created.
///
/// This type is not `Sendable`: reads of `instance` are not synchronized.
///
/// Guarantees: `instance` is created the first time it is read, by the closure this type was created with,
/// and every later read returns that same instance.
///
/// SafeDI rejects a dependency tree in which creating the instance would require the instance. It does not
/// inspect what initializers do. Do not read `instance` from the initializer of the type that holds this
/// dependency, or from any initializer that runs while the instance is being created, whether directly or
/// through a callback. Doing so violates this type’s contract and produces undefined behavior.
///
/// - SeeAlso: `SendableLazilyInstantiated`
/// - SeeAlso: `Instantiator`
public final class LazilyInstantiated<T> {
	/// - Parameter instantiator: A closure that returns an instance of `T`. Called the first time `instance` is read.
	public init(_ instantiator: @escaping () -> T) {
		state = .uninstantiated(instantiator)
	}

	/// The lazily instantiated instance of `T`.
	/// The first read creates the instance. Every later read returns that same instance.
	public var instance: T {
		switch state {
		case let .instantiated(instance):
			return instance
		case let .uninstantiated(instantiator):
			let instance = instantiator()
			switch state {
			case let .instantiated(instanceReadWhileInstantiating):
				// The instantiator caused `instance` to be read, and that read created and stored an instance.
				// Every read returns that one, so the instance just created is discarded.
				return instanceReadWhileInstantiating
			case .uninstantiated:
				state = .instantiated(instance)
				return instance
			}
		}
	}

	private enum State {
		case uninstantiated(() -> T)
		case instantiated(T)
	}

	private var state: State
}
