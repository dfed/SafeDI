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

/// Whether a seam call builds a fill for every place it fills, rather than one fill for the places of a case whose fills
/// would be built alike (`ScopeGenerator.FillStoodFor`). Which of the two a call does must reach no output, generated
/// code or diagnostic: a judgment that reads more of a place than its fill's fields (a capture, a closer's depth) reads
/// it for each place the fill stands for. Only a test sets this, to compare a run that shares fills with a run that
/// builds every one, as the seam corpus does for every graph. The tree
/// `--dot-file-output` draws shows a place whose fill is not built with the tree of the fill that stands for it.
public enum SeamFillSharing {
	@TaskLocal public static var buildsFillOfEveryPlace = false

	/// What one call of a seam or of another module's public mock built to fill its places, in one pass of its tree.
	public struct FillsOfCall: Sendable {
		/// The type the call builds, as its declaration spells it.
		public let calledType: String
		/// The fills the call built: the one of each case that generates code, and one for each set of a case's places
		/// whose fills would be built alike.
		public let builtFillCount: Int
		/// The places another place's fill stands for.
		public let placeStoodForCount: Int
	}

	/// Called with what each call that fills a place built, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: TaskLocalFunction<@Sendable (FillsOfCall) -> Void>?
}
