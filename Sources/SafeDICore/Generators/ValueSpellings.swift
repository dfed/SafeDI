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

/// One spelling for each value a tree's receivers spell apart. `==` reads `any P` and `P` as one type, so a set of the
/// properties a tree receives keeps whichever spelling it met first, which the order of a walk decides. Each value – a
/// label and the instance its forms hold: its optional, its unwrapped form, and a `LazilyInstantiated` or
/// `SendableLazilyInstantiated` of its instance – is spelled instead as the most explicit of its receivers' spellings
/// (`TypeDescription.mostExplicitSpelling(among:)`), so a value one receiver spells `any P` is spelled `any P` wherever
/// generated code declares it, which no module that enables the `ExistentialAny` upcoming feature warns on.
struct ValueSpellings {
	/// The spellings of the values `properties` hold, each its receivers' most explicit.
	init(of properties: some Sequence<Property>) {
		for property in properties {
			let instanceProperty = Self.instanceProperty(of: property)
			if let spelledInstanceProperty = spelledInstanceProperties[instanceProperty] {
				// Most receivers spell a value alike, which compares their spellings alone.
				if spelledInstanceProperty.typeDescription.asSource != instanceProperty.typeDescription.asSource,
				   instanceProperty.typeDescription.isMoreExplicitSpelling(than: spelledInstanceProperty.typeDescription)
				{
					spelledInstanceProperties[instanceProperty] = instanceProperty
				}
			} else {
				spelledInstanceProperties[instanceProperty] = instanceProperty
			}
		}
	}

	/// `property` with its value's spelling, or `property` itself when no spelling of its value is recorded.
	func spelling(ofValueOf property: Property) -> Property {
		spelledInstanceProperties[Self.instanceProperty(of: property)].map { Self.property(property, spellingInstanceAs: $0) } ?? property
	}

	/// `property` with the instance `instanceProperty(of:)` reads spelled as `instanceProperty` spells it.
	static func property(_ property: Property, spellingInstanceAs instanceProperty: Property) -> Property {
		Property(label: property.label, typeDescription: typeDescription(property.typeDescription, spellingInstanceAs: instanceProperty.typeDescription))
	}

	/// The fulfilling property `fulfillingProperty` an alias whose own property is `aliasProperty` receives, spelled as
	/// `aliasProperty` spells its type where that is the type `ofType:` names, and as `ofType:` does otherwise: an alias's
	/// declaration is its property, while `ofType: Service.self` is an expression, which the `ExistentialAny` upcoming
	/// feature does not flag.
	static func fulfillingProperty(_ fulfillingProperty: Property, spelledAsAlias aliasProperty: Property) -> Property {
		let fulfillingInstanceProperty = instanceProperty(of: fulfillingProperty)
		let declaredInstanceProperty = instanceProperty(of: Property(label: fulfillingProperty.label, typeDescription: aliasProperty.typeDescription))
		return if declaredInstanceProperty == fulfillingInstanceProperty {
			property(fulfillingProperty, spellingInstanceAs: declaredInstanceProperty)
		} else {
			fulfillingProperty
		}
	}

	/// The instance of the value `property` is a form of: `property` unwrapped, and the instance of a lazily
	/// instantiated property that creates a non-optional one.
	static func instanceProperty(of property: Property) -> Property {
		let unwrappedProperty = property.asUnwrappedProperty
		return unwrappedProperty.asLazilyInstantiatedInstanceProperty ?? unwrappedProperty
	}

	// MARK: Private

	/// The spelling of the instance of each value, keyed by that instance (`instanceProperty(of:)`).
	private var spelledInstanceProperties = [Property: Property]()

	/// `typeDescription` with the instance `instanceProperty(of:)` reads spelled `instanceType`.
	private static func typeDescription(_ typeDescription: TypeDescription, spellingInstanceAs instanceType: TypeDescription) -> TypeDescription {
		if case let .optional(wrappedType) = typeDescription {
			.optional(Self.typeDescription(wrappedType, spellingInstanceAs: instanceType))
		} else if case let .simple(name, generics) = typeDescription,
		          let lazilyInstantiatedInstanceType = typeDescription.lazilyInstantiatedInstanceType,
		          !lazilyInstantiatedInstanceType.isOptional
		{
			.simple(name: name, generics: [instanceType] + generics.dropFirst())
		} else {
			instanceType
		}
	}
}

extension Set<Property> {
	/// Inserts `property`, or, where the set holds another spelling of it, keeps the more explicit of the two
	/// (`TypeDescription.mostExplicitSpelling(among:)`). `insert` keeps whichever spelling it met first, so a set built
	/// by a walk would hold the spelling the walk's order decides.
	mutating func insertKeepingMostExplicitSpelling(_ property: Property) {
		let (inserted, member) = insert(property)
		// Most receivers spell a value alike, which compares their spellings alone.
		if !inserted,
		   member.typeDescription.asSource != property.typeDescription.asSource,
		   property.typeDescription.isMoreExplicitSpelling(than: member.typeDescription)
		{
			update(with: property)
		}
	}

	/// Inserts each of `properties` as `insertKeepingMostExplicitSpelling(_:)` does.
	mutating func formUnionKeepingMostExplicitSpelling(_ properties: some Sequence<Property>) {
		for property in properties {
			insertKeepingMostExplicitSpelling(property)
		}
	}
}
