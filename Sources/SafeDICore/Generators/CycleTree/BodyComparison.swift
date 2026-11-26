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
	/// root's plan builds with no tree of today's (`PlanBodiesObservation`). Does nothing where no test observes either.
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
		guard variantBodyObserver != nil || planBodiesObserver != nil,
		      todaysTree.unpassableCycleLabelsInTree.isEmpty,
		      let shadow = CallPlaceShadow(root: scope, cache: &cache)
		else { return }
		var bodies = VariantBodies(frozenScopeMap: frozenScopeMap, declaredTypeNames: declaredTypeNames)
		// The calls of each function already compared, each by the answers its call's path gives the labels the
		// function's tree receives: the places beneath a call answered alike are given the same declarations.
		var callsCompared = [ObjectIdentifier: [(nearestDeclarations: [NearestDeclaration?], lazilyInstantiatedInstanceProperties: Set<Property>, labelsPassedNil: Set<String>)]]()
		// The bodies today's places of scopes on a cycle take, in the order the walk first meets each.
		var todaysBodies = [Int]()
		var walk = PlaceContextWalk(ofTodaysTree: todaysTree, builtFrom: scope, twinValues: shadow.twinValues)
		while let (context, isCalledByCycleClosingScope) = walk.next() {
			if let copy = shadow.copy(of: context.scope) {
				var labelSet = Set(Self.collectReceivedProperties(from: context.scope, cache: &cache).received.map(\.label))
				labelSet.insert(context.property.label)
				let labels = labelSet.sorted()
				let key = VariantBodyKey(scope: ObjectIdentifier(context.scope), property: context.property, twinsBeingBuilt: context.twinsBeingBuilt)
				let body = try bodies.body(
					of: copy,
					as: key,
					keyedBy: labels,
					answering: labels,
					beneath: context.nearestDeclarations,
					lazilyInstantiatedInstanceProperties: context.lazilyInstantiatedInstanceProperties,
					builtBy: (context.builder, context.erasedToConcreteExistential),
				)
				// Today's place reads a parameter of a function it is built in where the call's path declares the
				// label, and the parameter is `nil` where the call passes `nil`: every receive of that label is then
				// `nil`, as in a body no declaration answers the label for.
				var todaysUnavailableOptionalProperties = context.generator.unavailableOptionalProperties
				if !context.labelsPassedNil.isDisjoint(with: labelSet) {
					let bodyWithoutAnswers = try bodies.body(
						of: copy,
						as: key,
						keyedBy: labels,
						answering: labels.filter { !context.labelsPassedNil.contains($0) },
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
			}
		}
		// The bodies the plan builds with no tree of today's: the root's, then the body of each call place a
		// body holds, beneath the answers that body's path gives it.
		if let planBodiesObserver, let rootCopy = shadow.copy(of: scope) {
			var bodiesOfPlan = [Int]()
			var bodiesToWalk = try [bodies.body(
				of: rootCopy,
				as: VariantBodyKey(scope: ObjectIdentifier(scope), property: nil, twinsBeingBuilt: [:]),
				keyedBy: [],
				answering: [],
				beneath: NearestDeclarations(),
				lazilyInstantiatedInstanceProperties: [],
			)]
			while let bodyToWalk = bodiesToWalk.popLast() {
				let body = bodies.bodies[bodyToWalk]
				var bodyWalk = PlaceContextWalk(
					ofTodaysTree: body.generator,
					builtFrom: body.copy,
					beneath: body.nearestDeclarations,
					lazilyInstantiatedInstanceProperties: body.lazilyInstantiatedInstanceProperties,
					twinValues: shadow.twinValues,
					twinsBeingBuilt: body.key.twinsBeingBuilt,
				)
				while let (context, _) = bodyWalk.next() {
					if let calledScope = shadow.scope(calledAt: context.scope), let calledCopy = shadow.copy(of: calledScope) {
						var labelSet = Set(Self.collectReceivedProperties(from: calledScope, cache: &cache).received.map(\.label))
						labelSet.insert(context.property.label)
						let labels = labelSet.sorted()
						// A call is of the function's property: where the path is building the value the call place
						// builds as its twin, a `LazilyInstantiated` of a constant or the reverse, the call closes the
						// cycle on that property's function, beneath the calling scope's declarations.
						let twinValue = TwinValue(concreteType: calledScope.instantiable.concreteInstantiable, property: context.property.asValidatedForDependencyCycles)
						let functionProperty = context.twinsBeingBuilt[twinValue] ?? context.property
						var calledNearestDeclarations = context.nearestDeclarations
						if functionProperty != context.property {
							calledNearestDeclarations = context.enclosingNearestDeclarations
							calledNearestDeclarations.build(functionProperty)
						}
						let calledBody = try bodies.body(
							of: calledCopy,
							as: VariantBodyKey(scope: ObjectIdentifier(calledScope), property: functionProperty, twinsBeingBuilt: context.twinsBeingBuilt),
							keyedBy: labels,
							answering: labels,
							beneath: calledNearestDeclarations,
							lazilyInstantiatedInstanceProperties: context.lazilyInstantiatedInstanceProperties,
							builtBy: (context.builder, context.erasedToConcreteExistential),
						)
						if !bodiesOfPlan.contains(calledBody) {
							bodiesOfPlan.append(calledBody)
							bodiesToWalk.append(calledBody)
						}
					}
				}
			}
			planBodiesObserver(
				scope.instantiable.concreteInstantiable.asSource,
				bodiesOfPlan.map { bodies.bodies[$0].description },
				todaysBodies.filter { !bodiesOfPlan.contains($0) }.map { bodies.bodies[$0].description },
				shadow.twinValues.map { "\($0.concreteType.asSource) as \($0.property.asSource)" }.sorted(),
			)
		}
	}
}
