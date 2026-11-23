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

/// Stage D1's lowering of the builders an internal mock takes: one per hole type and family for a seam's own places and
/// for the builders its tree's calls of other modules' public mocks pass up (`ScopeGenerator.seamMockBuilders`).
extension MockLowering {
	/// The builders `mock()` takes for `places`, the uncovered dependencies of a seam's own internal mock, each named as its
	/// parameter would have been, in the mock's order, and for the builders its tree's calls pass up, received as
	/// `passedUpProperties`, in the order of the flat received parameters: one per hole type and family, the places' families
	/// first, in the order the places first meet them, then the families only calls pass up, in the order the properties
	/// first meet them; each labeled from its hole type's stem apart from `otherParameterLabels`, in label order, and bound
	/// under a name apart from `builderFunctionNames` where `namesBoundInTheTree` holds its label. Or the first rule they
	/// meet: a property whose family is unknown, and a builder its calls pass up in another form than its places or other
	/// calls take, which `mock()` adapts, are not lowered yet.
	static func seamMockBuilders(
		places: [ScopeGenerator.MockRootParameters.UncoveredParameter],
		passedUpProperties: [Property],
		families: [Property: (family: ScopeGenerator.MockRootParameters.SeamMockBuilder.Family, isCapturedBySendableFunction: Bool)],
		otherParameterLabels: Set<String>,
		namesBoundInTheTree: Set<String>,
		builderFunctionNames: Set<String>,
		typesDeclaredEscaping: Set<TypeDescription>,
	) -> Lowering<[RootSignature.PassedUpBuilder]> {
		typealias Family = ScopeGenerator.MockRootParameters.SeamMockBuilder.Family
		guard !places.isEmpty || !passedUpProperties.isEmpty else { return .lowered([]) }
		var familiesInOrder = [Family]()
		var placesByFamily = [Family: [ScopeGenerator.MockRootParameters.UncoveredParameter]]()
		for place in places {
			let family = Family(
				holeType: SeamSignature.HoleType(instantiatedType: place.instantiatedType.spelledCanonically, builtType: place.property.typeDescription.builtTypeOfWrapper.spelledCanonically),
				isSendable: place.isSendableAutoclosure || place.property.propertyType.isSendable,
			)
			if placesByFamily[family] == nil {
				familiesInOrder.append(family)
			}
			placesByFamily[family, default: []].append(place)
		}
		var passedUpPropertiesByFamily = [Family: [Property]]()
		for property in passedUpProperties {
			guard let family = families[property]?.family else { return .unsupported(.publicMockCall) }
			if placesByFamily[family] == nil, passedUpPropertiesByFamily[family] == nil {
				familiesInOrder.append(family)
			}
			passedUpPropertiesByFamily[family, default: []].append(property)
		}
		var holeTypes = [SeamSignature.HoleType]()
		for family in familiesInOrder where !holeTypes.contains(family.holeType) {
			holeTypes.append(family.holeType)
		}
		let stems = DependencyTreeGenerator.stems(of: holeTypes)
		// The type a builder a call passes up is taken as: `@Sendable` where a `@Sendable` builder function captures it, an
		// instantiator's `Builder` through its `Sendable` twin.
		func passedUpType(of property: Property) -> TypeDescription {
			families[property]?.isCapturedBySendableFunction == true && !property.typeDescription.isSendableFunction ? property.typeDescription.asSendableBuilder : property.typeDescription
		}
		var labels = GeneratedNameAllocator(reserving: otherParameterLabels)
		var builders = [(label: String, family: Family, typeDescription: TypeDescription)]()
		for family in familiesInOrder {
			let stem = stems[family.holeType, default: ""]
			let label = labels.claim(family.isSendable ? DependencyTreeGenerator.sendableBuilderLabel(ofStem: stem) : DependencyTreeGenerator.plainBuilderLabel(ofStem: stem))
			let familyPlaces = placesByFamily[family, default: []]
			let familyPassedUpProperties = passedUpPropertiesByFamily[family, default: []]
			let parameterType: TypeDescription = if familyPlaces.isEmpty, let first = familyPassedUpProperties.first {
				passedUpType(of: first).asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping)
			} else {
				ScopeGenerator.MockRootParameters.SeamMockBuilder.parameterType(ofPlaceProperties: familyPlaces.map(\.property), in: family)
			}
			guard familyPassedUpProperties.allSatisfy({ passedUpType(of: $0).strippingEscaping.asSource == parameterType.strippingEscaping.asSource }) else { return .unsupported(.publicMockCall) }
			builders.append((label, family, parameterType))
		}
		builders.sort { $0.label < $1.label }
		var names = GeneratedNameAllocator(reserving: builderFunctionNames.union(namesBoundInTheTree))
		return .lowered(builders.map { builder in
			RootSignature.PassedUpBuilder(
				label: builder.label,
				internalName: namesBoundInTheTree.contains(builder.label) ? names.claim(ScopeGenerator.functionName(toBuildPropertyNamed: builder.label)) : builder.label,
				properties: passedUpPropertiesByFamily[builder.family, default: []],
				typeSource: builder.typeDescription.asSource,
				places: placesByFamily[builder.family, default: []],
			)
		})
	}
}

extension ScopeGenerator {
	/// Whether this is a hole without a site, which a tree built to compute a seam's signature, or a seam's own internal
	/// mock, holds for a place a builder builds: it generates nothing.
	nonisolated var mockLoweringIsHoleWithoutSite: Bool {
		if case .hole(_, _, nil) = scopeData {
			true
		} else {
			false
		}
	}
}
