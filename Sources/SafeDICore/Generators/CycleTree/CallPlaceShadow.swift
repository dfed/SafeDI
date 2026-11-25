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

/// The test hook that compares the order a scope builds its children in today with the order it would build them in if
/// each child on a cycle were a call place: test only.
public enum CallPlaceOrderObservation {
	/// Called, when set, for each place of a production root's tree that reaches a cycle, where the place builds two or
	/// more children: the place's root type or property, the order today's tree builds its children in there, and the
	/// order the place's scope builds them in where each child on a cycle is a call place, each as indices among the
	/// scope's children.
	@TaskLocal public static var observer: (@Sendable (_ scope: String, _ todaysOrder: [Int], _ callPlaceOrder: [Int]) -> Void)?
}

extension DependencyTreeGenerator {
	/// The scopes a production root reaches, each beside a copy whose children on a cycle are call places: scopes with no
	/// children whose types receive what the child's whole tree receives from above it (`collectReceivedProperties`, the
	/// least sets, which no order of siblings feeds).
	///
	/// A first model, read by a test's comparison only: a call place does not yet carry what its tree requires through an
	/// alias received only if available. Holds one copy and one call place per scope reached, for as long as the
	/// comparison of one root runs.
	struct CallPlaceShadow {
		/// `nil` where `root` reaches no cycle.
		init?(root: Scope, cache: inout ReceivedPropertiesCache) {
			var scopeByIdentifier = [ObjectIdentifier(root): root]
			let graph = OrderedGraph(root: ObjectIdentifier(root)) { identifier in
				var targets = [ObjectIdentifier]()
				if let scope = scopeByIdentifier[identifier] {
					for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate {
						scopeByIdentifier[ObjectIdentifier(childScope)] = childScope
						targets.append(ObjectIdentifier(childScope))
					}
				}
				return targets
			}
			guard graph.nodes.indices.contains(where: { graph.isOnCycle($0) }) else { return nil }
			var copyByIdentifier = [ObjectIdentifier: Scope]()
			var callPlaceByIdentifier = [ObjectIdentifier: Scope]()
			for (index, identifier) in graph.nodes.enumerated() {
				if let scope = scopeByIdentifier[identifier] {
					copyByIdentifier[identifier] = Scope(
						instantiable: scope.instantiable,
						dependenciesLeftOut: scope.dependenciesLeftOut,
						builtInlineSeamComment: scope.builtInlineSeamComment,
						isUnavailableDependency: scope.isUnavailableDependency,
					)
					if graph.isOnCycle(index) {
						callPlaceByIdentifier[identifier] = Scope(instantiable: callPlaceInstantiable(of: scope, receiving: collectReceivedProperties(from: scope, cache: &cache)))
					}
				}
			}
			for identifier in graph.nodes {
				if let scope = scopeByIdentifier[identifier], let copy = copyByIdentifier[identifier] {
					for propertyToGenerate in scope.propertiesToGenerate {
						switch propertyToGenerate {
						case let .instantiated(property, childScope, erasedToConcreteExistential):
							if let child = callPlaceByIdentifier[ObjectIdentifier(childScope)] ?? copyByIdentifier[ObjectIdentifier(childScope)] {
								copy.propertiesToGenerate.append(.instantiated(property, child, erasedToConcreteExistential: erasedToConcreteExistential))
							}
						case .hole, .aliased:
							copy.propertiesToGenerate.append(propertyToGenerate)
						}
					}
				}
			}
			self.copyByIdentifier = copyByIdentifier
		}

		/// The copy of `scope`: its own type, building each child on a cycle as a call place and every other child as its
		/// copy. `nil` for a scope the root does not reach.
		func copy(of scope: Scope) -> Scope? {
			copyByIdentifier[ObjectIdentifier(scope)]
		}

		private let copyByIdentifier: [ObjectIdentifier: Scope]
	}

	/// The type of `scope` as a call place: its own type and construction, receiving `receivedProperties`, each only if
	/// available where every receiver beneath receives it so, in `Property` order.
	private static func callPlaceInstantiable(of scope: Scope, receiving receivedProperties: ReceivedProperties) -> Instantiable {
		let instantiable = scope.instantiable
		let received = receivedProperties.received.sorted()
		var callPlace = Instantiable(
			instantiableType: instantiable.concreteInstantiable,
			isRoot: false,
			initializer: Initializer(
				arguments: received.map { property in
					Initializer.Argument(
						innerLabel: property.label,
						typeDescription: property.asFunctionParamter.typeDescription,
						defaultValueExpression: nil,
					)
				},
			),
			additionalInstantiables: Array(instantiable.instantiableTypes.dropFirst()),
			dependencies: received.map { property in
				Dependency(
					property: property,
					source: .received(onlyIfAvailable: receivedProperties.onlyIfAvailable.contains(property)),
					declarationLocation: instantiable.declarationLocation,
				)
			},
			declarationType: instantiable.declarationType,
			access: instantiable.access,
			enclosingTypeAccess: instantiable.enclosingTypeAccess,
			enclosingExtensionAccess: instantiable.enclosingExtensionAccess,
			mockAttributes: instantiable.mockAttributes,
			declarationLocation: instantiable.declarationLocation,
			moduleName: instantiable.moduleName,
			packageName: instantiable.packageName,
		)
		callPlace.sourceFilePath = instantiable.sourceFilePath
		return callPlace
	}

	/// Each place of `todaysTree` that builds two or more children: what the place is, the scope it builds, and the order
	/// it builds the scope's children in. `rootScope` is the scope `todaysTree` was built from; a place's children are
	/// its scope's, index by index.
	static func siblingOrders(ofTodaysTree todaysTree: ScopeGenerator, builtFrom rootScope: Scope) -> [(place: String, scope: Scope, order: [Int])] {
		var orders = [(place: String, scope: Scope, order: [Int])]()
		var places = [(generator: todaysTree, scope: rootScope)]
		while let (generator, scope) = places.popLast() {
			let children = generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: [])
			if children.count > 1 {
				orders.append((place: generator.scopeData.asDOTNode, scope: scope, order: children.map(\.index)))
			}
			for child in children where scope.propertiesToGenerate.indices.contains(child.index) {
				if case let .instantiated(_, childScope, _) = scope.propertiesToGenerate[child.index] {
					places.append((generator: child.generator, scope: childScope))
				}
			}
		}
		return orders
	}
}
