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

extension ScopeGenerator.FillCallerReads {
	/// The caller's own values a fill reads from its mock root's binding, each to be bound under its label from the name the
	/// root binds it under (`rootBindingNames`, by label and type), before the fill's body: in label order, which may decide
	/// the order of these bindings since each binds an equivalent value of its own label. A label the root binds under no
	/// name is left out.
	func mockRootRebindings(rootBindingNames: [String: [TypeDescription: String]]) -> [(label: String, rootBindingName: String)] {
		mockRootBindingByLabel.keys.sorted().compactMap { label in
			mockRootBindingByLabel[label].flatMap { rootBindingNames[label]?[$0.typeDescription] }.map { (label, $0) }
		}
	}
}
