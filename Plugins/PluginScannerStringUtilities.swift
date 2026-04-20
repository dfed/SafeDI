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
/// nesting supported), string literals (single and triple-quoted), and
/// extended regex literals (`#/…/#`), preserving line structure so regex
/// line anchors still behave. Non-comment/non-string characters and
/// newlines pass through unchanged.
///
/// This is deliberately a lexer-lite: it matches Swift tokens well enough
/// that a mention of `@Instantiable(...)` inside a comment or string is
/// excluded from the scanner's regex. It is NOT a full Swift parser — but
/// the real parser (`SafeDITool`) runs at build time and is authoritative.
///
/// Known limitation: simple `/.../` regex literals are ambiguous with
/// division in a tokenless scan, so they are not recognized. Block-comment
/// detection includes a lookahead that bails on unterminated `/*` — that
/// defangs runaway consumption when a `/*` appears inside a simple regex
/// and no later `*/` exists in the file.
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

		// Block comment (nested): skip through the matching `*/`. First verify
		// a matching `*/` exists at balanced depth; otherwise this `/*` isn't
		// really a block comment (e.g., it's inside a `/.../` regex literal)
		// and treating it as one would runaway-consume real code.
		if character == "/", next == "*", blockCommentHasCloser(chars: chars, start: index) {
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

		// Extended regex literal `#/.../#`: delimited unambiguously, so skip
		// the entire span. Preserves newlines for regex line-anchor parity.
		if character == "#", next == "/" {
			index += 2
			while index < chars.count {
				if chars[index] == "\\", index + 1 < chars.count {
					if chars[index + 1] == "\n" {
						result.append("\n")
					}
					index += 2
					continue
				}
				if chars[index] == "/", index + 1 < chars.count, chars[index + 1] == "#" {
					index += 2
					break
				}
				if chars[index] == "\n" {
					result.append("\n")
				}
				index += 1
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

/// Returns `true` if a `/*` at `start` has a matching `*/` at balanced
/// depth somewhere later in `chars`. Used to skip block-comment mode
/// when the `/*` is unterminated — defangs the case where `/*` appears
/// inside a `/.../` regex literal with no later `*/` in the file.
private func blockCommentHasCloser(chars: [Character], start: Int) -> Bool {
	var index = start + 2
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
			index += 1
		}
	}
	return depth == 0
}
