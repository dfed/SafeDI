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

/// Releases the objects of a tree one at a time.
///
/// An object that owns the next level of a tree releases it when it is deinitialized, and each object of that level
/// releases the level below it from its own deinitializer, nested inside the first. A tree as deep as a module has
/// types would nest a deinitializer for each level on the thread's stack, which a concurrency thread's half megabyte
/// cannot hold. A deinitializer hands what it owns to `release(_:)` instead: the first one on a thread releases it,
/// and the deinitializers that run while it does hand theirs over to it too, so it releases each level after the one
/// above, never inside it.
enum DeferredRelease {
	/// Releases `ownedValues`, which must hold the last references to what they hold: after the deinitializer that
	/// called this returns when this thread is already releasing, and now otherwise. A caller moves the values out
	/// of their storage with `swap` and passes them with `consume`, so that no copy of them outlives this call.
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
