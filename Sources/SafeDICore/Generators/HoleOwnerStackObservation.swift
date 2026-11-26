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

/// The stack each hole's owner was built with, as `Scope.createScopeGenerator` stacks it where it makes the hole's
/// generator, and as `SeamBuilderParameters` derives it from the path of the hole's site: a generator holds no path, so
/// only the second reaches a signature. Handed to `observer`, which the tests set to check that the two agree, never the
/// tool.
public enum HoleOwnerStackObservation {
	/// A stack of declarations, innermost first: each property, and the concrete type it is built for beside it.
	public struct Stack: Sendable, Equatable {
		public let properties: [Property]
		public let concreteTypes: [TypeDescription]
	}

	/// What `observer` is told. A generator is named by its identity, and the events that make one hand it over too, so
	/// that the observer can keep it alive and no later generator takes its identity.
	public enum Event: Sendable {
		/// Construction made a hole's generator, whose owner was built with `stack`.
		case built(generator: ObjectIdentifier, keepingAlive: any Sendable, stack: Stack)
		/// A tree made again from its first signature pass made a hole's generator again from `original`'s, at the same site.
		case reseated(generator: ObjectIdentifier, keepingAlive: any Sendable, original: ObjectIdentifier)
		/// `SeamBuilderParameters` derived `stack` for the owner of the hole the generator builds, from the site's path.
		case derived(generator: ObjectIdentifier, stack: Stack)
	}

	/// Called with each event, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: (@Sendable (Event) -> Void)?
}
