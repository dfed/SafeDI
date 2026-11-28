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

/// The Manual's text and the Swift code blocks of one of its sections, for the tests that compile what the Manual shows.
public enum ManualCodeBlocks {
	/// The text of `Documentation/Manual.md`.
	public static func manual() throws -> String {
		try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Documentation/Manual.md"), encoding: .utf8)
	}

	/// The Swift code blocks of the Manual's section headed `heading`, up to its next heading of any level: the next line
	/// outside a code block that begins with `#`, since a block may hold `#if DEBUG`.
	public static func swiftCodeBlocks(ofSectionTitled heading: String, in manual: String) throws -> [String] {
		let lines = manual.components(separatedBy: "\n")
		let start = try #require(lines.firstIndex(of: heading))
		var blocks = [String]()
		var block: [String]?
		for line in lines[(start + 1)...] {
			if var blockLines = block {
				if line == "```" {
					blocks.append(blockLines.joined(separator: "\n"))
					block = nil
				} else {
					blockLines.append(line)
					block = blockLines
				}
			} else if line == "```swift" {
				block = []
			} else if line.hasPrefix("#") {
				break
			}
		}
		return blocks
	}
}
