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
	/// Refuses `world`, which holds a cycle, where a body reads a `LazilyInstantiated` wrapper's instance or a seam's root
	/// is handed one: a function the cycle closes on takes such a value as a cycle parameter read through its wrapper
	/// (the cycle parameters' type fact, its wrapper keys), which these records do not write yet.
	static func checkReadsNoWrappersInstance(
		inWorldWithCycle world: some NodeRecordSources,
		answeringDeclarations: DeclarationsAnsweringReads,
		rootLazilyInstantiatedInstanceProperties: Set<Property>,
	) throws(NodeRecordRefusal) {
		guard rootLazilyInstantiatedInstanceProperties.isEmpty,
		      (0..<Int32(world.variantCount)).allSatisfy({ answeringDeclarations.lazilyInstantiatedInstanceProperties(readBy: $0).isEmpty })
		else { throw .cycleReadsLazyWrapper }
	}
}
