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

/// Lets a test compare, for each place of a production root's tree, which of its type's receives today's build passes
/// `nil` with which a body passes `nil` that is built from the scope's copy with call places beneath only the nearest
/// declarations of the labels the scope's tree receives and of the label it is built as: the answers a body is keyed by.
public enum VariantBodyObservation {
	/// Called with what the place is and the two sets of properties passed `nil`, each sorted.
	@TaskLocal public static var observer: (@Sendable (_ place: String, _ todaysUnavailableProperties: [String], _ bodysUnavailableProperties: [String]) -> Void)?
}

/// Lets a test see the bodies a production root's plan builds without today's tree: the root's own, then the body of
/// each call place a body holds, beneath the answers the body's path gives it, until no body holds a call answered
/// anew. Test only.
public enum PlanBodiesObservation {
	/// Called for each root that reaches a cycle with the root's type, each body of a type on a cycle the plan builds, in
	/// the order the plan first calls it, the bodies today's places of such types take that the plan does not build, and
	/// the values two properties of the root's tree build as twins (`CallPlaceShadow.twinValues`), sorted.
	@TaskLocal public static var observer: (@Sendable (_ root: String, _ bodiesOfPlan: [String], _ todaysBodiesPlanLacks: [String], _ twinValues: [String]) -> Void)?
}

/// Lets a test see the calls each body of a production root's plan makes (`VariantBodies.calls(of:)`). Test only.
public enum PlanCallsObservation {
	/// Called for each root that reaches a cycle with the root's type and a line per call of the root's body, then of
	/// each body the plan builds, in the order the plan first calls it: the calling body's generator and position, the
	/// call place's path and property, the position of the body called, and what answers each label that body is keyed by.
	@TaskLocal public static var observer: (@Sendable (_ root: String, _ calls: [String]) -> Void)?
}

extension DependencyTreeGenerator {
	/// What the bodies of a root are kept by: the scope built and the property it is built as, `nil` for the root's own.
	struct VariantBodyKey: Hashable {
		let scope: ObjectIdentifier
		let property: Property?
		/// The twin a path is building of each value two properties build (`CallPlaceShadow.twinValues`): a call of the
		/// value beneath closes the cycle on that property's function, whichever property makes the call.
		let twinsBeingBuilt: [TwinValue: Property]
	}

	/// A type on a cycle and a property that builds it, as cycle validation sees the property: what a cycle closes on.
	struct TwinValue: Hashable {
		let concreteType: TypeDescription
		let property: Property
	}

	/// The bodies of one root built so far: each a generator built from a scope's copy with call places
	/// (`CallPlaceShadow`), beneath only the declarations that answer some of the labels its tree receives. One body is
	/// built per scope, property, answers and lazily instantiated instances.
	///
	/// Built only where a test compares bodies. Holds every body's generator and declarations for as long as the
	/// comparison of one root runs.
	struct VariantBodies {
		struct Body {
			let key: VariantBodyKey
			let copy: Scope
			/// The labels the body is keyed by, sorted, and the declaration that answers each, `nil` where none does.
			let labels: [String]
			let answers: [NearestDeclaration?]
			let nearestDeclarations: NearestDeclarations
			let lazilyInstantiatedInstanceProperties: Set<Property>
			/// The labels the body takes as an optional parameter, whatever its calls answer them (`OptionalParameter`).
			let labelsTakenOptionally: Set<String>
			let generator: ScopeGenerator
			/// What the body's answers are to a call of it, one per label of `labels`: nothing where no declaration answers
			/// the label; a declaration being built where its path is building a form of it; the instance of a lazily
			/// instantiated declaration where the body reads the label through one; else the declaration. Where an answer
			/// hands its readers more than one property, the first in property order names it. Made once, with the body.
			let planAnswers: [Answer]

