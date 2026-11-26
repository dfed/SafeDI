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

/// Test only, deleted before merge: the fill findings of one `validateFills` call judged two ways, once per place as today
/// and once per case and answer (`fillFindings(…byCase: true)`), which the differential oracle of the tests compares. Nothing
/// generated reads it. A call judges by case only while a test observes the levels (`SeamPlaceLevels.observer`), on which
/// the comparison rides, so the tests set no task-local value of their own around `generate()` (`serialization.md`).
public struct FillCaseJudgementComparison: Sendable {
	public init(perPlace: [String], byCase: [String]) {
		self.perPlace = perPlace
		self.byCase = byCase
	}

	/// Each finding's diagnostics, formatted, in the order `validateFills` reports them, judged once per place.
	public let perPlace: [String]
	/// The same, judged once per case and answer, by the place whose route sorts first in source order.
	public let byCase: [String]

	/// Whether the two judgements report the same diagnostics in the same order.
	public var agrees: Bool {
		perPlace == byCase
	}
}
