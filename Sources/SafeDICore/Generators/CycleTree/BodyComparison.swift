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

extension DependencyTreeGenerator {
	/// Compares each place of a root's tree with a body built from its scope's copy beneath the answers its path gives
	/// the labels the scope's tree receives (`VariantBodyObservation`), and the bodies today's places take with those the
	/// root's plan builds with no tree of today's (`PlanBodiesObservation`, `PlanCallsObservation`). Does nothing where no test observes any.
	///
	/// A tree with a label no one parameter can pass is rejected (`validateCycleLabelsArePassable`), and is not compared:
	/// a body beneath a call's own answers passes a value there that today's parameter cannot carry.
	///
	/// - Parameters:
	///   - scope: The root's scope, in the map `frozenScopeMap` froze.
	///   - todaysTree: The generator today's build made of `scope`.
	///   - frozenScopeMap: The frozen map of the world `scope` is of: each body is built against a table of it.
	///   - cache: The received properties of the scopes of that world.
	static func compareBodies(
		ofRoot scope: Scope,
		todaysTree: ScopeGenerator,
		frozenScopeMap: FrozenScopeMap,
		declaredTypeNames: DeclaredTypeNames,
		cache: inout ReceivedPropertiesCache,
	) throws {
		let variantBodyObserver = VariantBodyObservation.observer
		let planBodiesObserver = PlanBodiesObservation.observer
		let planCallsObserver = PlanCallsObservation.observer
		let twinIdentityObserver = TwinIdentityObservation.observer
		guard variantBodyObserver != nil || planBodiesObserver != nil || planCallsObserver != nil || twinIdentityObserver != nil,
		      todaysTree.unpassableCycleLabelsInTree.isEmpty,
		      let shadow = CallPlaceShadow(root: scope, cache: &cache)
		else { return }
		var bodies = VariantBodies(frozenScopeMap: frozenScopeMap, declaredTypeNames: declaredTypeNames)
		// The calls of each function already compared, each by the answers its call's path gives the labels the
		// function's tree receives: the places beneath a call answered alike are given the same declarations.
		var callsCompared = [ObjectIdentifier: [(nearestDeclarations: [NearestDeclaration?], lazilyInstantiatedInstanceProperties: Set<Property>, labelsPassedNil: Set<String>)]]()
		// The bodies today's places of scopes on a cycle take, in the order the walk first meets each.
		var todaysBodies = [Int]()
		// The calls of today's tree that run another function than the plan's call names.
		var callsOfOtherFunction = [String]()
		var walk = PlaceContextWalk(ofTodaysTree: todaysTree, builtFrom: scope, twinValues: shadow.twinValues)
		while let (context, isCalledByCycleClosingScope) = walk.next() {
			if isCalledByCycleClosingScope {
				callsOfOtherFunction += VariantAnswers.placesCallingOtherFunctionThanPlan(at: context, twinValues: shadow.twinValues)
			}
			if let copy = shadow.copy(of: context.scope) {
				var labelSet = Set(Self.collectReceivedProperties(from: context.scope, cache: &cache).received.map(\.label))
				labelSet.insert(context.property.label)
				let labels = labelSet.sorted()
				let key = VariantBodyKey(scope: ObjectIdentifier(context.scope), property: context.property, twinsBeingBuilt: context.twinsBeingBuilt, isInSendableFamily: context.isInSendableFamily)
				// A label whose declaration the scopes above build after the place is `nil` in its tree.
				let answeredLabels = VariantAnswers.answeredLabels(labels, builtAfter: context.labelsBuiltAfter)
				let body = try bodies.body(
					of: copy,
					as: key,
					keyedBy: labels,
					answering: answeredLabels,
					beneath: context.nearestDeclarations,
					lazilyInstantiatedInstanceProperties: context.lazilyInstantiatedInstanceProperties,
					builtBy: (context.builder, context.erasedToConcreteExistential),
				)
				// Today's place reads a parameter of a function it is built in where the call's path declares the
				// label, and the parameter is `nil` where the call passes `nil`: every receive of that label is then
				// `nil`, as in a body no declaration answers the label for.
				var todaysUnavailableOptionalProperties = context.orderedUnavailableProperties
				if !context.labelsPassedNil.isDisjoint(with: labelSet) {
					let bodyWithoutAnswers = try bodies.body(
						of: copy,
						as: key,
						keyedBy: labels,
						answering: answeredLabels.filter { !context.labelsPassedNil.contains($0) },
						beneath: context.nearestDeclarations,
						lazilyInstantiatedInstanceProperties: context.lazilyInstantiatedInstanceProperties,
						builtBy: (context.builder, context.erasedToConcreteExistential),
					)
					todaysUnavailableOptionalProperties = todaysUnavailableOptionalProperties
						.filter { !context.labelsPassedNil.contains($0.label) }
						.union(bodies.bodies[bodyWithoutAnswers].generator.unavailableOptionalProperties.filter { context.labelsPassedNil.contains($0.label) })
				}
				if isCalledByCycleClosingScope {
					let call = (
						nearestDeclarations: bodies.bodies[body].answers,
						lazilyInstantiatedInstanceProperties: bodies.bodies[body].lazilyInstantiatedInstanceProperties,
						labelsPassedNil: context.labelsPassedNil.intersection(labelSet),
					)
					guard callsCompared[ObjectIdentifier(context.generator)]?.contains(where: { $0 == call }) != true else { continue }
					callsCompared[ObjectIdentifier(context.generator), default: []].append(call)
					walk.followCall()
				}
				if shadow.isOnCycle(context.scope), !todaysBodies.contains(body) {
					todaysBodies.append(body)
				}
				variantBodyObserver?(
					context.place,
					todaysUnavailableOptionalProperties.map(\.asSource).sorted(),
					bodies.bodies[body].generator.unavailableOptionalProperties.map(\.asSource).sorted(),
				)
				// The places inside the fills of a seam's or a public mock's call, built in the body as today's place builds them.
				if let variantBodyObserver {
					for (place, today, bodys) in Self.fillPlaces(ofCallBuiltToday: context.generator, inBody: bodies.bodies[body].generator, describedAs: context.place) {
						variantBodyObserver(place, today.unavailableOptionalProperties.map(\.asSource).sorted(), bodys.unavailableOptionalProperties.map(\.asSource).sorted())
					}
				}
			}
		}
		// The bodies the plan builds with no tree of today's: the root's, then the body of each call place a
		// body holds, beneath the answers that body's path gives it.
		if planBodiesObserver != nil || planCallsObserver != nil, let plan = try bodies.plan(ofRoot: scope, shadow: shadow, cache: &cache) {
			let bodiesOfPlan = plan.calledBodies
			planCallsObserver?(
				scope.instantiable.concreteInstantiable.asSource,
				([plan.rootBody] + bodiesOfPlan).flatMap { bodies.callDescriptions(of: $0) },
			)
			planBodiesObserver?(
				scope.instantiable.concreteInstantiable.asSource,
				bodiesOfPlan.map { bodies.bodies[$0].description },
				todaysBodies.filter { !bodiesOfPlan.contains($0) }.map { bodies.bodies[$0].description },
				shadow.twinValues.map { "\($0.concreteType.asSource) as \($0.property.asSource)" }.sorted(),
			)
		}
		if let twinIdentityObserver, !shadow.twinValues.isEmpty {
			let (table, record) = frozenScopeMap.freezing(rootScope: scope)
			twinIdentityObserver(
				scope.instantiable.concreteInstantiable.asSource,
				VariantAnswers.shadowsTwinValues(of: shadow),
				PerTypePlan(root: ConstructionScope(table: table, record: record)).map(VariantAnswers.plansTwinValues(of:)) ?? [],
				callsOfOtherFunction,
			)
		}
	}
}
