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

/// A dependency `query graph` sets aside so that the trees build while it cannot be fulfilled: a received dependency or
/// alias nothing provides, or an instantiated dependency no declaration fulfills.
public struct UnfulfilledDependency: Hashable, Sendable {
	public init(declaringType: TypeDescription, label: String) {
		self.declaringType = declaringType
		self.label = label
	}

	/// The concrete type of the declaration that declares the dependency.
	public let declaringType: TypeDescription
	/// The dependency's label.
	public let label: String
}

extension DependencyTreeGenerator {
	/// The declarations of `typeDescriptionToFulfillingInstantiableMap` with each dependency that `error` reports cannot
	/// be fulfilled set aside, so that the trees can be built again without it: an instantiated one is read as
	/// instantiated only if available, a received one or an alias as received only if available, each with its type
	/// made optional, as the macro requires of those spellings. `nil` when `error` reports anything else, or names no
	/// dependency the map declares. Only `query graph` calls this: `generate` reports the error.
	public static func settingAsideUnfulfilledDependencies(
		reportedBy error: any Error,
		in typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable],
	) -> (map: [TypeDescription: Instantiable], setAside: [UnfulfilledDependency])? {
		guard let error = error as? DependencyTreeGeneratorError,
		      let locations = unfulfilledDependencyLocations(reportedBy: error)
		else { return nil }
		var setAside = Set<UnfulfilledDependency>()
		let map = typeDescriptionToFulfillingInstantiableMap.mapValues { instantiable in
			instantiable.mappingDependencies { dependency in
				guard let location = dependency.declarationLocation, locations.contains(location) else { return dependency }
				setAside.insert(UnfulfilledDependency(declaringType: instantiable.concreteInstantiable, label: dependency.property.label))
				return dependency.readOnlyIfAvailable
			}
		}
		guard !setAside.isEmpty else { return nil }
		// The map's values are visited in no fixed order, so the dependencies are listed sorted.
		return (map, setAside.sorted { ($0.declaringType, $0.label) < ($1.declaringType, $1.label) })
	}

	/// Where each dependency `error` reports cannot be fulfilled is declared, or `nil` when `error` reports anything else.
	private static func unfulfilledDependencyLocations(reportedBy error: DependencyTreeGeneratorError) -> Set<Dependency.DeclarationLocation>? {
		var locations = Set<Dependency.DeclarationLocation>()
		var errors = [error]
		while let error = errors.popLast() {
			switch error {
			case let .independentErrors(independentErrors):
				errors.append(contentsOf: independentErrors)
			case let .noInstantiableFound(_, referencedBy, _, _, _):
				for case let location? in referencedBy.map(\.declarationLocation) {
					locations.insert(location)
				}
			case let .unfulfillableProperties(unfulfillableProperties):
				for case let location? in unfulfillableProperties.map(\.declarationLocation) {
					locations.insert(location)
				}
			case .unfilledHoles, .fillFindings, .holesInSeamsOfUnnamedModule, .hiddenReceivedProperties, .renamesContradictingOwnProperties, .forwardedPropertyHiddenInPromotedTree, .receivedPropertyHiddenInMockTree, .unpassableCycleLabel, .instantiableHasForwardedProperty, .constantDependencyCycleDetected, .dependencyReceivedInSameChainItIsInstantiated, .handWrittenMockSharesGeneratedMockName, .handWrittenMockSharesPublicMockName, .publicMockCannotBeGenerated, .nonSendableWrapperCapturedBySendableBuilder, .seamTierOmitsProvidedValue, .publicMockTierOmitsProvidedValue, .publicMockUnderOtherMockCondition, .seamModuleMockConditionDiffers, .configurationBuiltTwoWays, .repeatedDependencyLabels, .rejectedRenames, .unfulfilledMockParameters, .inaccessibleConstructions, .seam, .sourceLocated:
				return nil
			}
		}
		return locations
	}
}

extension Dependency {
	/// This dependency read as only if available, its type made optional. An error reports only a dependency that is
	/// instantiated, received or an alias, none of them only if available, so a forwarded one keeps its source.
	fileprivate var readOnlyIfAvailable: Dependency {
		let source: Source = switch self.source {
		case .instantiated, .forwarded:
			self.source
		case .received:
			.received(onlyIfAvailable: true)
		case let .aliased(fulfillingProperty, erasedToConcreteExistential, _):
			.aliased(fulfillingProperty: fulfillingProperty, erasedToConcreteExistential: erasedToConcreteExistential, onlyIfAvailable: true)
		}
		let typeDescription = property.typeDescription
		return Dependency(
			property: typeDescription.isOptional ? property : property.withUpdatedTypeDescription(.optional(typeDescription)),
			source: source,
			declarationLocation: declarationLocation,
			identifierRange: identifierRange,
			typeAnnotationRange: typeAnnotationRange,
			bareAttributeRange: bareAttributeRange,
		)
	}
}
