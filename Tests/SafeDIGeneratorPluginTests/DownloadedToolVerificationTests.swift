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

// The installer hashes with CryptoKit, which only Apple platforms have; it downloads nothing elsewhere.
#if canImport(CryptoKit)
	import Foundation
	import Testing

	struct DownloadedToolVerificationTests {
		/// The SHA-256 of the three bytes `abc`, the first test vector of FIPS 180-2. Its sixth byte is `0x01`, so a
		/// match also shows each byte is spelled with two digits.
		private static let abcSHA256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
		/// The SHA-256 of the two bytes `ab`.
		private static let abSHA256 = "fb8e20fc2e4c3f248c60c39bd652f3c1347298bb977b8b4d5903b85055620603"

		private static let downloadURL = URL(string: "https://example.com/releases/download/1.0.0/SafeDITool-macos-arm64")

		@Test
		func verifySHA256_succeeds_whenFileHasExpectedDigest() throws {
			let fileURL = try Self.temporaryFile(containing: "abc")
			defer { try? FileManager.default.removeItem(at: fileURL) }

			try verifySHA256(ofFileAt: fileURL, downloadedFrom: #require(Self.downloadURL), matches: Self.abcSHA256)
		}

		@Test
		func verifySHA256_throwsErrorNamingBothDigests_whenFileHasAnotherDigest() throws {
			let fileURL = try Self.temporaryFile(containing: "ab")
			defer { try? FileManager.default.removeItem(at: fileURL) }
			let downloadURL = try #require(Self.downloadURL)

			let error = try #require(throws: DownloadedToolChecksumMismatchError.self) {
				try verifySHA256(ofFileAt: fileURL, downloadedFrom: downloadURL, matches: Self.abcSHA256)
			}
			#expect(error.expectedSHA256 == Self.abcSHA256)
			#expect(error.actualSHA256 == Self.abSHA256)
			#expect(error.description == "The SafeDITool downloaded from https://example.com/releases/download/1.0.0/SafeDITool-macos-arm64 has SHA-256 \(Self.abSHA256), but the SafeDI release this project depends on publishes SafeDITool with SHA-256 \(Self.abcSHA256), so it was deleted rather than installed. The download was corrupted or replaced on its way here; run the command again to retry. If the hashes differ again, the file the release offers is not the one SafeDI published: do not install it by hand.")
		}

		private static func temporaryFile(containing contents: String) throws -> URL {
			let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
			try Data(contents.utf8).write(to: fileURL)
			return fileURL
		}
	}
#endif
