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

/// The declarations being built above a place, outermost first, each with the IDs a cycle's lookup compares: the
/// property as cycle validation sees it (a lazily instantiated property as the constant it stands for) and the concrete
/// type it is built for, each by its class, which is `==`. A lazily instantiated declaration's instance is an entry of
/// its own, just inside the declaration.
struct ContextStack: Sendable {
	/// One declaration being built.
	struct Entry: Sendable {
		let property: Property
		let propertyID: PropertyID
		let concreteType: TypeDescription
		/// The depth in the tree of the scope that put the entry on the stack, or -1 for the path of the seam whose hole the
		/// enclosing fill fills.
		let depth: Int
		let validatedPropertyClass: PropertyClassID
		let concreteTypeClass: TypeClassID
		/// Whether the entry is the instance of the lazily instantiated declaration just outside it.
		let isInstanceOfEntryOutside: Bool
	}

	init() {}

	/// The stack of the seam path a fill's tree is built beneath, interned now: `propertyStack` and `concreteTypeStack`
	/// innermost first, as `SeamSignature.Hole.fillPropertyStack` holds them.
	init(fillPropertyStack propertyStack: [Property], concreteTypeStack: [TypeDescription], interningIn space: ConstructionInternerSpace) {
		var outerProperty: Property?
		for (property, concreteType) in zip(propertyStack, concreteTypeStack).reversed() {
			let propertyID = space.intern(property)
			let concreteTypeID = space.intern(concreteType)
			entries.append(Entry(
				property: property,
				propertyID: propertyID,
				concreteType: concreteType,
				depth: -1,
				validatedPropertyClass: space.classID(of: space.asValidatedForDependencyCycles(propertyID)),
				concreteTypeClass: space.classID(of: concreteTypeID),
				isInstanceOfEntryOutside: outerProperty?.asLazilyInstantiatedInstanceProperty == property,
			))
			outerProperty = property
		}
	}

	/// The entries, outermost first.
	private(set) var entries = [Entry]()

	/// The properties of the entries, innermost first.
	var propertiesInnermostFirst: [Property] {
		entries.reversed().map(\.property)
	}

	/// The concrete types of the entries, innermost first.
	var concreteTypesInnermostFirst: [TypeDescription] {
		entries.reversed().map(\.concreteType)
	}

	/// Puts `property`, built for `concreteType` by the scope at `depth`, on the stack, and, inside it, its instance where
	/// it is lazily instantiated.
	mutating func push(
		_ property: Property,
		id propertyID: PropertyID,
		concreteType: TypeDescription,
		concreteTypeID: TypeID,
		depth: Int,
		interner: ConstructionInterner,
	) {
		let concreteTypeClass = interner.classID(of: concreteTypeID)
		entries.append(Entry(
			property: property,
			propertyID: propertyID,
			concreteType: concreteType,
			depth: depth,
			validatedPropertyClass: interner.classID(of: interner.asValidatedForDependencyCycles(propertyID)),
			concreteTypeClass: concreteTypeClass,
			isInstanceOfEntryOutside: false,
		))
		if let lazilyInstantiatedProperty = interner.lazilyInstantiated(propertyID), let instanceProperty = property.asLazilyInstantiatedInstanceProperty {
			let instancePropertyID = interner.instance(of: lazilyInstantiatedProperty)
			entries.append(Entry(
				property: instanceProperty,
				propertyID: instancePropertyID,
				concreteType: concreteType,
				depth: depth,
				validatedPropertyClass: interner.classID(of: interner.asValidatedForDependencyCycles(instancePropertyID)),
				concreteTypeClass: concreteTypeClass,
				isInstanceOfEntryOutside: true,
			))
		}
	}

	/// The entry a scope that builds the property `propertyID` names for the concrete type `concreteTypeID` names repeats,
	/// when it closes a cycle, with its index: the innermost entry of the same property as cycle validation sees it, built
	/// for the same concrete type, and, where that entry is a lazily instantiated declaration's instance, the declaration,
	/// which the same scope put on the stack just outside it.
	func entryClosedOn(byPropertyID propertyID: PropertyID, concreteTypeID: TypeID, interner: ConstructionInterner) -> (entry: Entry, index: Int)? {
		let validatedPropertyClass = interner.classID(of: interner.asValidatedForDependencyCycles(propertyID))
		let concreteTypeClass = interner.classID(of: concreteTypeID)
		guard let entryIndex = entries.lastIndex(where: { $0.validatedPropertyClass == validatedPropertyClass && $0.concreteTypeClass == concreteTypeClass }) else { return nil }
		let index = entries[entryIndex].isInstanceOfEntryOutside ? entryIndex - 1 : entryIndex
		return (entries[index], index)
	}
}