			init(
				key: VariantBodyKey,
				copy: Scope,
				labels: [String],
				answers: [NearestDeclaration?],
				nearestDeclarations: NearestDeclarations,
				lazilyInstantiatedInstanceProperties: Set<Property>,
				labelsTakenOptionally: Set<String>,
				generator: ScopeGenerator,
			) {
				self.key = key
				self.copy = copy
				self.labels = labels
				self.answers = answers
				self.nearestDeclarations = nearestDeclarations
				self.lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
				self.labelsTakenOptionally = labelsTakenOptionally
				self.generator = generator
				var instancePropertiesByLabel = [String: Property]()
				for instance in lazilyInstantiatedInstanceProperties {
					instancePropertiesByLabel[instance.label] = min(instance, instancePropertiesByLabel[instance.label] ?? instance)
				}
				planAnswers = zip(labels, answers).map { label, answer in
					guard let answer, let property = answer.bindings.values.min() else { return .none }
					if !answer.formsBeingBuilt.isEmpty {
						return .declared(property, isBeingBuilt: true)
					} else if let instance = instancePropertiesByLabel[label] {
						return .instance(of: answer.bindings[instance] ?? property)
					} else {
						return .declared(property, isBeingBuilt: false)
					}
				}
			}

			/// The body's type and property, then each label with the properties its answer hands its readers.
			var description: String {
				var description = copy.instantiable.concreteInstantiable.asSource
				if let property = key.property {
					description.append(" as \(property.asSource)")
				}
				for (label, answer) in zip(labels, answers) {
					if let answer {
						let properties = Set(answer.bindings.values.map(\.asSource)).sorted().joined(separator: " or ")
						description.append(" [\(label) = \(properties)\(answer.formsBeingBuilt.isEmpty ? "" : ", being built")\(labelsTakenOptionally.contains(label) ? ", optional" : "")]")
					} else {
						description.append(" [\(label) = nil]")
					}
				}
				for twin in key.twinsBeingBuilt.values.map(\.asSource).sorted() {
					description.append(" [building \(twin)]")
				}
				return description
			}
		}

		/// A call a body makes: a child on a cycle, which the body's generator holds as a call place.
		struct Call {
			/// Where the call place is in the calling body's generator: at each scope from the body's own down, the index
			/// among the scope's `propertiesToGenerate` of the child that leads to it.
			let path: [Int]
			/// The property the call place is built as.
			let property: Property
			/// The position of the body called.
			let calledBody: Int
			/// What the called body's answers are, one per label of its `labels` (`Body.planAnswers`), but for a member of a
			/// loop of builders this call passes made again (`Answer.declaredMadeAgainAtCall`).
			let arguments: [Answer]
			/// The positions of `arguments` in the order a function takes them: the label the called body is built as, then
			/// each other label in the order a walk of the called scope's tree first receives it (each scope's dependencies
			/// in declaration order, then its children's trees, depth first). The order follows where the labels are
			/// received, never how they are named, so renaming a graph reorders no function's parameters.
			let argumentOrder: [Int]
			/// Whether the call is made in the `@Sendable` family where the calling body's function is plain
			/// (`VariantAnswers.isInSendableFamily(calledInSendableFunction:property:)`): inside a `@Sendable` function on the
			/// path to its call place, or of a property held in a `Sendable` wrapper.
			let isInSendableFamily: Bool
		}

		/// - Parameter forMockGeneration: Whether each body is built as a place of a mock's tree is.
		/// - Parameter sharesConstructionMemo: Whether the root's bodies share one construction memo, as the plan a root's
		///   code is laid out from does: a test's comparison builds each body with a memo of its own, so what it builds
		///   reads no other body's places.
		init(frozenScopeMap: FrozenScopeMap, declaredTypeNames: DeclaredTypeNames, forMockGeneration: Bool = false, sharesConstructionMemo: Bool = false) {
			self.frozenScopeMap = frozenScopeMap
			self.declaredTypeNames = declaredTypeNames
			self.forMockGeneration = forMockGeneration
			constructionMemo = ConstructionMemo(sharing: sharesConstructionMemo ? .acrossTrees : .perTree)
		}

		private(set) var bodies = [Body]()

		/// The generator of the body at a position of `bodies`, built as its property: each child on a cycle is a call
		/// place, and nothing closes on a stack.
		func generator(of body: Int) -> ScopeGenerator {
			bodies[body].generator
		}

		/// The body's type and property, each label with what answers it, and ` [@Sendable]` where its function is
		/// (`isSendable(_:)`).
		func description(of body: Int) -> String {
			bodies[body].description + (isSendable(body) ? " [@Sendable]" : "")
		}

