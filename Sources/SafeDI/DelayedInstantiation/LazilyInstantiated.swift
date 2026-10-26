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
/// - SeeAlso: `SendableLazilyInstantiated`
/// - SeeAlso: `Instantiator`
public final class LazilyInstantiated<T> {
	/// - Parameter instantiator: A closure that returns an instance of `T`. Called at most once.
	public init(_ instantiator: @escaping () -> T) {
		self.instantiator = instantiator
	}

	/// The lazily instantiated instance of `T`.
	/// The first read creates the instance. Every later read returns that same instance.
	public var instance: T {
		if let instantiatedInstance {
			return instantiatedInstance
		} else {
			guard let instantiator else { fatalError("`\(T.self)` was requested while it was being instantiated. A type created during the instantiation of `\(T.self)` must not read `LazilyInstantiated<\(T.self)>.instance` before that instantiation completes.") }
			// Forget the instantiator before calling it. A read of `instance` made while it runs then finds
			// nothing to call, and everything the instantiator captured is released once it returns.
			self.instantiator = nil
			let instance = instantiator()
			instantiatedInstance = instance
			return instance
		}
	}

	private var instantiator: (() -> T)?
	private var instantiatedInstance: T?
}
