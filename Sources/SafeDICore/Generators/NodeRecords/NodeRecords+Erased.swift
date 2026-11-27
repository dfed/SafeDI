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
	/// Claims a node built as an `ErasedInstantiator`, or as a constant or an `Instantiator` erased to its property's type
	/// (`erasedToConcreteExistential`). Its record is its type's initializer's
	/// (`builtByInitializerRecord(of:variant:in:unavailableProperties:lazilyInstantiatedInstanceProperties:typesDeclaredEscaping:children:lineEnd:)`),
	/// marked erased where the node is, so that the engine wraps the built value in the property's type. An erased
	/// `LazilyInstantiated` is `lazyClaim(of:in:)`'s, and an erased `Sendable` wrapper `sendableClaim(of:in:)`'s.
	static func erasedClaim(of declaration: DeclarationID, in world: some NodeRecordVariantFacts) -> NodeRecordClaim? {
		switch world.kind(of: declaration) {
		case .erasedInstantiator:
			NodeRecordClaim(kind: .erased, discharges: [.erased])
		case .constant, .instantiator:
			world.isErased(declaration) ? NodeRecordClaim(kind: .erased, discharges: [.erased]) : nil
		case .sendableInstantiator, .sendableErasedInstantiator, .lazy, .sendableLazy, .alias, .hole:
			nil
		}
	}
}