		/// Whether the function of the body at a position of `bodies` is `@Sendable`: where some call of it is made in the
		/// `@Sendable` family, or by a body whose function is. One function serves the calls of both families, as today's
		/// tree marks a builder function `@Sendable` for every caller once a `@Sendable` function calls it
		/// (`buildsInSendableFunction`): a plain caller can call a `@Sendable` function, and no `@Sendable` one can call a
		/// plain local function, so a plain body beside it would serve no call today's tree compiles without. `false` for a
		/// body `plan(ofRoot:shadow:cache:)` did not reach.
		func isSendable(_ body: Int) -> Bool {
			sendableBodies.contains(body)
		}

		/// A line per call of `body` (`PlanCallsObservation`).
		func callDescriptions(of body: Int) -> [String] {
			calls(of: body).map { call in
				let arguments = zip(bodies[call.calledBody].labels, call.arguments).map { label, argument in
					switch argument {
					case .none:
						"\(label): nil"
					case let .declared(property, isBeingBuilt):
						"\(label): \(property.asSource)\(isBeingBuilt ? ", being built" : "")"
					case let .declaredMadeAgainAtCall(property):
						"\(label): \(property.asSource), made again at the call"
					case let .instance(of: property):
						"\(label): instance of \(property.asSource)"
					}
				}
				return "\(generator(of: body).scopeData.asDOTNode) [\(body)] at \(call.path) calls [\(call.calledBody)] as \(call.property.asSource) (\(call.argumentOrder.map { arguments[$0] }.joined(separator: "; ")))"
			}
		}

		/// The calls of a body `plan(ofRoot:shadow:cache:)` walked, in the order of their paths; none for any other.
		func calls(of body: Int) -> [Call] {
			callsByBody[body] ?? []
		}

		/// Builds the bodies of a root's plan with no tree of today's: the root's own, then the body of each call place a
		/// body holds, beneath the answers that body's path gives it, until no call is answered anew, and keeps each
		/// body's calls (`calls(of:)`).
		/// - Returns: The position of the root's body, and of each body called in the order the plan first calls it, or
		///   `nil` where `shadow` holds no copy of `scope` or the bodies of one key pass their bound (`keptPerPathBecause`).
		mutating func plan(ofRoot scope: Scope, shadow: CallPlaceShadow, cache: inout ReceivedPropertiesCache) throws -> (rootBody: Int, calledBodies: [Int])? {
			guard let rootCopy = shadow.copy(of: scope) else { return nil }
			frozenScopeMap = frozenScopeMap.freezing(scopes: shadow.copies)
			let rootBody = try body(
				of: rootCopy,
				as: VariantBodyKey(scope: ObjectIdentifier(scope), property: nil, twinsBeingBuilt: [:]),
				keyedBy: [],
				answering: [],
				beneath: NearestDeclarations(),
				lazilyInstantiatedInstanceProperties: [],
			)
			return try plan(fromRootBody: rootBody, shadow: shadow, isMockRoot: false, cache: &cache).map { (rootBody, $0) }
		}

		/// Builds a mock root's plan as `plan(ofRoot:shadow:cache:)` builds a production root's: the root's body, built
		/// beneath the bindings the mock gives its tree (`rootNearestDeclarations`, keyed by their labels, `rootLabels`), its
		/// declarations joined to them (`PlaceContextWalk`'s `isMockRoot`), then the body of each call place a body holds.
		/// - Returns: The position of the root's body, and of each body called in the order the plan first calls it, or
		///   `nil` where `shadow` holds no copy of `scope` or the bodies of one key pass their bound (`keptPerPathBecause`).
		mutating func plan(
			ofMockRoot scope: Scope,
			keyedBy rootLabels: [String],
			beneath rootNearestDeclarations: NearestDeclarations,
			lazilyInstantiatedInstanceProperties: Set<Property>,
			shadow: CallPlaceShadow,
			cache: inout ReceivedPropertiesCache,
		) throws -> (rootBody: Int, calledBodies: [Int])? {
			guard let rootCopy = shadow.copy(of: scope) else { return nil }
			frozenScopeMap = frozenScopeMap.freezing(scopes: shadow.copies)
			let rootBody = try body(
				of: rootCopy,
				as: VariantBodyKey(scope: ObjectIdentifier(scope), property: nil, twinsBeingBuilt: [:]),
				keyedBy: rootLabels,
				answering: rootLabels,
				beneath: rootNearestDeclarations,
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			)
			return try plan(fromRootBody: rootBody, shadow: shadow, isMockRoot: true, cache: &cache).map { (rootBody, $0) }
		}

