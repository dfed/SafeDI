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
import Testing

/// Every Foundation or C call that normalizes or resolves a path belongs in `FilePathSpelling.swift`, so no comparison
/// pairs two spellings made by different rules. This target compiles the plugin's comment and string stripping, so
/// the check reads only code: a comment or string that names a call does not count. It does not look for paths made
/// relative by hand.
struct PathSpellingCallTests {
	@Test
	func sources_normalizeAndResolvePathsOnlyInFilePathSpelling() throws {
		let repositoryRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let pathSpellingCalls = try [
			#"\bstandardizedFileURL\b"#,
			#"\.standardized\b"#,
			#"\bstandardize\s*\("#,
			#"\bstandardizingPath\b"#,
			#"\bresolvingSymlinksInPath\b"#,
			#"\bcanonicalPathKey\b"#,
			#"\bdestinationOfSymbolicLink\b"#,
			#"\brealpath\s*\("#,
		].map { try Regex($0) }
		var checkedFileNames = Set<String>()
		var violations = [String]()
		for directory in ["Sources", "Plugins"] {
			let enumerator = try #require(FileManager.default.enumerator(
				at: repositoryRoot.appendingPathComponent(directory),
				includingPropertiesForKeys: [.isSymbolicLinkKey],
			))
			for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
				// A symbolic link compiles a file that is checked where it lives.
				guard try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { continue }
				checkedFileNames.insert(fileURL.lastPathComponent)
				guard fileURL.lastPathComponent != "FilePathSpelling.swift" else { continue }
				let code = try stripSwiftCommentsAndStrings(from: String(contentsOf: fileURL, encoding: .utf8))
				for call in pathSpellingCalls where code.contains(call) {
					violations.append(fileURL.lastPathComponent)
				}
			}
		}
		#expect(checkedFileNames.isSuperset(of: ["FilePathSpelling.swift", "ScanCommand.swift", "GenerateCommand.swift", "PluginScanner.swift"]))
		#expect(violations == [])
	}

	@Test
	func pathSpellingCallCheck_findsCall_whenCodeCallsIt() throws {
		// The check reads the code the stripping leaves, so it finds a call and ignores a comment that names one.
		let code = stripSwiftCommentsAndStrings(from: """
		// URL.standardizedFileURL is documented here.
		let resolved = realpath (path, nil)
		""")
		#expect(try code.contains(Regex(#"\brealpath\s*\("#)))
		#expect(try !code.contains(Regex(#"\bstandardizedFileURL\b"#)))
	}
}
