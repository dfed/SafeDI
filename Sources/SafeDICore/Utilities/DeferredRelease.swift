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

#if canImport(Darwin)
	import Darwin
#elseif canImport(Glibc)
	import Glibc
#elseif canImport(Musl)
	import Musl
#endif

/// The part of an object that owns the next level of a tree: the values it holds the last references to, which its
/// deinitialization releases through `DeferredRelease` rather than from within it.
///
/// An object that owns the next level of a tree releases it when it is deinitialized, and each object of that level
/// releases the level below it from its own deinitializer, nested inside the first. A tree as deep as a module has
/// types would nest a deinitializer for each level on the thread's stack, which a concurrency thread's half megabyte
/// cannot hold. An object holds such values in a `let` of this type instead: the slot is never copied and never
/// changes after `init`, so an object that is `Sendable` stays so without a mutable stored property, and when the object
/// is deinitialized the slot moves its values out and hands them to `DeferredRelease`, so that no reference to them
/// outlives the hand-over.
///
/// Swift 6.2.3 and 6.3.3, with `-O` or `-Osize` and no whole-module optimization, never run this type's `deinit` for a
/// slot a class in another file stores: the class's destructor destroys the slot's fields directly, with no diagnostic,
/// so each level is released from within the one above. Whole-module builds (SwiftPM's release configuration,
/// Xcode's Release configuration, rules_swift's `-c opt` and exec configuration) and unoptimized builds run it.
/// SafeDICore is therefore never compiled per file with optimization.
struct DeferredReleaseSlot<Value: RangeReplaceableCollection & Sendable>: ~Copyable, Sendable {
	init(_ value: Value) {
		storage = Storage(value: value)
	}

	deinit {
		// `storage` is noncopyable, so the deinitializer can consume it, and the consumed copy is mutable, so its value
		// can be swapped out: a copyable stored property of a deinitializer's `self` can be neither.
		var storage = consume storage
		var value = Value()
		swap(&value, &storage.value)
		DeferredRelease.release(consume value)
	}

	/// The values the slot holds.
	var value: Value {
		storage.value
	}

	/// Holds `value` in a noncopyable type, which the slot's deinitializer can consume.
	private struct Storage: ~Copyable {
		var value: Value
	}

	private let storage: Storage
}

/// Releases the objects of a tree one at a time.
///
/// A deinitializer hands what it owns to `release(_:)`: the first one on a thread releases it, and the deinitializers
/// that run while it does hand theirs over to it too, so it releases each level after the one above, never inside it.
/// An object whose owned values never change after `init` holds them in a `DeferredReleaseSlot`, which hands them over
/// for it; one that changes them after `init` (`Scope`) swaps them out in its own `deinit` and calls `release(_:)`.
enum DeferredRelease {
	/// Releases `ownedValues`: after the deinitializer that called this returns when this thread is already releasing,
	/// and now otherwise. A caller moves the values out of their storage with `swap` and passes them with `consume`, so
	/// that its own storage keeps no copy of them; a copy a reader still holds keeps what it holds alive, and that copy
	/// releases it.
	static func release(_ ownedValues: consuming some Collection) {
		// Most objects are leaves of their tree, which own nothing to release.
		guard !ownedValues.isEmpty else { return }
		if let pendingReleases = pendingReleasesOfCurrentThread {
			pendingReleases.values.append(consume ownedValues)
		} else {
			let pendingReleases = PendingReleases()
			pendingReleases.values.append(consume ownedValues)
			pthread_setspecific(pendingReleasesKey, Unmanaged.passUnretained(pendingReleases).toOpaque())
			// Each value released here can hand values over, which this loop releases in turn.
			while pendingReleases.values.popLast() != nil {}
			pthread_setspecific(pendingReleasesKey, nil)
		}
	}

	/// The values handed over on one thread while it releases.
	private final class PendingReleases {
		var values = [Any]()
	}

	/// The values the current thread is releasing, or `nil` when it is not releasing any.
	private static var pendingReleasesOfCurrentThread: PendingReleases? {
		pthread_getspecific(pendingReleasesKey).map {
			Unmanaged<PendingReleases>.fromOpaque($0).takeUnretainedValue()
		}
	}

	/// The key under which each thread keeps its `PendingReleases` while it releases.
	private static let pendingReleasesKey: pthread_key_t = {
		var key = pthread_key_t()
		pthread_key_create(&key, nil)
		return key
	}()
}
