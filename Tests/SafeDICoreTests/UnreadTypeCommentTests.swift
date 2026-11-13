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

import SafeDICore
import Testing

struct UnreadTypeCommentTests {
	@Test
	func resolvingMarkers_replacesTheMarker_whenTheLineBreakBeforeItIsCarriageReturnLineFeed() {
		let code = "public struct S {}\r\n\t\u{1}UnreadTypes\u{1}A\npublic func a() {}\n"
		#expect(UnreadTypeComment.resolvingMarkers(in: code) == "public struct S {}\r\n\t// SafeDI counts `A` as `public`: no module it reads declares it narrower. If `A` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.\npublic func a() {}\n")
	}

	@Test
	func resolvingMarkers_keepsTheCarriageReturnInTheLastTypeName_whenTheMarkerLineEndsInCarriageReturnLineFeed() {
		// SafeDI ends every generated line with a line feed alone, so a marker line never ends in a carriage return; the
		// byte search splits lines at line feeds only.
		let code = "\u{1}UnreadTypes\u{1}A\r\nx = 1\n"
		#expect(UnreadTypeComment.resolvingMarkers(in: code) == "// SafeDI counts `A\r` as `public`: no module it reads declares it narrower. If `A\r` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.\nx = 1\n")
	}

	@Test
	func resolvingMarkers_returnsTheCodeUnchanged_whenEveryControlCharacterIsNotAMarker() {
		let code = "let a = \"\u{1}UnreadTypes\u{1}A\"\nx\u{1}UnreadTypes\u{1}B\n\t\u{1}OtherTypes\u{1}C\n\u{1}"
		#expect(UnreadTypeComment.resolvingMarkers(in: code) == code)
	}

	@Test
	func resolvingMarkers_leavesAControlCharacterThatIsNotAtTheStartOfALine_whenAMarkerLineFollows() {
		let code = "let a = \"\u{1}UnreadTypes\u{1}B\"\n\u{1}UnreadTypes\u{1}A\nx = 1\n"
		#expect(UnreadTypeComment.resolvingMarkers(in: code) == "let a = \"\u{1}UnreadTypes\u{1}B\"\n// SafeDI counts `A` as `public`: no module it reads declares it narrower. If `A` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.\nx = 1\n")
	}

	@Test
	func resolvingMarkers_replacesOnlyTheFirstMarkerLineAndRemovesTheOthersWithTheLineBreakBeforeEach_whenSeveralMarkerLinesExist() {
		let code = "public enum E {\n\t\u{1}UnreadTypes\u{1}B\n\tpublic func b() {}\n\t\u{1}UnreadTypes\u{1}A\n\tpublic func a() {}\n}\n\u{1}UnreadTypes\u{1}C\npublic func c() {}"
		#expect(UnreadTypeComment.resolvingMarkers(in: code) == "public enum E {\n\t// SafeDI counts `A`, `B`, and `C` as `public`: no module it reads declares them narrower. If one is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.\n\tpublic func b() {}\n\tpublic func a() {}\n}\npublic func c() {}")
	}

	@Test
	func resolvingMarkers_namesEachTypeOnceInSpellingOrder_whenMarkersNameTypesOutOfOrderAndMoreThanOnce() {
		let code = "\u{1}UnreadTypes\u{1}F\u{1}C\u{1}A\n\u{1}UnreadTypes\u{1}E\u{1}C\u{1}B\u{1}F\n\u{1}UnreadTypes\u{1}D\u{1}A\u{1}E\n"
		#expect(UnreadTypeComment.resolvingMarkers(in: code) == "// SafeDI counts `A`, `B`, `C`, `D`, `E`, and `F` as `public`: no module it reads declares them narrower. If one is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.\n")
	}
}
