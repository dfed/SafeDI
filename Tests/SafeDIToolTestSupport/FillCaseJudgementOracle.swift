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

/// Test only, deleted before merge: the differential oracle of the callers' fill findings by case. `validateFills` judges
/// every place against its fill today; by case it judges one place per case of the called seam's enums nested by type and
/// per distinct answer of what the fill's tree reads, the place whose route sorts first in source order, which is the
/// place `FillFinding.precedesInSourceOrder` keeps once `FillFinding.adding` merges findings that differ only in the
/// places they name. Every test and every fuzzer graph compares the two judgements' diagnostics, text and order, so moving
/// the judgement onto the place graph moves it onto answers already proven equal.
public enum FillCaseJudgementOracle {
	/// The disagreement of one `validateFills` call's two judgements, or none.
	public static func mismatches(of comparison: FillCaseJudgementComparison) -> [String] {
		guard !comparison.agrees else { return [] }
		return ["""
		fill findings judged by case differ from those judged per place
		--- per place
		\(comparison.perPlace.joined(separator: "\n"))
		--- by case
		\(comparison.byCase.joined(separator: "\n"))
		"""]
	}
}
