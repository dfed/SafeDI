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
	/// Whether `declaration`, a node of a mock root's world, is erased, so that its override returns the property's type
	/// (`mockErasedDecoration(of:)`): an `ErasedInstantiator`, which production's term claims, and any node whose value is
	/// erased to its property's type, a `LazilyInstantiated`, a `Sendable` wrapper and a public mock call included.
	static func isMockErased(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		erasedClaim(of: declaration, in: world) != nil || world.isErased(declaration)
	}

	/// `record`, a mock's record of a node erased to its property's type or built as an `ErasedInstantiator` or an erased
	/// `LazilyInstantiated` of it, whose override returns the property's type.
	static func mockErasedDecoration(of record: BuiltPlaceRecord) -> BuiltPlaceRecord {
		var record = record
		// A constant built in place returns nothing: its construction is erased where it is bound, and its override is read
		// there as the property's type.
		guard record.hasFunction else { return record }
		record.returnsPropertyType = true
		guard record.isErased else { return record }
		// A configuration's builder returns the concrete type, whether the node is configured for its children or for a
		// field its own construction reads; a closure that overrides the node itself returns the property's.
		record.alternatives = record.alternatives.map { alternative in
			guard case .member(ReservedName.configurationBuilderPropertyName, _) = alternative.closure else { return alternative }
			return ConstructionAlternative(
				closure: alternative.closure,
				bindingName: alternative.bindingName,
				requiresAbsent: alternative.requiresAbsent,
				use: alternative.use,
				resultWrapper: record.property.typeDescription.asInstantiatedTypeSpelledAsDeclared,
			)
		}
		return record
	}
}
