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
	/// The refusals of stage 1 that the mock kind `mockErased` discharges of `declaration`, a node of a mock root's world:
	/// `erased` where the production kind's classifier claims the node (`erasedClaim(of:in:)`), and none otherwise. An
	/// erased `LazilyInstantiated` stays `lazy`'s, and an erased `Sendable` wrapper `sendable`'s.
	static func mockErasedDischarges(of declaration: DeclarationID, in world: some NodeRecordSources) -> Set<NodeRecordRefusal> {
		erasedClaim(of: declaration, in: world)?.discharges ?? []
	}

	/// The record of `declaration`'s place, a node of kind `mockErased`: `mockConstructionRecord`'s, whose override
	/// returns the property's type, as a mock's override always does, where the node's type is erased to it or built as
	/// an `ErasedInstantiator` of it. So the node's function returns the property's type, its construction erased inside
	/// where the node is erased, and its call erases nothing. A configured node's builder returns the concrete type, as its
	/// configuration declares it, which the function erases as it erases its construction.
	static func mockErasedRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
		unavailableProperties: Set<Property>,
		typesDeclaredEscaping: Set<TypeDescription>,
		children: [GeneratedCode],
	) throws -> BuiltPlaceRecord {
		var record = try mockConstructionRecord(of: declaration, variant: variant, in: world, unavailableProperties: unavailableProperties, typesDeclaredEscaping: typesDeclaredEscaping, children: children)
		// A constant built in place returns nothing: its construction is erased where it is bound, and its override is read
		// there as the property's type.
		guard record.hasFunction else { return record }
		record.returnsPropertyType = true
		if record.isErased, !children.isEmpty {
			record.alternatives = record.alternatives.map {
				ConstructionAlternative(
					closure: $0.closure,
					bindingName: $0.bindingName,
					requiresAbsent: $0.requiresAbsent,
					use: $0.use,
					resultWrapper: record.property.typeDescription.asInstantiatedTypeSpelledAsDeclared,
				)
			}
		}
		return record
	}
}
