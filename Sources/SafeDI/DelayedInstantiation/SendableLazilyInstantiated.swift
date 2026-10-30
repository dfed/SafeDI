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

import Synchronization

/// A SafeDI dependency that is instantiated the first time it is requested, and shared from then on.
/// Unlike a `SendableInstantiator`, which creates a new instance on every call to `instantiate()`, a
/// `SendableLazilyInstantiated` creates one instance: every read of `instance` returns the same one.
///
/// Types further down the dependency tree may receive the dependency as `SendableLazilyInstantiated<T>`,
/// which keeps it uninstantiated, or as `T`, which instantiates it when the receiving type is created.
///
/// This type can be shared across concurrency domains. The instance is created exactly once, while a lock
/// is held: a read of `instance` that races with the first one waits for it and receives the same instance.
///
/// Guarantees: `instance` is created exactly once, by the closure this type was created with, and every
/// read, from any concurrency domain, returns that same instance.
///
/// SafeDI creates the instance in a `@Sendable` function, so every initializer that function calls, anywhere in
/// the instance’s subtree, must be callable synchronously outside any actor: a `@MainActor` class with a
/// `nonisolated init` is fine, but a `@MainActor init` is not, whatever the type’s own isolation. What the
/// instance’s type, and every type in its subtree, receives from outside it must be `Sendable` too, even when that
/// type is itself `Sendable`, such as an actor. Where an initializer cannot be `nonisolated`, use `LazilyInstantiated`.
///
/// SafeDI rejects a dependency tree in which creating the instance would require the instance. It does not
/// inspect what initializers do. Do not read `instance` from the initializer of the type that declares the
/// `SendableLazilyInstantiated` property, or from any initializer that runs while the instance is being created,
/// whether directly or through a callback. Doing so violates this type’s contract and produces undefined behavior.
///
/// - SeeAlso: `LazilyInstantiated`
/// - SeeAlso: `SendableInstantiator`
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
public final class SendableLazilyInstantiated<T: Sendable>: Sendable {
	/// - Parameter instantiator: A closure that returns an instance of `T`. Called at most once.
	public init(_ instantiator: @escaping @Sendable () -> T) {
		state = Mutex(.uninstantiated(instantiator))
	}

	/// The lazily instantiated instance of `T`.
	/// The first read creates the instance. Every later read returns that same instance.
	public var instance: T {
		state.withLock { state in
			switch state {
			case let .instantiated(instance):
				return instance
			case let .uninstantiated(instantiator):
				let instance = instantiator()
				state = .instantiated(instance)
				return instance
			}
		}
	}

	private enum State {
		case uninstantiated(@Sendable () -> T)
		case instantiated(T)
	}

	private let state: Mutex<State>
}
