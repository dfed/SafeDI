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

/// Lets a test compare the values two properties of one root's tree build as twins by two rules: the order shadow's
/// (`CallPlaceShadow.twinValues`) and the plan's (`PerTypePlan.twins`), each by the identity a cycle closes on, and check
/// that each call of today's tree runs the function the plan's call names. Test only.
public enum TwinIdentityObservation {
	/// Called for each production root whose tree holds a twin value (`CallPlaceShadow.twinValues`), with
	/// the root's type, each rule's twin values, as `<type> as <property>`, sorted, and the places of today's tree, in walk
	/// order, that a scope closing a cycle calls where the plan's call names another function.
	@TaskLocal public static var observer: (@Sendable (_ root: String, _ shadowsTwinValues: [String], _ plansTwinValues: [String], _ callsOfOtherFunction: [String]) -> Void)?
}

extension DependencyTreeGenerator {
	/// The judgements a body's key needs beyond the nearest declaration of each label its tree receives: the order the
	/// scope that makes a call builds its children in, the `@Sendable` family a call is made in, and which values a path
	/// builds as twins. Each is read by a test's comparison only: nothing emits from it.
	enum VariantAnswers {
		/// The labels of `propertiesGeneratedLater`, the declarations a place's tree reads only if available that a scope
		/// above it builds after it (`ScopeGenerator.OrderedChild.propertiesGeneratedLater`), and of `labelsBuiltAfterAbove`,
		/// those `nil` where the place is, less those `generator`, the place's, makes again at the top of its function as a
		/// member of a loop of builders (`ScopeGenerator.reboundProperties`), which its tree then reads, but for
		/// `parameterLabels`, which a call place's function takes as parameters instead (a function rebinds no label it
		/// takes), and less those such a parameter is passed made again (`labelsMadeAgainAtCall`). Each other is `nil`
		/// everywhere in the place's tree, since its every receive of the label is only if available (a required receive
		/// orders the declaration first), so a body answers it `nil` whatever declares it.
		static func labelsBuiltAfter(
			_ propertiesGeneratedLater: Set<Property>,
			besides labelsBuiltAfterAbove: Set<String>,
			reboundBy generator: ScopeGenerator,
			besidesParameters parameterLabels: Set<String>,
			passedByReceivedFunction loopMembers: Set<Property>,
		) -> Set<String> {
			var labels = labelsBuiltAfterAbove
			for property in propertiesGeneratedLater
				where !isPassedByReceivedFunction(property, to: generator, taking: parameterLabels, among: loopMembers)
			{
				labels.insert(property.label)
			}
			return labels.subtracting(generator.reboundProperties.lazy.map(\.label).filter { !parameterLabels.contains($0) })
		}

		/// The labels of `propertiesGeneratedLater` that the call of `generator`'s function passes made again
		/// (`Answer.declaredMadeAgainAtCall`): the members of its loop of builders, `loopMembers`, that the function takes
		/// as parameters, which the scope that declares the loop builds after the call.
		static func labelsMadeAgainAtCall(
			_ propertiesGeneratedLater: Set<Property>,
			by generator: ScopeGenerator,
			besidesParameters parameterLabels: Set<String>,
			passedByReceivedFunction loopMembers: Set<Property>,
		) -> Set<String> {
			guard !loopMembers.isEmpty else { return [] }
			return Set(propertiesGeneratedLater.lazy
				.filter { isPassedByReceivedFunction($0, to: generator, taking: parameterLabels, among: loopMembers) }
				.map(\.label))
		}

