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

import SafeDICore
import Synchronization
import Testing

extension HoleOwnerStackObservation {
	/// The observer the test executors install: `checkingDerivedStacks(handingOn:)` where the platform has `Mutex`, which
	/// every platform the tests run on has, and otherwise `enclosingObserver` alone.
	static func checkingDerivedStacksWherePossible(handingOn enclosingObserver: (@Sendable (Event) -> Void)?) -> (@Sendable (Event) -> Void)? {
		if #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) {
			checkingDerivedStacks(handingOn: enclosingObserver)
		} else {
			enclosingObserver
		}
	}

	/// An observer that records an issue wherever the stack `SeamBuilderParameters` derives for a hole's owner from the
	/// site's path differs from the stack construction built the owner with, or where it derives one for a hole generator
	/// whose construction it was not told of, then hands each event to `enclosingObserver`. Each call makes a table of its
	/// own, which keeps every hole generator it is told of alive while the observer lives, so no later generator takes an
	/// identity the table holds.
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
	static func checkingDerivedStacks(handingOn enclosingObserver: (@Sendable (Event) -> Void)?) -> @Sendable (Event) -> Void {
		let table = HoleOwnerStackTable()
		return { event in
			if let mismatch = table.record(event) {
				Issue.record(Comment(rawValue: mismatch))
			}
			enclosingObserver?(event)
		}
	}
}

/// The stacks construction built each hole generator's owner with, by the generator's identity, shared by the tasks of
/// one run.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
private final class HoleOwnerStackTable: Sendable {
	/// Records `event`, and returns a description of the mismatch it shows, if any.
	func record(_ event: HoleOwnerStackObservation.Event) -> String? {
		entries.withLock { entries in
			switch event {
			case let .built(generator, keepingAlive, stack):
				entries[generator] = Entry(keepingAlive: keepingAlive, stack: stack)
				return nil
			case let .reseated(generator, keepingAlive, original):
				guard let originalEntry = entries[original] else {
					return "A hole generator was made again from one whose construction was not observed."
				}
				entries[generator] = Entry(keepingAlive: keepingAlive, stack: originalEntry.stack)
				return nil
			case let .derived(generator, derived):
				guard let built = entries[generator]?.stack else {
					return "A stack was derived for the owner of a hole generator whose construction was not observed: \(Self.spelled(derived))"
				}
				guard derived != built else { return nil }
				return "The stack derived for a hole’s owner from its site’s path differs from the stack construction built it with.\nDerived: \(Self.spelled(derived))\nBuilt: \(Self.spelled(built))"
			}
		}
	}

	private struct Entry: Sendable {
		let keepingAlive: any Sendable
		let stack: HoleOwnerStackObservation.Stack
	}

	private static func spelled(_ stack: HoleOwnerStackObservation.Stack) -> String {
		zip(stack.properties, stack.concreteTypes).map { "\($0.asSource) (\($1.asSource))" }.joined(separator: ", ")
	}

	private let entries = Mutex([ObjectIdentifier: Entry]())
}
