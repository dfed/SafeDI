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

enum MockTypeKeyLayoutChecks {
	/// The errors production's record function may throw at a mock's built place, by case and kind of construction: where the
	/// place calls its type's hand-written mock, which may take fewer dependencies than production's initializer
	/// (`Scope.dependenciesLeftOut`), production's argument list names one the mock's scope does not declare. The root keeps
	/// the walk's body, which builds the place as before. A root that falls back on any other error is an engine defect.
	static let expectedRecordErrors: Set<String> = ["unexpectedArgument:configuredConstruction"]

	/// An observer that records an issue for each mock root that falls back because production's record function threw an
	/// error `expectedRecordErrors` does not list, then hands the outcome to `enclosingObserver`.
	static func failingUnexpectedRecordErrors(handingOn enclosingObserver: (@Sendable (String, String) -> Void)?) -> @Sendable (String, String) -> Void {
		{ mockedType, outcome in
			let threwPrefix = "unrecorded:threw:"
			if outcome.hasPrefix(threwPrefix), !expectedRecordErrors.contains(String(outcome.dropFirst(threwPrefix.count))) {
				Issue.record(Comment(rawValue: "The type key’s layout of `\(mockedType).mock()` fell back on an error production’s record function is not expected to throw: \(outcome)"))
			}
			enclosingObserver?(mockedType, outcome)
		}
	}
}
