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

/// How `generate --split-combined-output-mocks` spreads a module's mocks over its mock files.
///
/// A mock's file follows from the mocked type's name alone, so an edit that changes one mock rewrites only that mock's
/// file, and a build that compiles only the files whose bytes changed recompiles one file of mocks rather than all of
/// them. Placing mocks by size would balance the files better, but an edit that changes one mock's size would move
/// other mocks between files and rewrite most of them.
enum MockFileDistribution {
	/// The number of mock files. Fixed, so that a build system that declares its outputs before `generate` runs, as
	/// Bazel does, can name them without knowing how many mocks a module has, and `bazel/safedi.bzl` declares this many.
	/// Measured on 2,401 mocks under an incremental debug build at 4 jobs, 32 files made an edit to one mock 2.4 times as
	/// fast as one file, more than 4 or 8 files did, and 32 mostly empty files added about 0.3 seconds to a clean build of
	/// a module of 10 mocks.
	static let fileCount = 32

	/// The index, from 0, of the file that holds the mock of the type spelled `typeName`: a 64-bit FNV-1a hash of the
	/// spelling's UTF-8 bytes, which is the same on every platform and in every process, modulo `fileCount`.
	static func fileIndex(ofMockOfTypeSpelled typeName: String) -> Int {
		var hash: UInt64 = 0xCBF29CE484222325
		for byte in typeName.utf8 {
			hash ^= UInt64(byte)
			hash = hash &* 0x00000100000001B3
		}
		return Int(hash % UInt64(fileCount))
	}
}
