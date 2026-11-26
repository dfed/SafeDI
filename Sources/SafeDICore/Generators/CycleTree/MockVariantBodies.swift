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

/// Lets a test compare a mock root's tree with the bodies its plan builds, as `VariantBodyObservation` and
/// `PlanBodiesObservation` do for a production root's. Test only.
public enum MockVariantBodyObservation {
	/// Called, for each place of a mock root's tree that reaches a cycle, with the mocked type, what the place is, and
	/// the receives today's place and its body pass `nil`, each sorted.
	@TaskLocal public static var observer: (@Sendable (_ mockRoot: String, _ place: String, _ todaysUnavailableProperties: [String], _ bodysUnavailableProperties: [String]) -> Void)?
	/// Called, for each mock root that reaches a cycle, with the mocked type, each body of a type on a cycle the plan
	/// builds, in the order the plan first calls it, and the bodies today's places of such types take that the plan does
	/// not build.
	@TaskLocal public static var planObserver: (@Sendable (_ mockRoot: String, _ bodiesOfPlan: [String], _ todaysBodiesPlanLacks: [String]) -> Void)?
}

extension DependencyTreeGenerator {
	/// Compares each place of a mock root's tree with a body built from its scope's copy beneath the answers its path
	/// gives it, and the bodies the plan builds with no tree of today's with the bodies today's places take, where a test
	/// sets `MockVariantBodyObservation`'s observers.
	///
	/// A mock root differs from a production root in what its tree is given and how its root declares: the mock binds
	/// every received property it does not promote (`boundProperties`), passing `nil` where `receivesPassedNil` says
	/// production does; its declarations join those bindings; and the trees of the dependencies it promotes are built
	/// beneath the bindings before its own required receives pin any. Each body is built beneath its answers as a place of
	/// a mock's tree is (`VariantBodies(…forMockGeneration: true)`), and the answers keep what the bindings pass `nil`
	/// (`NearestDeclarations.keeping(labels:)`). Holds every body for as long as the comparison runs.
	///
	/// What override a place reads is no input of its body: the places of one type read different entries of
	/// `SafeDIOverrides`, the kind of read (a configuration, a closure, a hand-written mock's) is the declaration's, and a
	/// body is to be handed its configuration by each call.
	static func compareMockBodies(
		ofMockOf instantiable: Instantiable,
		mockRootScope: Scope,
		todaysTree: ScopeGenerator,
		boundProperties: Set<Property>,
		receivesPassedNil: MockReceivesPassedNil,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		frozenScopeMap: FrozenScopeMap,
		declaredTypeNames: DeclaredTypeNames,
		cache: inout ReceivedPropertiesCache,
	) throws {
		let observer = MockVariantBodyObservation.observer
		let planObserver = MockVariantBodyObservation.planObserver
		// A tree that calls another module's public mock is not compared: the call reads the caller's declarations for its
		// fills' trees, as a production root's seam call does, and a body has no edge for a fill.
		guard observer != nil || planObserver != nil,
		      !reachesCallOfPublicMock(from: mockRootScope),
		      let shadow = CallPlaceShadow(root: mockRootScope, cache: &cache)
		else { return }
		let mockRoot = instantiable.concreteInstantiable.asSource
		let rootNearestDeclarations = NearestDeclarations.binding(boundProperties, passingNilTo: receivesPassedNil)
		var bodies = VariantBodies(frozenScopeMap: frozenScopeMap, declaredTypeNames: declaredTypeNames, forMockGeneration: true)
		// The calls of each function already compared, each by the answers its call's path gives the labels the function's
		// tree receives: the places beneath a call answered alike are given the same declarations.
		var callsCompared = [ObjectIdentifier: [(nearestDeclarations: [NearestDeclaration?], lazilyInstantiatedInstanceProperties: Set<Property>, labelsPassedNil: Set<String>)]]()
		// The bodies today's places of scopes on a cycle take, in the order the walk first meets each.
		var todaysBodies = [Int]()
		var walk = PlaceContextWalk(
			ofTodaysTree: todaysTree,
			builtFrom: mockRootScope,
			beneath: rootNearestDeclarations,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			twinValues: shadow.twinValues,
			isMockRoot: true,
		)
		while let (context, isCalledByCycleClosingScope) = walk.next() {
			if let copy = shadow.copy(of: context.scope) {
				let labels = labels(readBy: context.scope, builtAs: context.property, cache: &cache)
				let key = VariantBodyKey(scope: ObjectIdentifier(context.scope), property: context.property, twinsBeingBuilt: context.twinsBeingBuilt)
				let body = try bodies.body(
					of: copy,
					as: key,
					keyedBy: labels,
					answering: labels,
					beneath: context.nearestDeclarations,
					lazilyInstantiatedInstanceProperties: context.lazilyInstantiatedInstanceProperties,
				)
				// Today's place reads a parameter of a function it is built in where the call's path declares the label,
				// and the parameter is `nil` where the call passes `nil`: every receive of that label is then `nil`, as in
				// a body no declaration answers the label for.
				var todaysUnavailableOptionalProperties = context.generator.unavailableOptionalProperties
				let labelsPassedNil = context.labelsPassedNil.intersection(labels)
				if !labelsPassedNil.isEmpty {
					let bodyWithoutAnswers = try bodies.body(
						of: copy,
						as: key,
						keyedBy: labels,
						answering: labels.filter { !labelsPassedNil.contains($0) },
						beneath: context.nearestDeclarations,
						lazilyInstantiatedInstanceProperties: context.lazilyInstantiatedInstanceProperties,
					)
					todaysUnavailableOptionalProperties = todaysUnavailableOptionalProperties
						.filter { !labelsPassedNil.contains($0.label) }
						.union(bodies.bodies[bodyWithoutAnswers].generator.unavailableOptionalProperties.filter { labelsPassedNil.contains($0.label) })
				}
				if isCalledByCycleClosingScope {
					let call = (
						nearestDeclarations: bodies.bodies[body].answers,
						lazilyInstantiatedInstanceProperties: bodies.bodies[body].lazilyInstantiatedInstanceProperties,
						labelsPassedNil: labelsPassedNil,
					)
					guard callsCompared[ObjectIdentifier(context.generator)]?.contains(where: { $0 == call }) != true else { continue }
					callsCompared[ObjectIdentifier(context.generator), default: []].append(call)
					walk.followCall()
				}
				if shadow.isOnCycle(context.scope), !todaysBodies.contains(body) {
					todaysBodies.append(body)
				}
				observer?(
					mockRoot,
					context.place,
					todaysUnavailableOptionalProperties.map(\.asSource).sorted(),
					bodies.bodies[body].generator.unavailableOptionalProperties.map(\.asSource).sorted(),
				)
			}
		}
		// The bodies the plan builds with no tree of today's: the root's, beneath every binding the mock gives its tree,
		// then the body of each call place a body holds, beneath the answers that body's path gives it.
		if let planObserver, let rootCopy = shadow.copy(of: mockRootScope) {
			let rootLabels = Set(boundProperties.map(\.label)).sorted()
			var bodiesOfPlan = [Int]()
			var bodiesToWalk = try [bodies.body(
				of: rootCopy,
				as: VariantBodyKey(scope: ObjectIdentifier(mockRootScope), property: nil, twinsBeingBuilt: [:]),
				keyedBy: rootLabels,
				answering: rootLabels,
				beneath: rootNearestDeclarations,
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
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
					isMockRoot: body.key.property == nil,
				)
				while let (context, _) = bodyWalk.next() {
					if let calledScope = shadow.scope(calledAt: context.scope), let calledCopy = shadow.copy(of: calledScope) {
						let labels = labels(readBy: calledScope, builtAs: context.property, cache: &cache)
						// A call is of the function's property: where the path is building the value the call place builds as
						// its twin, the call closes the cycle on that property's function, beneath the calling scope's
						// declarations.
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
						)
						if !bodiesOfPlan.contains(calledBody) {
							bodiesOfPlan.append(calledBody)
							bodiesToWalk.append(calledBody)
						}
					}
				}
			}
			planObserver(
				mockRoot,
				bodiesOfPlan.map { bodies.bodies[$0].description },
				todaysBodies.filter { !bodiesOfPlan.contains($0) }.map { bodies.bodies[$0].description },
			)
		}
	}

	/// Whether `scope`'s tree instantiates a call of another module's public mock.
	private static func reachesCallOfPublicMock(from scope: Scope) -> Bool {
		var visited = Set<ObjectIdentifier>()
		var scopesToVisit = [scope]
		while let scope = scopesToVisit.popLast() {
			guard visited.insert(ObjectIdentifier(scope)).inserted else { continue }
			guard scope.publicMockCall == nil else { return true }
			for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate {
				scopesToVisit.append(childScope)
			}
		}
		return false
	}

	/// The labels a body of `scope` built as `property` is keyed by: those its tree receives, and its own.
	private static func labels(readBy scope: Scope, builtAs property: Property, cache: inout ReceivedPropertiesCache) -> [String] {
		var labelSet = Set(collectReceivedProperties(from: scope, cache: &cache).received.map(\.label))
		labelSet.insert(property.label)
		return labelSet.sorted()
	}
}
