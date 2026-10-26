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

/// The modification times of the file at a path, exactly as the file system records them, which
/// `scan` stores for each input it reads and `generate` compares to decide whether scan's cache
/// still describes the inputs.
///
/// Recorded with `lstat` and, for a symbolic link, `stat` as well: scan reads a file's contents
/// through the link, so the target's time reveals an edit, and the link's own time reveals that the
/// link was pointed elsewhere. Times are kept as whole seconds and nanoseconds rather than a `Date`,
/// whose floating-point seconds would make two reads of the same time compare unequal. A missing
/// file has no times. A system call per path costs about a microsecond, several times less than
/// Foundation's resource values, and `generate` reads every input of every module the target
/// depends on.
struct FileModificationStamp: Codable, Equatable {
	init(ofFileAtPath path: String) {
		var linkInformation = stat()
		guard lstat(path, &linkInformation) == 0 else {
			times = []
			return
		}
		var times = Self.modificationTime(of: linkInformation)
		var targetInformation = stat()
		if linkInformation.st_mode & S_IFMT == S_IFLNK, stat(path, &targetInformation) == 0 {
			times += Self.modificationTime(of: targetInformation)
		}
		self.times = times
	}

	init(from decoder: any Decoder) throws {
		times = try decoder.singleValueContainer().decode([Int64].self)
	}

	func encode(to encoder: any Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(times)
	}

	// MARK: Private

	/// Seconds and nanoseconds of each modification time recorded, in the order recorded. Kept as one
	/// flat array so the thousands of stamps a cache holds stay small to write and read.
	private let times: [Int64]

	private static func modificationTime(of information: stat) -> [Int64] {
		#if canImport(Darwin)
			let modificationTime = information.st_mtimespec
		#else
			let modificationTime = information.st_mtim
		#endif
		return [Int64(modificationTime.tv_sec), Int64(modificationTime.tv_nsec)]
	}
}
