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
		/// The fills the call built a second time, only to be judged (`ScopeGenerator.fillJudgementTree`).
		public let fillJudgementTreeCount: Int
		/// Each fill's binding (`ScopeGenerator.fillBinding(of:)`) with the path of the place it fills, in the order the call
		/// holds its fills.
		public let bindings: [(sitePath: [Property], binding: SeamFillBinding)]
	}

	/// Called with what each call that fills a place built, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: TaskLocalFunction<@Sendable (FillsOfCall) -> Void>?
}

/// What a fill of a seam call or public mock call binds, as a reader outside the fill's own generation reads it: one
/// value per fill, compared by its six facts alone. For a seam call's own cases, `boundFields`' order and each field's
/// form come from the seam's signature, so every fill of one case binds the same at every call of the seam in the
/// module. Two kinds of fill are per site until a passed-up case's answers follow its reference: a place the called
/// seam passes up, and a public mock call's place whose caller binds one of the mock's arguments itself, which
/// `fillUnderConstruction` drops from that call's fill.
public struct SeamFillBinding: Hashable, Sendable {
	/// The case nested by type the fill fills (`fillCaseKey(of:)`): every place of it shares one fill.
	public let caseKey: String
	/// The stack entries whose routes the fill's answers leave out. Empty for every fill generation emits: a fill that
	/// closes a cycle on the seam's path is `closesCycleInSeamTree`, an error, so only the judge asks another set.
	public let excludedStackEntries: Set<SeamSignature.Places.StackEntry>
	/// What the fill binds from its case's struct, then what it takes as parameters, in the order the fill function
	/// declares them (`fillBoundFields`, then `fillParameterFields`).
	public let boundFields: [SeamSignature.Hole.Field]
	/// The labels the case's places carry in forms that differ in more than optionality (`irreconcilableFields(of:)`):
	/// non-empty only where `validateFills` rejects the graph, so generation never reads it.
	public let irreconcilableLabels: Set<String>
	/// Whether the fill's function is `@Sendable` (`buildsInSendableFunction(ofFill:)`): the case's family joined with the
	/// caller's own `@Sendable` functions that refer to it, which is why it is no fact of the case.
	public let isSendable: Bool
	/// Whether the place is built inside a `@Sendable` function of the seam's tree: its family.
	public let isBuiltInSendableFunction: Bool
}
