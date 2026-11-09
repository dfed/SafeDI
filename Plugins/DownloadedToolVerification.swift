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

import Foundation

// The `InstallSafeDITool` command plugin compiles this file, and so does the
// plugin test target, through symbolic links. It imports nothing from
// `PackagePlugin`, so the test target can compile it.

// CryptoKit ships with macOS, where the installer runs. Linux, where the test
// target also compiles, has no CryptoKit, and the installer downloads nothing
// there.
#if canImport(CryptoKit)
	import CryptoKit

	/// Checks that the file at `fileURL` has the SHA-256 `expectedSHA256`, a
	/// lowercase hexadecimal digest as `shasum -a 256` prints it.
	/// - Throws: `DownloadedToolChecksumMismatchError` when the file's digest
	///   differs, or the error reading the file.
	func verifySHA256(
		ofFileAt fileURL: URL,
		downloadedFrom downloadURL: URL,
		matches expectedSHA256: String,
	) throws {
		let actualSHA256 = try sha256(ofFileAt: fileURL)
		guard actualSHA256 == expectedSHA256 else {
			throw DownloadedToolChecksumMismatchError(
				url: downloadURL,
				expectedSHA256: expectedSHA256,
				actualSHA256: actualSHA256,
			)
		}
	}

	/// The SHA-256 of the file at `fileURL`, as lowercase hexadecimal.
	func sha256(ofFileAt fileURL: URL) throws -> String {
		let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
		return SHA256.hash(data: data)
			.map { byte in
				let hexadecimal = String(byte, radix: 16)
				return byte < 0x10 ? "0\(hexadecimal)" : hexadecimal
			}
			.joined()
	}
#endif

struct DownloadedToolChecksumMismatchError: Error, CustomStringConvertible {
	let url: URL
	let expectedSHA256: String
	let actualSHA256: String

	var description: String {
		"The SafeDITool downloaded from \(url.absoluteString) has SHA-256 \(actualSHA256), but the SafeDI release this project depends on publishes SafeDITool with SHA-256 \(expectedSHA256), so it was deleted rather than installed. The download was corrupted or replaced on its way here; run the command again to retry. If the hashes differ again, the file the release offers is not the one SafeDI published: do not install it by hand."
	}
}
