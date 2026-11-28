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

extension TypeFactsGraph {
	/// Whether the edge to `child` from the last declaration of `path`, which a walk of a function's body meets, re-enters
	/// a fill rather than closing a cycle on the declaration `closesOn` picks, the nearest on `path`. A seam's call inside
	/// one of the seam's own fills passes the fills it was handed: the fill is not built again, so its edge closes no cycle
	/// and reaches nothing. So does a call of a declaration being built above a fill on the path to it: inside the fill the
	/// tree calls the seam again, handing on the fills its call was handed, and closes no cycle on the function above.
	/// Every fold that walks a function's body to the calls that close a cycle on it asks this, so each skips the same edges.
	func reentersFill(_ child: Int32, in path: [Int32], closesOn: (Int32) -> Bool) -> Bool {
		guard let position = path.lastIndex(where: closesOn) else { return false }
		return graph.nodes[Int(child)].key.isFill || path[(position + 1)...].contains { graph.nodes[Int($0)].key.isFill }
	}
}
