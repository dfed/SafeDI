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

extension NodeRecords {
	/// What a node of a mock root's world built as a `LazilyInstantiated`, erased or not, discharges of stage 1's
	/// refusals: the wrapper is made of its builder function as in a production root's world (`lazyClaim(of:in:)`), and
	/// the function first tries the node's override
	/// (`mockConstructionRecord(of:variant:in:unavailableProperties:lazilyInstantiatedInstanceProperties:typesDeclaredEscaping:children:)`).
	/// An erased wrapper's override returns the erased type, so its record is the erased kind's, whose function erases the
	/// construction it falls back to. Empty for a node of any other kind.
	static func mockLazyDischarges(of declaration: DeclarationID, in world: some NodeRecordSources) -> Set<NodeRecordRefusal> {
		lazyClaim(of: declaration, in: world)?.discharges ?? []
	}
}