		/// Whether `property` is one of `loopMembers`, the members of the loop of builders `generator` is on, that its
		/// function takes as a parameter a lazy cycle needs (one of its own `cycleParameters`, or of `parameterLabels` for
		/// a call place): the scope that declares the loop hands the member a function of no such parameters,
		/// `__safeDI_<label>_received`, which makes each such member's wrapper again and passes it, so the function is
		/// passed a value whichever member is built first. A member is matched by property, in the form the loop declares
		/// or its optional form, as today's record of the call matches it (`ScopeGenerator`'s `recordCalls`), never by
		/// label alone.
		static func isPassedByReceivedFunction(_ property: Property, to generator: ScopeGenerator, taking parameterLabels: Set<String>, among loopMembers: Set<Property>) -> Bool {
			guard !loopMembers.isEmpty else { return false }
			let unwrappedProperty = property.asUnwrappedProperty
			guard loopMembers.contains(unwrappedProperty) || loopMembers.contains(unwrappedProperty.asOptionalProperty) else { return false }
			return parameterLabels.contains(property.label) || generator.cycleParameters.contains { $0.property.asUnwrappedProperty == unwrappedProperty }
		}

		/// `answers`, a called body's, one per label of `labels`, as one call's arguments: a declaration whose label is
		/// among `labelsMadeAgainAtCall` is passed made again. Such a label never answers a declaration being built: a
		/// declaration being built is of a scope the call is made inside, and one made again is of a sibling the calling
		/// scope builds after the call.
		static func arguments(_ answers: [Answer], of labels: [String], makingAgain labelsMadeAgainAtCall: Set<String>) -> [Answer] {
			guard !labelsMadeAgainAtCall.isEmpty else { return answers }
			return zip(labels, answers).map { label, answer in
				if labelsMadeAgainAtCall.contains(label), case let .declared(property, isBeingBuilt: false) = answer {
					.declaredMadeAgainAtCall(property)
				} else {
					answer
				}
			}
		}

		/// The labels of the parameters of the function a lazy cycle closes on that `child`, the scope that declares the
		/// function or one that closes the cycle on it, passes `nil`, given the order the scope above it builds its children
		/// in: those whose declaration is still being built (`labelsOfCycleParametersPassedNil`), and those whose declaration
		/// is built after the call.
		static func labelsOfCycleParametersPassedNil(by child: ScopeGenerator.OrderedChild, passedByReceivedFunction loopMembers: Set<Property>) -> Set<String> {
			var labels = child.generator.labelsOfCycleParametersPassedNil
			for parameter in child.generator.cycleParameters
				where child.unavailableProperties.contains(parameter.property) && !isPassedByReceivedFunction(parameter.property, to: child.generator, taking: [], among: loopMembers)
			{
				labels.insert(parameter.property.label)
			}
			return labels
		}

		/// Of `labels`, those a body is given an answer for: every one not built after the call.
		static func answeredLabels(_ labels: [String], builtAfter labelsBuiltAfter: Set<String>) -> [String] {
			labelsBuiltAfter.isEmpty ? labels : labels.filter { !labelsBuiltAfter.contains($0) }
		}

		/// Whether a body built as `property`, called from inside a `@Sendable` function or not, is of the `@Sendable`
		/// family. Every body's function is declared in the root's body, so none encloses another: a function called from
		/// inside a `@Sendable` function, or handed to a `Sendable` wrapper, is captured by it, and so must be `@Sendable`.
		/// Today's `buildsInSendableFunction` differs only where a function encloses the `@Sendable` function that calls
		/// it, which then captures nothing.
		static func isInSendableFamily(calledInSendableFunction: Bool, property: Property) -> Bool {
			calledInSendableFunction || property.propertyType.isSendable
		}

		/// The twin values of a root's tree by the plan's rule (`PerTypePlan.twins`): each declaration on a cycle that shares
		/// its cycle identity with another declaration of its component, as `<concrete type> as <property as cycle validation
		/// sees it>`, sorted and without repeats.
		static func plansTwinValues(of plan: PerTypePlan) -> [String] {
			var twinValues = Set<String>()
			for index in plan.twins {
				if let built = plan.graph.nodes[index].built {
					twinValues.insert("\(plan.graph.nodes[index].record.instantiable.concreteInstantiable.asSource) as \(built.property.asValidatedForDependencyCycles.asSource)")
				}
			}
			return twinValues.sorted()
		}