		/// The bodies the plan whose root's body is at `rootBody` calls, in the order it first calls each: the body of each
		/// call place a body holds, beneath the answers that body's path gives it, until no call is answered anew. Keeps
		/// each body's calls (`calls(of:)`). `isMockRoot` says whether the root's body is a mock root's, whose declarations
		/// join the bindings it is built beneath. `nil` where the bodies of one key pass `bodiesPerKeyLimit`.
		private mutating func plan(fromRootBody rootBody: Int, shadow: CallPlaceShadow, isMockRoot: Bool, cache: inout ReceivedPropertiesCache) throws -> [Int]? {
			var bodiesOfPlan = [Int]()
			var bodiesInPlan = Set<Int>()
			// The bodies of the plan each key holds, which a comparison with today's tree can hold others beside.
			var bodiesOfPlanByKey = [VariantBodyKey: Set<Int>]()
			var bodiesToWalk = [rootBody]
			while let bodyToWalk = bodiesToWalk.popLast() {
				let body = bodies[bodyToWalk]
				var calls = [Call]()
				var bodyWalk = PlaceContextWalk(
					ofTodaysTree: body.generator,
					builtFrom: body.copy,
					beneath: body.nearestDeclarations,
					lazilyInstantiatedInstanceProperties: body.lazilyInstantiatedInstanceProperties,
					twinValues: shadow.twinValues,
					twinsBeingBuilt: body.key.twinsBeingBuilt,
					parameterLabelsByCallPlace: shadow.parameterLabelsByCallPlace,
					followingOnly: shadow.scopesLeadingToCallPlaces,
					isMockRoot: isMockRoot && bodyToWalk == rootBody,
				)
				while let (context, _) = bodyWalk.next() {
					if let calledScope = shadow.scope(calledAt: context.scope), let calledCopy = shadow.copy(of: calledScope) {
						let calledTree = calledTree(of: calledScope)
						let labels = calledTree.sortedReceivedLabels.contains(context.property.label)
							? calledTree.sortedReceivedLabels
							: (calledTree.sortedReceivedLabels + [context.property.label]).sorted()
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
						let key = VariantBodyKey(scope: ObjectIdentifier(calledScope), property: functionProperty, twinsBeingBuilt: context.twinsBeingBuilt)
						let (calledBody, arguments) = try self.calledBody(
							of: calledCopy,
							calledScope: calledScope,
							as: key,
							keyedBy: labels,
							answering: VariantAnswers.answeredLabels(labels, builtAfter: context.labelsBuiltAfter),
							beneath: calledNearestDeclarations,
							lazilyInstantiatedInstanceProperties: context.lazilyInstantiatedInstanceProperties,
							makingAgain: context.labelsMadeAgainAtCall,
							takingOptionallyAmong: shadow.parameterLabels(ofFunctionOf: calledScope),
							builtBy: (context.builder, context.erasedToConcreteExistential),
							cache: &cache,
						)
						// Bodies a key holds apart differ in a label no one optional parameter takes, such as one declared
						// in two forms: past a bound, the root is built per path rather than by a plan that grows with
						// the paths.
						bodiesOfPlanByKey[key, default: []].insert(calledBody)
						guard bodiesOfPlanByKey[key, default: []].count <= Self.bodiesPerKeyLimit else {
							keptPerPathBecause = .bodiesOfOneDeclarationPassBound
							return nil
						}
						// The tree can receive the label the body is built as too, as a loop mate does: it keeps its first place.
						let labelsInOrderReceived = [context.property.label] + calledTree.labelsInOrderFirstReceived.filter { $0 != context.property.label }
						var positionsByLabel = [String: Int]()
						for (position, label) in bodies[calledBody].labels.enumerated() {
							positionsByLabel[label] = position
						}
						let argumentOrder = labelsInOrderReceived.compactMap { positionsByLabel[$0] }
						let orderedPositions = Set(argumentOrder)
						calls.append(Call(
							path: context.path,
							property: context.property,
							calledBody: calledBody,
							// A deliberate gap while nothing emits from the plan: the layout still spells a member made
							// again as its binding (`Answer.argumentSource(labeled:)`).
							arguments: arguments,
							// A label no receive of the walk names keeps its sorted place after the others.
							argumentOrder: argumentOrder + bodies[calledBody].labels.indices.filter { !orderedPositions.contains($0) },
							isInSendableFamily: context.isInSendableFamily,
						))
						if bodiesInPlan.insert(calledBody).inserted {
							bodiesOfPlan.append(calledBody)
							bodiesToWalk.append(calledBody)
						}
					}
				}
				callsByBody[bodyToWalk] = calls.sorted { $0.path.lexicographicallyPrecedes($1.path) }
			}
			// Each pass only marks bodies `@Sendable`, so the passes end within a pass per body.
			var changed = true
			while changed {
				changed = false
				for body in [rootBody] + bodiesOfPlan {
					for call in calls(of: body) where !sendableBodies.contains(call.calledBody) && (call.isInSendableFamily || sendableBodies.contains(body)) {
						sendableBodies.insert(call.calledBody)
						changed = true
					}
				}
			}
			return bodiesOfPlan
		}

