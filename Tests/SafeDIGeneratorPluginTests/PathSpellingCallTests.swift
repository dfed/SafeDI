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
		for file in try RepositorySwiftFile.files(under: ["Sources", "Plugins"]) {
			checkedFileNames.insert(file.name)
			guard file.name != "FilePathSpelling.swift" else { continue }
			let code = stripSwiftCommentsAndStrings(from: file.source)
			for call in pathSpellingCalls where code.contains(call) {
				violations.append(file.name)
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
