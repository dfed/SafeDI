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

/// Every stored property of `value` and of everything it holds, private ones included, read through
/// reflection. Two values with the same description hold the same data, even where `==` would not tell
/// them apart: `TypeDescription.VoidSpelling` compares both spellings equal, and
/// `UnorderedEquatingCollection` ignores order. A set's elements are sorted, because a set's iteration
/// order is not part of its value.
func reflectedDescription(of value: Any) -> String {
	let mirror = Mirror(reflecting: value)
	let children = mirror.children.map { child in
		"\(child.label.map { "\($0): " } ?? "")\(reflectedDescription(of: child.value))"
	}
	return if mirror.displayStyle == .set {
		"\(type(of: value))[\(children.sorted().joined(separator: ", "))]"
	} else if children.isEmpty {
		// A leaf such as a string, a number, or an enum case without a payload.
		"\(type(of: value))(\(String(reflecting: value)))"
	} else {
		"\(type(of: value))(\(children.joined(separator: ", ")))"
	}
}

/// Every value of a struct or enum type that `value` holds, `value` included, found through reflection.
func reflectedStructuresAndEnumerations(in value: Any) -> [Any] {
	let mirror = Mirror(reflecting: value)
	let nested = mirror.children.flatMap { reflectedStructuresAndEnumerations(in: $0.value) }
	return if mirror.displayStyle == .struct || mirror.displayStyle == .enum {
		[value] + nested
	} else {
		nested
	}
}