		/// The position of the body of `copy` built as `key` beneath what `nearestDeclarations` answers `answeredLabels`,
		/// those of `labels` the body is given an answer for, building it where no body has those answers yet.
		mutating func body(
			of copy: Scope,
			as key: VariantBodyKey,
			keyedBy labels: [String],
			answering answeredLabels: [String],
			beneath nearestDeclarations: NearestDeclarations,
			lazilyInstantiatedInstanceProperties: Set<Property>,
			takingOptionally optionalParameters: [String: OptionalParameter] = [:],
			builtBy builder: (scope: Scope, erasedToConcreteExistential: Bool)? = nil,
		) throws -> Int {
			// A label the body takes optionally is bound to its parameter, which hides every declaration of it above.
			let answeredLabelSet = Set(answeredLabels)
			var keptNearestDeclarations = nearestDeclarations.keeping(labels: answeredLabels.filter { optionalParameters[$0] == nil })
			for label in labels {
				if let parameter = optionalParameters[label] {
					keptNearestDeclarations.replace(parameter.property, providing: parameter.providedForms)
				}
			}
			let answers = labels.map { optionalParameters[$0] != nil ? keptNearestDeclarations[$0] : answeredLabelSet.contains($0) ? nearestDeclarations[$0] : nil }
			let labelsTakenOptionally = Set(optionalParameters.keys)
			let lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties.filter { answeredLabelSet.contains($0.label) && !labelsTakenOptionally.contains($0.label) }
			if let position = positionsByKey[key]?.first(where: { bodies[$0].answers == answers && bodies[$0].lazilyInstantiatedInstanceProperties == lazilyInstantiatedInstanceProperties && bodies[$0].labelsTakenOptionally == labelsTakenOptionally }) {
				return position
			} else {
				let generator: ScopeGenerator
				if let builder, let dependency = builder.scope.instantiable.dependencies.first(where: { $0.property == key.property }) {
					// Built as its property: the one child of a scope that declares nothing else, so the body is built as
					// a place builds it, and every child on a cycle, a repeat of the body's own declaration included, is a
					// call place, which closes on nothing. A dependency a mock root promotes is one its type receives,
					// which the mock instantiates: the holder instantiates it too.
					let heldDependency = switch dependency.source {
					case .instantiated:
						dependency
					case .received, .forwarded, .aliased:
						Dependency(property: dependency.property, source: .instantiated(fulfillingTypeDescription: nil, erasedToConcreteExistential: builder.erasedToConcreteExistential), declarationLocation: dependency.declarationLocation)
					}
					let holder = Scope(instantiable: Self.holderInstantiable(of: builder.scope.instantiable, declaring: heldDependency))
					holder.propertiesToGenerate = [.instantiated(dependency.property, copy, erasedToConcreteExistential: builder.erasedToConcreteExistential)]
					let (table, record) = frozenScopeMap.freezing(rootScope: holder)
					let holderGenerator = try record.createScopeGenerator(
						in: table,
						nearestDeclarations: keptNearestDeclarations,
						lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
						erasedToConcreteExistential: false,
						forMockGeneration: forMockGeneration,
						declaredTypeNames: declaredTypeNames,
						constructionMemo: &constructionMemo,
					)
					generator = holderGenerator.orderedChildrenComputedAfresh(propertiesGeneratedLater: []).first?.generator ?? holderGenerator
				} else {
					let (table, record) = frozenScopeMap.freezing(rootScope: copy)
					generator = try record.createScopeGenerator(
						in: table,
						nearestDeclarations: keptNearestDeclarations,
						lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
						erasedToConcreteExistential: false,
						forMockGeneration: forMockGeneration,
						declaredTypeNames: declaredTypeNames,
						constructionMemo: &constructionMemo,
					)
				}
				bodies.append(Body(
					key: key,
					copy: copy,
					labels: labels,
					answers: answers,
					nearestDeclarations: keptNearestDeclarations,
					lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
					labelsTakenOptionally: labelsTakenOptionally,
					generator: generator,
				))
				positionsByKey[key, default: []].append(bodies.count - 1)
				return bodies.count - 1
			}
		}

