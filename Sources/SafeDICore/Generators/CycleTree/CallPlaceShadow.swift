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
	/// A place of today's tree that builds a scope as a property, with the declarations its path gives it, as the scopes
	/// above it declare them: each scope's declarations hide those above of their labels, and the property a place is
	/// built as is being built beneath it. A place inside a function a lazy cycle closes on is listed once for the call of
	/// the scope that declares the function and once for each scope that closes the cycle on it, each time with the
	/// declarations that call's path gives it: today one generator stands for the places of every call, and reads the
	/// function's parameters.
	struct PlaceContext {
		let place: String
		let generator: ScopeGenerator
		let scope: Scope
		let property: Property
		let nearestDeclarations: NearestDeclarations
		let lazilyInstantiatedInstanceProperties: Set<Property>
		/// The labels the place reads as a parameter of a function it is built in that the call passes `nil`: today's
		/// generator passes the parameter on, so it does not list a receive of such a label as passed `nil`, and the value
		/// is `nil` for every receive of the label.
		let labelsPassedNil: Set<String>
		/// Whether the place is walked for a call by a scope that closes the cycle as another property than the function
		/// was built for, a constant on a `LazilyInstantiated` of its label or the reverse (`PerTypePlan.twins`): today the
		/// call builds what the function's property builds, and a plan's call place builds the calling property.
		let isCalledAsTwin: Bool
	}

	/// A scope of today's tree that declares a builder function, which a scope beneath that closes a cycle on its
	/// declaration calls.
	struct FunctionPlace {
		let generator: ScopeGenerator
		let scope: Scope
		let property: Property
	}

	/// A walk of the places of a tree as today builds it, each with its context. A place's children are its scope's, index
	/// by index. The places of a function are walked again for each scope that closes a cycle on it, down to the scopes
	/// that close a cycle there: a call made inside such a call is not followed, a limit the rules file states. The places
	/// beneath the function such a call calls are walked only where `followCall()` is asked after `next()` returns it: a
	/// tree of screens that open each other calls each function along a number of paths that grows with every cycle.
	struct PlaceContextWalk {
		/// - Parameters:
		///   - rootScope: The scope `todaysTree` was built from.
		///   - nearestDeclarations: The declarations `todaysTree` was built beneath, with their lazily instantiated instances.
		init(
			ofTodaysTree todaysTree: ScopeGenerator,
			builtFrom rootScope: Scope,
			beneath nearestDeclarations: NearestDeclarations = NearestDeclarations(),
			lazilyInstantiatedInstanceProperties: Set<Property> = [],
		) {
			places = [Place(
				generator: todaysTree,
				scope: rootScope,
				nearestDeclarations: nearestDeclarations,
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
				labelsPassedNil: [],
				functions: [:],
				callDescription: nil,
				isCalledAsTwin: false,
			)]
		}

		/// The next place, and whether it is the function a scope that closes a cycle calls.
		mutating func next() -> (context: PlaceContext, isCalledByCycleClosingScope: Bool)? {
			calledPlace = nil
			while placesOfScope.isEmpty, let place = places.popLast() {
				placesOfScope = Self.childPlaces(of: place).reversed()
			}
			guard let (context, place, isCalledByCycleClosingScope) = placesOfScope.popLast() else { return nil }
			if isCalledByCycleClosingScope {
				calledPlace = place
			} else {
				places.append(place)
			}
			return (context, isCalledByCycleClosingScope)
		}

		/// Walks the places beneath the function the last place `next()` returned is, where a scope that closes a cycle
		/// calls it.
		mutating func followCall() {
			if let calledPlace {
				places.append(calledPlace)
			}
		}

		private struct Place {
			let generator: ScopeGenerator
			let scope: Scope
			let nearestDeclarations: NearestDeclarations
			let lazilyInstantiatedInstanceProperties: Set<Property>
			let labelsPassedNil: Set<String>
			let functions: [ScopeGenerator.BuiltDeclaration: FunctionPlace]
			let callDescription: String?
			let isCalledAsTwin: Bool
		}

		private var places: [Place]
		private var placesOfScope = [(context: PlaceContext, place: Place, isCalledByCycleClosingScope: Bool)]()
		private var calledPlace: Place?

		private static func childPlaces(of place: Place) -> [(context: PlaceContext, place: Place, isCalledByCycleClosingScope: Bool)] {
			let (generator, scope, functions, callDescription) = (place.generator, place.scope, place.functions, place.callDescription)
			var childPlaces = [(context: PlaceContext, place: Place, isCalledByCycleClosingScope: Bool)]()
			let childLabelsPassedNil = place.labelsPassedNil.subtracting(scope.declaredLabels)
			var childNearestDeclarations = place.nearestDeclarations
			childNearestDeclarations.replaceLabels(of: scope.sortedDeclaredPropertyForms)
			let childLazilyInstantiatedInstanceProperties = place.lazilyInstantiatedInstanceProperties
				.filter { !scope.declaredLabels.contains($0.label) }
				.union(scope.declaredLazilyInstantiatedInstanceProperties)
			for child in generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []) where scope.propertiesToGenerate.indices.contains(child.index) {
				if case let .instantiated(property, childScope, _) = scope.propertiesToGenerate[child.index] {
					// What the place of `function`, built by `child`'s call of it, is given: a member of a loop of builders
					// makes each wrapper its tree receives inside the loop again at the top of its function, its own included,
					// so that rebinding is the nearest declaration beneath it, and is not being built.
					func context(of function: FunctionPlace, describedAs description: String, isCalledAsTwin: Bool) -> PlaceContext {
						var placeNearestDeclarations = childNearestDeclarations
						placeNearestDeclarations.build(function.property)
						for reboundProperty in function.generator.reboundProperties {
							placeNearestDeclarations.replace(reboundProperty, providing: CycleParameter.forms(providedBy: reboundProperty))
						}
						return PlaceContext(
							place: description,
							generator: function.generator,
							scope: function.scope,
							property: function.property,
							nearestDeclarations: placeNearestDeclarations,
							lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties,
							labelsPassedNil: childLabelsPassedNil.union(child.generator.labelsOfCycleParametersPassedNil),
							isCalledAsTwin: isCalledAsTwin,
						)
					}
					if case .property(_, _, _, _, false, _) = child.generator.scopeData {
						let function = FunctionPlace(generator: child.generator, scope: childScope, property: property)
						let context = context(of: function, describedAs: callDescription.map { "\(child.generator.scopeData.asDOTNode) \($0)" } ?? child.generator.scopeData.asDOTNode, isCalledAsTwin: place.isCalledAsTwin)
						var childFunctions = functions
						if let declaration = child.generator.declaration {
							childFunctions[declaration] = function
						}
						childPlaces.append((context, Place(
							generator: child.generator,
							scope: childScope,
							nearestDeclarations: context.nearestDeclarations,
							lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties,
							labelsPassedNil: context.labelsPassedNil,
							functions: childFunctions,
							callDescription: callDescription,
							isCalledAsTwin: place.isCalledAsTwin,
						), false))
					} else if callDescription == nil,
					          let function = child.generator.closedOnDeclaration.flatMap({ functions[$0] })
					{
						// A scope that closes a cycle builds nothing: it is a call of the function it closes on, whose places
						// are walked again with what this call's path gives them.
						let description = "called by \(child.generator.scopeData.asDOTNode) in \(generator.scopeData.asDOTNode)"
						let context = context(of: function, describedAs: "\(function.generator.scopeData.asDOTNode) \(description)", isCalledAsTwin: property != function.property)
						childPlaces.append((context, Place(
							generator: function.generator,
							scope: function.scope,
							nearestDeclarations: context.nearestDeclarations,
							lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties,
							labelsPassedNil: context.labelsPassedNil,
							functions: functions,
							callDescription: description,
							isCalledAsTwin: property != function.property,
						), true))
					}
				}
			}
			return childPlaces
		}
	}

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
			var calledScopeByCallPlace = [ObjectIdentifier: Scope]()
			for (index, identifier) in graph.nodes.enumerated() {
				if let scope = scopeByIdentifier[identifier] {
					copyByIdentifier[identifier] = Scope(
						instantiable: scope.instantiable,
						dependenciesLeftOut: scope.dependenciesLeftOut,
						builtInlineSeamComment: scope.builtInlineSeamComment,
						isUnavailableDependency: scope.isUnavailableDependency,
					)
					if graph.isOnCycle(index) {
						let callPlace = Scope(instantiable: callPlaceInstantiable(of: scope, receiving: collectReceivedProperties(from: scope, cache: &cache)))
						callPlaceByIdentifier[identifier] = callPlace
						calledScopeByCallPlace[ObjectIdentifier(callPlace)] = scope
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
			self.calledScopeByCallPlace = calledScopeByCallPlace
			self.callPlaceByIdentifier = callPlaceByIdentifier
		}

		/// Whether a copy builds `scope` as a call place: the scope is on a cycle.
		func isOnCycle(_ scope: Scope) -> Bool {
			callPlaceByIdentifier[ObjectIdentifier(scope)] != nil
		}

		/// The scope on a cycle that `callPlace` stands for in a copy, or `nil` for any other scope.
		func scope(calledAt callPlace: Scope) -> Scope? {
			calledScopeByCallPlace[ObjectIdentifier(callPlace)]
		}

		/// The copy of `scope`: its own type, building each child on a cycle as a call place and every other child as its
		/// copy. `nil` for a scope the root does not reach.
		func copy(of scope: Scope) -> Scope? {
			copyByIdentifier[ObjectIdentifier(scope)]
		}

		private let copyByIdentifier: [ObjectIdentifier: Scope]
		private let calledScopeByCallPlace: [ObjectIdentifier: Scope]
		private let callPlaceByIdentifier: [ObjectIdentifier: Scope]
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
