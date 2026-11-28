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

import Testing
@testable import SafeDICore

struct ValuePathEqualityTests {
	@Test
	func equality_equatesMemberReadsOfEqualBases_whenEachBaseIsItsOwnObject() {
		// A member's base is held by a class, so two reads built apart hold two objects: they are one path where their bases
		// are, as a set of paths keeps one of them, and two where a base or a member's name differs.
		let paths: Set<ValuePath> = [
			.member("first", of: .rootDeclaration("safeDIOverrides")),
			.member("first", of: .rootDeclaration("safeDIOverrides")),
			.member("first", of: .rootDeclaration("other")),
			.member("second", of: .rootDeclaration("safeDIOverrides")),
			.optionalMember("first", of: .member("first", of: .rootDeclaration("safeDIOverrides"))),
			.optionalMember("first", of: .member("first", of: .rootDeclaration("safeDIOverrides"))),
		]
		#expect(paths.count == 4)
		#expect(paths.contains(.optionalMember("first", of: .member("first", of: .rootDeclaration("safeDIOverrides")))))
	}
}