		/// What every call of a scope reads of the scope's tree, made once per scope called.
		private struct CalledTree {
			/// The labels the scope's tree reads from above, sorted (`sortedLabelsReadFromAbove(inTreeOf:)`).
			let sortedReceivedLabels: [String]
			/// The same labels in the order a walk first meets a receive of each (`labelsInOrderFirstReceived(inTreeOf:)`).
			let labelsInOrderFirstReceived: [String]
		}

		private mutating func calledTree(of scope: Scope) -> CalledTree {
			if let calledTree = calledTreesByScope[ObjectIdentifier(scope)] {
				return calledTree
			} else {
				let calledTree = CalledTree(
					sortedReceivedLabels: Self.sortedLabelsReadFromAbove(inTreeOf: scope),
					labelsInOrderFirstReceived: Self.labelsInOrderFirstReceived(inTreeOf: scope),
				)
				calledTreesByScope[ObjectIdentifier(scope)] = calledTree
				return calledTree
			}
		}

		/// The body a call of `calledScope`, whose copy is `copy`, is answered by: built as `key` beneath what
		/// `nearestDeclarations` answers `answeredLabels`, those of `labels` the call answers, but for each label of
		/// `parameterLabels` the body takes as an optional parameter (`OptionalParameter`), which every call of the body
		/// passes its own answer. `parameterLabels` are those another scope of the called scope's cycles declares, which
		/// today's function takes as parameters (`CallPlaceShadow.parameterLabels(ofFunctionOf:)`): any other label every
		/// call answers alike. With what the call passes each label: that answer, or the body's own (`Body.planAnswers`), a
		/// member of a loop of builders made again among `labelsMadeAgainAtCall` (`VariantAnswers.arguments`).
		mutating func calledBody(
			of copy: Scope,
			calledScope: Scope,
			as key: VariantBodyKey,
			keyedBy labels: [String],
			answering answeredLabels: [String],
			beneath nearestDeclarations: NearestDeclarations,
			lazilyInstantiatedInstanceProperties: Set<Property>,
			makingAgain labelsMadeAgainAtCall: Set<String>,
			takingOptionallyAmong parameterLabels: Set<String>,
			builtBy builder: (scope: Scope, erasedToConcreteExistential: Bool),
			cache: inout ReceivedPropertiesCache,
		) throws -> (body: Int, arguments: [Answer]) {
			var optionalParameters = [String: OptionalParameter]()
			var optionalArguments = [String: Answer]()
			// A member of a loop of builders made again at the call is passed made again (`VariantAnswers.arguments`).
			for (label, parameter) in Self.optionalParameters(ofTreeOf: calledScope, keyedBy: labels.filter(parameterLabels.contains), builtAs: key.property?.label, cache: &cache) {
				if let argument = Self.argument(
					passing: parameter,
					labeled: label,
					isAnswered: answeredLabels.contains(label),
					beneath: nearestDeclarations,
					lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
				) {
					optionalParameters[label] = parameter
					optionalArguments[label] = argument
				}
			}
			let body = try body(
				of: copy,
				as: key,
				keyedBy: labels,
				answering: answeredLabels,
				beneath: nearestDeclarations,
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
				takingOptionally: optionalParameters,
				builtBy: builder,
			)
			let arguments = zip(labels, bodies[body].planAnswers).map { label, answer in optionalArguments[label] ?? answer }
			return (body, VariantAnswers.arguments(arguments, of: labels, makingAgain: labelsMadeAgainAtCall))
		}

