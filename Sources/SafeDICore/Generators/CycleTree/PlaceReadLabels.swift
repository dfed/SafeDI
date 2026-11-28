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

/// The labels a plan says each declaration of a tree reads from above it (`LabelsReadFromAbove`), by the scope built and
/// the property it is built as. Built only where a test observes it (`PlaceReadsObservation`): the tree each path builds
/// logs what each place's subtree read of the context above the place (`ConstructionLog`), and a body shared by every
/// place its paths answer alike may read no label the plan does not key it by.
struct PlaceReadLabels: Sendable {
	struct Place: Hashable, Sendable {
		let record: ObjectIdentifier
		let property: PropertyID
	}

	let plannedLabelsByPlace: [Place: Set<String>]
}

/// Lets a test compare, for each place a tree's pass finishes whose reads were logged, the labels its subtree read of
/// the context above it, cycle reads aside, with the labels the plan says its declaration reads from above.
public enum PlaceReadsObservation {
	/// Called with the type the place builds, the property it is built as, the labels read and the labels planned, each
	/// sorted.
	@TaskLocal public static var observer: TaskLocalFunction<@Sendable (_ type: String, _ property: String, _ labelsRead: [String], _ labelsPlanned: [String]) -> Void>?
}
