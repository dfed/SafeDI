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

/// A dependency `generate` reports cannot be fulfilled, which `query graph` marks: a received dependency or alias nothing
/// provides, or an instantiated dependency no declaration fulfills.
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
	/// What `query graph` builds the trees of a graph mid-edit from when `error`, which `generate` reports of
	/// `typeDescriptionToFulfillingInstantiableMap`, names only dependencies that cannot be fulfilled: every declaration
	/// as written, beside an absent declaration of each type no declaration fulfills, which declares no dependency, and
	/// where the received dependencies and aliases nothing provides are declared, around which a generator given them
	/// builds the trees. No declaration is changed, so every receive the error does not name is handed what it is handed
	/// once the dependencies are fulfilled, as far as the declarations that exist decide it. `nil` when `error` reports
	/// anything else, or names no dependency the map declares. Only `query graph` calls this: `generate` reports the error.
	public static func absentDeclarations(
		ofDependenciesReportedBy error: any Error,
		in typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable],
	) -> AbsentDeclarations? {
		guard let error = error as? DependencyTreeGeneratorError,
		      let reported = unfulfilledDependencies(reportedBy: error)
		else { return nil }
		var unfulfilledDependencies = Set<UnfulfilledDependency>()
		var unfulfilledReceiveLocations = Set<Dependency.DeclarationLocation>()
		for instantiable in typeDescriptionToFulfillingInstantiableMap.values {
			for dependency in instantiable.dependencies {
				guard let location = dependency.declarationLocation else { continue }
				switch dependency.source {
				case .instantiated:
					// A dependency instantiated only if available is `nil` by design where no declaration fulfills its
					// type, though the error lists it beside the required ones.
					guard reported.instantiatingLocations.contains(location), !dependency.isInstantiatedOnlyIfAvailable else { continue }
				case .received, .aliased:
					guard reported.receiveLocations.contains(location) else { continue }
					unfulfilledReceiveLocations.insert(location)
				case .forwarded:
					continue
				}
				unfulfilledDependencies.insert(UnfulfilledDependency(declaringType: instantiable.concreteInstantiable, label: dependency.property.label))
			}
		}
		guard !unfulfilledDependencies.isEmpty else { return nil }
		var map = typeDescriptionToFulfillingInstantiableMap
		for typeDescription in reported.typesNoDeclarationFulfills where map[typeDescription] == nil {
			map[typeDescription] = Instantiable(
				instantiableType: typeDescription,
				isRoot: false,
				initializer: nil,
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
				access: AccessDeclaration(level: .public),
			)
		}
		// The map's values are visited in no fixed order, so the dependencies are listed sorted.
		return AbsentDeclarations(
			map: map,
			unfulfilledDependencies: unfulfilledDependencies.sorted { ($0.declaringType, $0.label) < ($1.declaringType, $1.label) },
			unfulfilledReceiveLocations: unfulfilledReceiveLocations,
		)
	}

	/// The declarations `query graph` builds the trees of a graph mid-edit from, and the dependencies it marks.
	public struct AbsentDeclarations: Sendable {
		/// Every declaration as written, and an absent declaration of each type no declaration fulfills.
		public let map: [TypeDescription: Instantiable]
		/// The dependencies `generate` reports: each required instantiated dependency no declaration fulfills, and each
		/// received dependency and alias nothing provides.
		public let unfulfilledDependencies: [UnfulfilledDependency]
		/// Where each of those received dependencies and aliases is declared.
		public let unfulfilledReceiveLocations: Set<Dependency.DeclarationLocation>
	}

	/// What `error` reports cannot be fulfilled, or `nil` when it reports anything else.
	private static func unfulfilledDependencies(reportedBy error: DependencyTreeGeneratorError) -> ReportedUnfulfilledDependencies? {
		var reported = ReportedUnfulfilledDependencies()
		var errors = [error]
		while let error = errors.popLast() {
			switch error {
			case let .independentErrors(independentErrors):
				errors.append(contentsOf: independentErrors)
			case let .noInstantiableFound(typeDescription, referencedBy, _, _, _):
				reported.typesNoDeclarationFulfills.insert(typeDescription)
				for case let location? in referencedBy.map(\.declarationLocation) {
					reported.instantiatingLocations.insert(location)
				}
			case let .unfulfillableProperties(unfulfillableProperties):
				for case let location? in unfulfillableProperties.map(\.declarationLocation) {
					reported.receiveLocations.insert(location)
				}
			case .unfilledHoles, .fillFindings, .holesInSeamsOfUnnamedModule, .hiddenReceivedProperties, .renamesContradictingOwnProperties, .forwardedPropertyHiddenInPromotedTree, .receivedPropertyHiddenInMockTree, .unpassableCycleLabel, .instantiableHasForwardedProperty, .constantDependencyCycleDetected, .dependencyReceivedInSameChainItIsInstantiated, .handWrittenMockSharesGeneratedMockName, .handWrittenMockSharesPublicMockName, .publicMockCannotBeGenerated, .nonSendableWrapperCapturedBySendableBuilder, .seamTierOmitsProvidedValue, .publicMockTierOmitsProvidedValue, .publicMockUnderOtherMockCondition, .seamModuleMockConditionDiffers, .configurationBuiltTwoWays, .repeatedDependencyLabels, .rejectedRenames, .unfulfilledMockParameters, .inaccessibleConstructions, .seam, .sourceLocated:
				return nil
			}
		}
		return reported
	}

	/// What an error reports cannot be fulfilled.
	private struct ReportedUnfulfilledDependencies {
		/// The types no declaration fulfills.
		var typesNoDeclarationFulfills = Set<TypeDescription>()
		/// Where each dependency that instantiates one of those types is declared.
		var instantiatingLocations = Set<Dependency.DeclarationLocation>()
		/// Where each received dependency and alias nothing provides is declared.
		var receiveLocations = Set<Dependency.DeclarationLocation>()
	}
}