		/// The labels `scope`'s tree reads from above it, sorted: hiding is by label, so a read is answered by the nearest
		/// declaration of its label, and a label a scope of the tree declares is read beneath it from that declaration, whatever
		/// form the read takes (`LabelsReadFromAbove`, the validation walk's rule). A body is keyed by these labels alone: a
		/// scope that forwards `mark: Mark?` above a receive of `mark: Stamp?` only if available reads no `mark` from above.
		static func sortedLabelsReadFromAbove(inTreeOf scope: Scope) -> [String] {
			var scopeByIdentifier = [ObjectIdentifier(scope): scope]
			let graph = OrderedGraph(root: ObjectIdentifier(scope)) { identifier in
				var targets = [ObjectIdentifier]()
				for case let .instantiated(_, childScope, _) in scopeByIdentifier[identifier]?.propertiesToGenerate ?? [] {
					scopeByIdentifier[ObjectIdentifier(childScope)] = childScope
					targets.append(ObjectIdentifier(childScope))
				}
				return targets
			}
			// Every node is a scope the walk met.
			let scopes = graph.nodes.compactMap { scopeByIdentifier[$0] }
			let labels = LabelsReadFromAbove(
				graph: graph,
				own: { PlanVariants.labelsReadFromAbove(byDependenciesOf: scopes[$0].instantiable) },
				bound: { scopes[$0].declaredLabels },
			)
			return labels.labels(of: 0).sorted()
		}

		/// The labels the scopes of `scope`'s tree receive, each once, in the order a walk first meets a receive of it: each
		/// scope's received dependencies and the properties its renames are fulfilled by, in declaration order, then the
		/// trees of the scopes it instantiates, depth first, each scope once.
		private static func labelsInOrderFirstReceived(inTreeOf scope: Scope) -> [String] {
			var labels = [String]()
			var labelsMet = Set<String>()
			var visitedScopes = Set<ObjectIdentifier>()
			var scopesToVisit = [scope]
			while let scope = scopesToVisit.popLast() {
				guard visitedScopes.insert(ObjectIdentifier(scope)).inserted else { continue }
				for dependency in scope.instantiable.dependencies {
					let label: String? = switch dependency.source {
					case .instantiated, .forwarded:
						nil
					case .received:
						dependency.property.label
					case let .aliased(fulfillingProperty, _, _):
						fulfillingProperty.label
					}
					if let label, labelsMet.insert(label).inserted {
						labels.append(label)
					}
				}
				for propertyToGenerate in scope.propertiesToGenerate.reversed() {
					if case let .instantiated(_, childScope, _) = propertyToGenerate {
						scopesToVisit.append(childScope)
					}
				}
			}
			return labels
		}

		/// The type of a scope whose one declaration is `dependency` of `builder`: what a body built as its property is the
		/// child of.
		private static func holderInstantiable(of builder: Instantiable, declaring dependency: Dependency) -> Instantiable {
			var holder = Instantiable(
				instantiableType: builder.concreteInstantiable,
				isRoot: false,
				initializer: Initializer(arguments: [Initializer.Argument(
					innerLabel: dependency.property.label,
					typeDescription: dependency.property.typeDescription,
					defaultValueExpression: nil,
				)]),
				additionalInstantiables: nil,
				dependencies: [dependency],
				declarationType: builder.declarationType,
				access: builder.access,
				enclosingTypeAccess: builder.enclosingTypeAccess,
				enclosingExtensionAccess: builder.enclosingExtensionAccess,
				declarationLocation: builder.declarationLocation,
				moduleName: builder.moduleName,
				packageName: builder.packageName,
			)
			holder.sourceFilePath = builder.sourceFilePath
			return holder
		}

		/// The world's frozen map, with every copy of the shadow a plan is built from frozen in it once the plan starts.
		private var frozenScopeMap: FrozenScopeMap
		private let declaredTypeNames: DeclaredTypeNames
		private let forMockGeneration: Bool
		/// Why the last plan stopped before its last body: the bodies of one key passed `bodiesPerKeyLimit`.
		private(set) var keptPerPathBecause: PerPathReason?
		/// The most bodies one key holds before the plan stops: each differs from the others in an answer no optional
		/// parameter merges, of which a path around a cycle can give a key one per subset of its labels.
		static let bodiesPerKeyLimit = 8
		private var positionsByKey = [VariantBodyKey: [Int]]()
		private var calledTreesByScope = [ObjectIdentifier: CalledTree]()
		/// The memo the root's bodies are built with: shared across them where the plan lays the root's code out, so a
		/// body's places that read their context alike reuse what another body built.
		private var constructionMemo: ConstructionMemo
		private var callsByBody = [Int: [Call]]()
		private var sendableBodies = Set<Int>()
	}
}
