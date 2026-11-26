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

import SafeDIToolLibrary
import Testing

/// What every run of the multi-module harness checks of the places a module info file holds.
enum StoredPlaceChecks {
	/// Records an issue when `count`, which the output of the run of the module named `moduleName` holds
	/// (`Generate.Output.passedUpPlacesWrittenInFull`; the count and not the output, since `Generate` is available
	/// from macOS 13, which this declaration does not state), counts a place a seam passes up that the run wrote in
	/// full, where it would write the record of the seam the place came from. A place written in full is read correctly; the issue says that
	/// the form that keeps a module info file from growing with the modules beneath it did not hold the place.
	///
	/// Read from the run's output after the run, never observed through one more `TaskLocal.withValue` in the harness's
	/// nest of them: with one more written there, a release build of the tests by Swift 6.2 aborts with "freed pointer
	/// was not the last allocation".
	/// - Parameter isExpected: Whether the run may write such a place, which then records no issue.
	static func expectNoPlaceWrittenInFull(counted count: Int?, unless isExpected: Bool, byRunOfModuleNamed moduleName: String, sourceLocation: SourceLocation) {
		if let count, count > 0, !isExpected {
			Issue.record("The run of module `\(moduleName)` wrote \(count) passed-up place in full, not as the record it copies", sourceLocation: sourceLocation)
		}
	}
}
