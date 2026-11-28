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
	/// The refusals of stage 1 the mock kind `onlyIfAvailable` discharges of `declaration`, a node of a mock root's world
	/// (`mockConstructionClaim(of:in:)`): a receive only if available of its type, which its construction is passed as
	/// `OnlyIfAvailableAnswers` finds it on the node's path, the value of the nearest declaration of its label that
	/// provides a form it reads and is built before it, or `nil`, as a production root's world; the parameters of `mock()`
	/// and the overrides it binds before its nodes are the declarations farthest from every node, as a seam's parameters
	/// are in its tree (`NodeRecords.init(world:seamTree:outerDeclarations:declaredTypeNames:)`). The mocked type's own
	/// receive is not discharged: the mock offers it an override, which the root binds (`mockRootBindsOtherThanNodes`),
	/// or hands it a dependency the mock promotes beside it, which the root's own construction reads.
	static func mockOnlyIfAvailableDischarges(of declaration: DeclarationID) -> Set<NodeRecordRefusal> {
		declaration == 0 ? [] : [.onlyIfAvailable]
	}
}
