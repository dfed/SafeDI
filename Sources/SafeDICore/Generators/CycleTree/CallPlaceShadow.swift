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
		/// The place's position beneath the tree the walk started from: at each scope from that tree's root down, the
		/// index among the scope's `propertiesToGenerate` of the child that leads to the place. A place inside a function
		/// a scope that closes a cycle calls has the path of that scope, then the path from the function's scope.
		let path: [Int]
		/// The scope that builds the place, and whether it erases what the place builds to a concrete existential.
		let builder: Scope
		let erasedToConcreteExistential: Bool
		let nearestDeclarations: NearestDeclarations
		/// The declarations of the scope that builds the place, before the place's own property is being built.
		let enclosingNearestDeclarations: NearestDeclarations
		let lazilyInstantiatedInstanceProperties: Set<Property>
		/// The labels the place reads as a parameter of a function it is built in that the call passes `nil`: today's
		/// generator passes the parameter on, so it does not list a receive of such a label as passed `nil`, and the value
		/// is `nil` for every receive of the label.
		let labelsPassedNil: Set<String>
		/// The twin the place's path is building of each value two properties build (`CallPlaceShadow.twinValues`), the
		/// place's own included: a scope beneath that closes a cycle on the value calls that property's function.
		let twinsBeingBuilt: [TwinValue: Property]
		/// The properties today's build passes `nil` where it constructs the place's type, given the order the scopes above
		/// it build their children in: a receive only if available of a sibling built after the place, or after a scope
		/// above it, included.
		let orderedUnavailableProperties: Set<Property>
		/// The labels of the declarations the place's tree reads only if available that are built after it
		/// (`VariantAnswers.labelsBuiltAfter(_:besides:reboundBy:besidesParameters:)`): `nil` at the place, whatever declares them.
		let labelsBuiltAfter: Set<String>
		/// Whether the place is built in the `@Sendable` family (`VariantAnswers.isInSendableFamily(calledInSendableFunction:property:)`).
		let isInSendableFamily: Bool
	}

	/// A scope of today's tree that declares a builder function, which a scope beneath that closes a cycle on its
	/// declaration calls.
	struct FunctionPlace {
		let generator: ScopeGenerator
		let scope: Scope
		let property: Property
		let builder: Scope
		let erasedToConcreteExistential: Bool
		/// What today's build passes `nil` where the function constructs its type, and the labels built after the function
		/// is declared, which every call of it reads as the declaring place does (`PlaceContext`).
		let orderedUnavailableProperties: Set<Property>
		let labelsBuiltAfter: Set<String>
		/// The `propertiesGeneratedLater` of the scopes the function's body builds, given the order around its declaration.
		let bodyPropertiesGeneratedLater: Set<Property>
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
		///   - isInSendableFamily: Whether `todaysTree` is built inside a `@Sendable` function.
		///   - parameterLabelsByCallPlace: Where `todaysTree` is a body holding call places, the labels each call place's
		///     function can take as parameters (`CallPlaceShadow.parameterLabelsByCallPlace`).
		init(
			ofTodaysTree todaysTree: ScopeGenerator,
			builtFrom rootScope: Scope,
			beneath nearestDeclarations: NearestDeclarations = NearestDeclarations(),
			lazilyInstantiatedInstanceProperties: Set<Property> = [],
			twinValues: Set<TwinValue>,
			twinsBeingBuilt: [TwinValue: Property] = [:],
			isInSendableFamily: Bool = false,
			parameterLabelsByCallPlace: [ObjectIdentifier: Set<String>] = [:],
		) {
			self.twinValues = twinValues
			self.parameterLabelsByCallPlace = parameterLabelsByCallPlace
			places = [Place(
				generator: todaysTree,
				scope: rootScope,
				nearestDeclarations: nearestDeclarations,
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
				labelsPassedNil: [],
				functions: [:],
				callDescription: nil,
				twinsBeingBuilt: twinsBeingBuilt,
				path: [],
				propertiesGeneratedLater: [],
				labelsBuiltAfter: [],
				isInSendableFunction: isInSendableFamily,
			)]
		}

		/// The next place, and whether it is the function a scope that closes a cycle calls.
		mutating func next() -> (context: PlaceContext, isCalledByCycleClosingScope: Bool)? {
			calledPlace = nil
			while placesOfScope.isEmpty, let place = places.popLast() {
				placesOfScope = Self.childPlaces(of: place, twinValues: twinValues, parameterLabelsByCallPlace: parameterLabelsByCallPlace).reversed()
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
			let twinsBeingBuilt: [TwinValue: Property]
			let path: [Int]
			/// The `propertiesGeneratedLater` the place's children are ordered with.
			let propertiesGeneratedLater: Set<Property>
			/// The labels `nil` in the place's tree whatever declares them above it (`PlaceContext.labelsBuiltAfter`), a
			/// parameter a call passes `nil` as built after it included.
			let labelsBuiltAfter: Set<String>
			/// Whether the place's children are built inside a `@Sendable` function.
			let isInSendableFunction: Bool
		}

		private let twinValues: Set<TwinValue>
		private let parameterLabelsByCallPlace: [ObjectIdentifier: Set<String>]
		private var places: [Place]
		private var placesOfScope = [(context: PlaceContext, place: Place, isCalledByCycleClosingScope: Bool)]()
		private var calledPlace: Place?

		private static func childPlaces(of place: Place, twinValues: Set<TwinValue>, parameterLabelsByCallPlace: [ObjectIdentifier: Set<String>]) -> [(context: PlaceContext, place: Place, isCalledByCycleClosingScope: Bool)] {
			let (generator, scope, functions, callDescription) = (place.generator, place.scope, place.functions, place.callDescription)
			var childPlaces = [(context: PlaceContext, place: Place, isCalledByCycleClosingScope: Bool)]()
			let childLabelsPassedNil = place.labelsPassedNil.subtracting(scope.declaredLabels)
			let childLabelsBuiltAfter = place.labelsBuiltAfter.subtracting(scope.declaredLabels)
			var childNearestDeclarations = place.nearestDeclarations
			childNearestDeclarations.replaceLabels(of: scope.sortedDeclaredPropertyForms)
			let childLazilyInstantiatedInstanceProperties = place.lazilyInstantiatedInstanceProperties
				.filter { !scope.declaredLabels.contains($0.label) }
				.union(scope.declaredLazilyInstantiatedInstanceProperties)
			for child in generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: place.propertiesGeneratedLater) where scope.propertiesToGenerate.indices.contains(child.index) {
				if case let .instantiated(property, childScope, erasedToConcreteExistential) = scope.propertiesToGenerate[child.index] {
					// What the place of `function`, built by `child`'s call of it, is given: a member of a loop of builders
					// makes each wrapper its tree receives inside the loop again at the top of its function, its own included,
					// so that rebinding is the nearest declaration beneath it, and is not being built.
					func context(of function: FunctionPlace, describedAs description: String, twinsBeingBuilt: [TwinValue: Property], isInSendableFamily: Bool) -> PlaceContext {
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
							path: place.path + [child.index],
							builder: function.builder,
							erasedToConcreteExistential: function.erasedToConcreteExistential,
							nearestDeclarations: placeNearestDeclarations,
							enclosingNearestDeclarations: childNearestDeclarations,
							lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties,
							labelsPassedNil: childLabelsPassedNil.union(VariantAnswers.labelsOfCycleParametersPassedNil(by: child)),
							twinsBeingBuilt: twinsBeingBuilt,
							orderedUnavailableProperties: function.orderedUnavailableProperties,
							labelsBuiltAfter: function.labelsBuiltAfter,
							isInSendableFamily: isInSendableFamily,
						)
					}
					if case .property(_, _, _, _, false, _) = child.generator.scopeData {
						let function = FunctionPlace(
							generator: child.generator,
							scope: childScope,
							property: property,
							builder: scope,
							erasedToConcreteExistential: erasedToConcreteExistential,
							orderedUnavailableProperties: child.generator.mockLoweringBodyUnavailableProperties(child.unavailableProperties),
							labelsBuiltAfter: VariantAnswers.labelsBuiltAfter(child.propertiesGeneratedLater, besides: childLabelsBuiltAfter, reboundBy: child.generator, besidesParameters: parameterLabelsByCallPlace[ObjectIdentifier(childScope), default: []]),
							bodyPropertiesGeneratedLater: child.generator.mockLoweringBodyPropertiesGeneratedLater(child.propertiesGeneratedLater),
						)
						let isInSendableFamily = VariantAnswers.isInSendableFamily(calledInSendableFunction: place.isInSendableFunction, property: property)
						// The first property a path builds a twin value as is the one a call of the value beneath closes on.
						let twinValue = TwinValue(concreteType: childScope.instantiable.concreteInstantiable, property: property.asValidatedForDependencyCycles)
						var childTwinsBeingBuilt = place.twinsBeingBuilt
						if twinValues.contains(twinValue), childTwinsBeingBuilt[twinValue] == nil {
							childTwinsBeingBuilt[twinValue] = property
						}
						let context = context(of: function, describedAs: callDescription.map { "\(child.generator.scopeData.asDOTNode) \($0)" } ?? child.generator.scopeData.asDOTNode, twinsBeingBuilt: childTwinsBeingBuilt, isInSendableFamily: isInSendableFamily)
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
							twinsBeingBuilt: childTwinsBeingBuilt,
							path: context.path,
							propertiesGeneratedLater: function.bodyPropertiesGeneratedLater,
							labelsBuiltAfter: context.labelsBuiltAfter,
							isInSendableFunction: isInSendableFamily,
						), false))
					} else if callDescription == nil,
					          let function = child.generator.closedOnDeclaration.flatMap({ functions[$0] })
					{
						// A scope that closes a cycle builds nothing: it is a call of the function it closes on, whose places
						// are walked again with what this call's path gives them.
						let description = "called by \(child.generator.scopeData.asDOTNode) in \(generator.scopeData.asDOTNode)"
						// The function is called from inside a `@Sendable` function where the closing scope is, or from inside its own
						// `Sendable` wrapper's closure.
						let isInSendableFamily = VariantAnswers.isInSendableFamily(calledInSendableFunction: place.isInSendableFunction, property: property)
						var context = context(of: function, describedAs: "\(function.generator.scopeData.asDOTNode) \(description)", twinsBeingBuilt: place.twinsBeingBuilt, isInSendableFamily: isInSendableFamily)
						// The function reads its parameters from this call, and everything else where it is declared.
						context = context.answeringCall(of: function, by: child, passingOnNilFor: childLabelsBuiltAfter)
						childPlaces.append((context, Place(
							generator: function.generator,
							scope: function.scope,
							nearestDeclarations: context.nearestDeclarations,
							lazilyInstantiatedInstanceProperties: childLazilyInstantiatedInstanceProperties,
							labelsPassedNil: context.labelsPassedNil,
							functions: functions,
							callDescription: description,
							twinsBeingBuilt: place.twinsBeingBuilt,
							path: context.path,
							propertiesGeneratedLater: function.bodyPropertiesGeneratedLater,
							labelsBuiltAfter: context.labelsBuiltAfter,
							isInSendableFunction: isInSendableFamily,
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
			var labelsDeclaredByComponent = [Int: Set<String>]()
			for (index, identifier) in graph.nodes.enumerated() where graph.isOnCycle(index) {
				if let scope = scopeByIdentifier[identifier] {
					labelsDeclaredByComponent[graph.componentByNode[index], default: []].formUnion(scope.declaredLabels)
				}
			}
			var copyByIdentifier = [ObjectIdentifier: Scope]()
			var callPlaceByIdentifier = [ObjectIdentifier: Scope]()
			var parameterLabelsByCallPlace = [ObjectIdentifier: Set<String>]()
			var calledScopeByCallPlace = [ObjectIdentifier: Scope]()
			for (index, identifier) in graph.nodes.enumerated() {
				if let scope = scopeByIdentifier[identifier] {
					// A copy of a seam's or a public mock's call keeps the call and the fills it passes, which its body builds as
					// today's place does (`FillEdges` carries what they read of the caller). A call builds no child, so it is on
					// no cycle and never a call place.
					let copy = Scope(
						instantiable: scope.instantiable,
						dependenciesLeftOut: scope.dependenciesLeftOut,
						builtInlineSeamComment: scope.builtInlineSeamComment,
						seamCall: scope.seamCall,
						publicMockCall: scope.publicMockCall,
						isUnavailableDependency: scope.isUnavailableDependency,
					)
					copy.holeArguments = scope.holeArguments
					copy.fillReceivedProperties = scope.fillReceivedProperties
					copy.fillLabelsReadOnlyIfAvailable = scope.fillLabelsReadOnlyIfAvailable
					copyByIdentifier[identifier] = copy
					if graph.isOnCycle(index) {
						let callPlace = Scope(instantiable: callPlaceInstantiable(of: scope, receiving: collectReceivedProperties(from: scope, cache: &cache)), isCallPlace: true)
						callPlaceByIdentifier[identifier] = callPlace
						calledScopeByCallPlace[ObjectIdentifier(callPlace)] = scope
						parameterLabelsByCallPlace[ObjectIdentifier(callPlace)] = labelsDeclaredByComponent[graph.componentByNode[index], default: []].subtracting(scope.declaredLabels)
					}
				}
			}
			var propertiesByTwinValue = [TwinValue: Set<Property>]()
			for identifier in graph.nodes {
				if let scope = scopeByIdentifier[identifier], let copy = copyByIdentifier[identifier] {
					for propertyToGenerate in scope.propertiesToGenerate {
						switch propertyToGenerate {
						case let .instantiated(property, childScope, erasedToConcreteExistential):
							if let child = callPlaceByIdentifier[ObjectIdentifier(childScope)] ?? copyByIdentifier[ObjectIdentifier(childScope)] {
								copy.propertiesToGenerate.append(.instantiated(property, child, erasedToConcreteExistential: erasedToConcreteExistential))
							}
							if callPlaceByIdentifier[ObjectIdentifier(childScope)] != nil {
								propertiesByTwinValue[TwinValue(concreteType: childScope.instantiable.concreteInstantiable, property: property.asValidatedForDependencyCycles), default: []].insert(property)
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
			self.parameterLabelsByCallPlace = parameterLabelsByCallPlace
			twinValues = Set(propertiesByTwinValue.lazy.filter { $0.value.count > 1 }.map(\.key))
		}

		/// The values two properties build of one type on a cycle, a constant and a `LazilyInstantiated` of it
		/// (`PerTypePlan.twins`): a cycle closes on whichever of the two its path built first.
		let twinValues: Set<TwinValue>

		/// The labels the function each call place stands for can take as parameters of a lazy cycle closed on it, by call
		/// place: those another scope of its strongly connected component declares (`CycleParameter`). A call place holds
		/// none of the function's tree, so the label a loop of builders would make again in its function is no rebinding
		/// there where the function takes it as a parameter (`ScopeGenerator.reboundProperties`). Holds more labels than
		/// a path's function takes: one declared in the component off every path between the function and a scope closing
		/// the cycle on it.
		let parameterLabelsByCallPlace: [ObjectIdentifier: Set<String>]

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
