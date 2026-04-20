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

/// Removes Swift line comments (`//`…EOL), block comments (`/* … */`,
/// nesting supported), and string literals (single and triple-quoted),
/// preserving line structure so regex line anchors still behave.
/// Non-comment/non-string characters and newlines pass through unchanged.
///
/// This is deliberately a lexer-lite: it matches Swift tokens well enough
/// that a mention of `@Instantiable(...)` inside a comment or string is
/// excluded from the scanner's regex. It is NOT a full Swift parser — but
/// the real parser (`SafeDITool`) runs at build time and is authoritative.
func stripSwiftCommentsAndStrings(from source: String) -> String {
	var result = ""
	result.reserveCapacity(source.count)
	let chars = Array(source)
	var index = 0
	while index < chars.count {
		let character = chars[index]
		let next: Character? = index + 1 < chars.count ? chars[index + 1] : nil

		// Line comment: skip through end-of-line, keeping the newline.
		if character == "/", next == "/" {
			while index < chars.count, chars[index] != "\n" {
				index += 1
			}
			continue
		}

		// Block comment (nested): skip through the matching `*/`.
		if character == "/", next == "*" {
			index += 2
			var depth = 1
			while index < chars.count, depth > 0 {
				let openerNext: Character? = index + 1 < chars.count ? chars[index + 1] : nil
				if chars[index] == "/", openerNext == "*" {
					depth += 1
					index += 2
				} else if chars[index] == "*", openerNext == "/" {
					depth -= 1
					index += 2
				} else {
					if chars[index] == "\n" {
						result.append("\n")
					}
					index += 1
				}
			}
			continue
		}

		// Triple-quoted string: skip through closing `"""`. Newlines inside
		// are preserved so downstream regexes see consistent line positions.
		if character == "\"", next == "\"", index + 2 < chars.count, chars[index + 2] == "\"" {
			index += 3
			while index < chars.count {
				if chars[index] == "\\", index + 1 < chars.count {
					if chars[index + 1] == "\n" {
						result.append("\n")
					}
					index += 2
					continue
				}
				if chars[index] == "\"",
				   index + 2 < chars.count,
				   chars[index + 1] == "\"",
				   chars[index + 2] == "\""
				{
					index += 3
					break
				}
				if chars[index] == "\n" {
					result.append("\n")
				}
				index += 1
			}
			continue
		}

		// Single-quoted string: skip through closing `"` on the same line.
		if character == "\"" {
			index += 1
			while index < chars.count {
				if chars[index] == "\\", index + 1 < chars.count {
					index += 2
					continue
				}
				if chars[index] == "\"" || chars[index] == "\n" {
					if chars[index] == "\n" {
						result.append("\n")
					} else {
						index += 1
					}
					break
				}
				index += 1
			}
			continue
		}

		result.append(character)
		index += 1
	}
	return result
}