		/// The property whose function the plan's call made at `context`'s place runs, where the place is built as a value two
		/// properties build: the twin its path is building (`PlaceContext.twinsBeingBuilt`), as `VariantBodies` calls it.
		/// `nil` where the place builds no twin value, whose call runs its own property's function.
		static func functionThePlanCalls(at context: PlaceContext, twinValues: Set<TwinValue>) -> Property? {
			let twinValue = TwinValue(concreteType: context.scope.instantiable.concreteInstantiable, property: context.property.asValidatedForDependencyCycles)
			guard twinValues.contains(twinValue) else { return nil }
			return context.twinsBeingBuilt[twinValue]
		}

		/// `context`'s place, where a scope closing a cycle calls it and runs another function than the plan's call there
		/// names (`functionThePlanCalls(at:twinValues:)`); else nothing.
		static func placesCallingOtherFunctionThanPlan(at context: PlaceContext, twinValues: Set<TwinValue>) -> [String] {
			[functionThePlanCalls(at: context, twinValues: twinValues)].compactMap(\.self).filter { $0 != context.property }.map { _ in context.place }
		}

		/// `shadow`'s twin values, spelled as `plansTwinValues(of:)` spells them, sorted.
		static func shadowsTwinValues(of shadow: CallPlaceShadow) -> [String] {
			shadow.twinValues.map { "\($0.concreteType.asSource) as \($0.property.asSource)" }.sorted()
		}
	}
}

extension DependencyTreeGenerator.PlaceContext {
	/// This context, for a call of `function` by `closingScope`, a scope that closes a cycle on it: the function reads the
	/// labels it takes as parameters from the call, `nil` where the call is built before their declarations or passes on a
	/// `nil` it was given (`labelsPassedNilAboveCall`), and every other label where the function is declared. A parameter
	/// the call passes `nil` whatever the order (`labelsPassedNil`) keeps its answer, as a call of every order does.
	///
	/// - Parameter labelsPassedNilAboveCall: The labels a function the closing scope is built in was passed `nil`, that no
	///   scope between declares: the closing scope passes that parameter on.
	func answeringCall(
		of function: DependencyTreeGenerator.FunctionPlace,
		by closingScope: ScopeGenerator.OrderedChild,
		passingOnNilFor labelsPassedNilAboveCall: Set<String>,
		passedByReceivedFunction loopMembers: Set<Property>,
	) -> Self {
		let parameterLabels = Set(function.generator.cycleParameters.map(\.property.label))
		guard !parameterLabels.isEmpty else { return self }
		var labelsBuiltAfter = labelsBuiltAfter.subtracting(parameterLabels)
		let labelsPassedNilWhateverTheOrder = closingScope.generator.labelsOfCycleParametersPassedNil
		for label in parameterLabels.intersection(labelsPassedNilAboveCall) where !labelsPassedNilWhateverTheOrder.contains(label) {
			labelsBuiltAfter.insert(label)
		}
		// A closing scope on a loop of builders calls through a `_received` function, which passes the loop's members
		// made again.
		var labelsMadeAgainAtCall = Set<String>()
		for parameter in closingScope.generator.cycleParameters
			where closingScope.unavailableProperties.contains(parameter.property)
			&& !labelsPassedNilWhateverTheOrder.contains(parameter.property.label)
		{
			if DependencyTreeGenerator.VariantAnswers.isPassedByReceivedFunction(parameter.property, to: closingScope.generator, taking: [], among: loopMembers) {
				labelsMadeAgainAtCall.insert(parameter.property.label)
			} else {
				labelsBuiltAfter.insert(parameter.property.label)
			}
		}
		return Self(
			place: place,
			generator: generator,
			scope: scope,
			property: property,
			path: path,
			builder: builder,
			erasedToConcreteExistential: erasedToConcreteExistential,
			nearestDeclarations: nearestDeclarations,
			enclosingNearestDeclarations: enclosingNearestDeclarations,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			labelsPassedNil: labelsPassedNil,
			twinsBeingBuilt: twinsBeingBuilt,
			orderedUnavailableProperties: orderedUnavailableProperties,
			labelsBuiltAfter: labelsBuiltAfter,
			labelsMadeAgainAtCall: labelsMadeAgainAtCall,
			isInSendableFamily: isInSendableFamily,
		)
	}
}
