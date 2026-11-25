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
	/// the order the plan first calls it, and the bodies today's places of such types take that the plan does not build.
	@TaskLocal public static var observer: (@Sendable (_ root: String, _ bodiesOfPlan: [String], _ todaysBodiesPlanLacks: [String]) -> Void)?
}

extension DependencyTreeGenerator {
	/// What the bodies of a root are kept by: the scope built and the property it is built as, `nil` for the root's own.
	struct VariantBodyKey: Hashable {
		let scope: ObjectIdentifier
		let property: Property?
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
			let generator: ScopeGenerator

			/// The body's type and property, then each label with the properties its answer hands its readers.
			var description: String {
				var description = copy.instantiable.concreteInstantiable.asSource
				if let property = key.property {
					description.append(" as \(property.asSource)")
				}
				for (label, answer) in zip(labels, answers) {
					if let answer {
						let properties = Set(answer.bindings.values.map(\.asSource)).sorted().joined(separator: " or ")
						description.append(" [\(label) = \(properties)\(answer.formsBeingBuilt.isEmpty ? "" : ", being built")]")
					} else {
						description.append(" [\(label) = nil]")
					}
				}
				return description
			}
		}

		init(frozenScopeMap: FrozenScopeMap, declaredTypeNames: DeclaredTypeNames) {
			self.frozenScopeMap = frozenScopeMap
			self.declaredTypeNames = declaredTypeNames
		}

		private(set) var bodies = [Body]()

		/// The position of the body of `copy` built as `key` beneath what `nearestDeclarations` answers `answeredLabels`,
		/// those of `labels` the body is given an answer for, building it where no body has those answers yet.
		mutating func body(
			of copy: Scope,
			as key: VariantBodyKey,
			keyedBy labels: [String],
			answering answeredLabels: [String],
			beneath nearestDeclarations: NearestDeclarations,
			lazilyInstantiatedInstanceProperties: Set<Property>,
		) throws -> Int {
			let answers = labels.map { answeredLabels.contains($0) ? nearestDeclarations[$0] : nil }
			let lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties.filter { answeredLabels.contains($0.label) }
			if let position = positionsByKey[key]?.first(where: { bodies[$0].answers == answers && bodies[$0].lazilyInstantiatedInstanceProperties == lazilyInstantiatedInstanceProperties }) {
				return position
			} else {
				let (table, record) = frozenScopeMap.freezing(rootScope: copy)
				let keptNearestDeclarations = nearestDeclarations.keeping(labels: answeredLabels)
				var memo = ConstructionMemo()
				try bodies.append(Body(
					key: key,
					copy: copy,
					labels: labels,
					answers: answers,
					nearestDeclarations: keptNearestDeclarations,
					lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
					generator: record.createScopeGenerator(
						in: table,
						nearestDeclarations: keptNearestDeclarations,
						lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
						erasedToConcreteExistential: false,
						declaredTypeNames: declaredTypeNames,
						constructionMemo: &memo,
					),
				))
				positionsByKey[key, default: []].append(bodies.count - 1)
				return bodies.count - 1
			}
		}

		private let frozenScopeMap: FrozenScopeMap
		private let declaredTypeNames: DeclaredTypeNames
		private var positionsByKey = [VariantBodyKey: [Int]]()
	}
}
