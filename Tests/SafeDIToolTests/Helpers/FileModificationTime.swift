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
import Foundation

/// A file's modification time, exactly as the file system records it. Tests use it to change a
/// file's contents without the change being visible to a check of modification times, or to change
/// only the modification time, without the precision `Date` loses.
struct FileModificationTime: Equatable {
	/// The modification time of the item at `path` itself, not following a symbolic link.
	init(ofItemAtPath path: String) throws {
		var information = stat()
		guard lstat(path, &information) == 0 else {
			throw CocoaError(.fileReadNoSuchFile)
		}
		#if canImport(Darwin)
			let modificationTime = information.st_mtimespec
		#else
			let modificationTime = information.st_mtim
		#endif
		seconds = Int(modificationTime.tv_sec)
		nanoseconds = Int(modificationTime.tv_nsec)
	}

	init(seconds: Int, nanoseconds: Int) {
		self.seconds = seconds
		self.nanoseconds = nanoseconds
	}

	let seconds: Int
	let nanoseconds: Int

	/// Sets the modification time of the item at `path` itself, not following a symbolic link.
	func apply(toItemAtPath path: String) throws {
		// The access time is set too: leaving it as it is takes `UTIME_OMIT`, which Glibc does not
		// expose to Swift, and nothing reads a test file's access time.
		let time = timespec(tv_sec: time_t(seconds), tv_nsec: nanoseconds)
		var times = [time, time]
		guard utimensat(AT_FDCWD, path, &times, AT_SYMLINK_NOFOLLOW) == 0 else {
			throw CocoaError(.fileWriteUnknown)
		}
	}
}
