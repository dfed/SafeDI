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

extension NodeRecords {
	/// Every kind stage 1 does not make that `declaration` is of, in the order they are checked.
	static func refusalsOfBuiltByInitializer(_ declaration: DeclarationID, in world: some NodeRecordSources) -> [NodeRecordRefusal] {
		var refusals = [NodeRecordRefusal]()
		// Every other construction is a call of another module's code, a hand-written mock or a fill, which a later stage or
		// another lane's kind makes.
		if world.construction(of: declaration) != .initializer {
			refusals.append(.construction)
		}
		switch world.kind(of: declaration) {
		case .constant, .instantiator:
			if world.isErased(declaration) {
				refusals.append(.erased)
			}
		case .sendableInstantiator, .sendableErasedInstantiator, .sendableLazy:
			refusals.append(.sendable)
		case .erasedInstantiator:
			refusals.append(.erased)
		case .lazy:
			refusals.append(.lazy)
		case .alias, .hole:
			refusals.append(.renameOrHole)
		}
		if world.isOnCycle(declaration) {
			refusals.append(.cycle)
		}
		let scope = world.scope(of: declaration)
		if scope.isUnavailableDependency || scope.builtInlineSeamComment != nil {
			refusals.append(.unavailableOrInlineSeam)
		}
		if !scope.holeArguments.isEmpty {
			refusals.append(.fill)
		}
		if !scope.instantiatedDependenciesNotGenerated.isEmpty {
			refusals.append(.renameOrHole)
		}
		for propertyToGenerate in scope.propertiesToGenerate {
			switch propertyToGenerate {
			case .instantiated:
				break
			case .hole, .aliased:
				refusals.append(.renameOrHole)
			}
		}
		// A mock root's record reads no wrapper's instance yet. A lazy node is refused there as its kind, which no claim
		// takes in a mock world; a scope that forwards a lazily instantiated property, or cannot build one it instantiates,
		// has no such node, so it is refused here. In a production root's world `DeclarationsAnsweringReads` answers both.
		if world.isMockWorld, !scope.declaredLazilyInstantiatedInstanceProperties.isEmpty || !scope.forwardedLazilyInstantiatedInstanceProperties.isEmpty {
			refusals.append(.lazy)
		}
		for dependency in scope.instantiable.dependencies where dependency.source == .received(onlyIfAvailable: true) {
			refusals.append(.onlyIfAvailable)
		}
		if declaration != 0, scope.instantiable.initializer == nil {
			refusals.append(.noInitializer)
		}
		return refusals
	}

	/// The record of `declaration`'s place, a node its type's initializer builds, as a constant or in any of SafeDI's
	/// wrappers, whose body builds `children`, whose tree declares `typesDeclaredEscaping` `@escaping`, whose construction
	/// is passed `nil` for `unavailableProperties`, whose line constructing the type ends with `lineEnd`, and which declares
	/// its builder function where `declaresFunction`. Whether the place is erased, is `@Sendable` and always declares its
	/// builder function, it reads of the node.
	/// - Parameter lazilyInstantiatedInstanceProperties: The by-value properties the node's type receives as the instance
	///   of a lazily instantiated property declared above it (`DeclarationsAnsweringReads`).
	static func builtByInitializerRecord(
		of declaration: DeclarationID,
		variant _: VariantID,
		in world: some NodeRecordSources,
		unavailableProperties: Set<Property> = [],
		lazilyInstantiatedInstanceProperties: Set<Property>,
		typesDeclaredEscaping: Set<TypeDescription>,
		children: [GeneratedCode],
		lineEnd: String = "",
		declaresFunction: Bool = false,
	) throws -> BuiltPlaceRecord {
		let instantiable = world.scope(of: declaration).instantiable
		// Every node but the root is built as a property, and has an initializer (`refusalsOfBuiltByInitializer(_:in:)`).
		guard let property = world.property(of: declaration), let initializer = instantiable.initializer else { throw NodeRecordRefusal.noInitializer }
		// Never throws: a type's initializer is one that fulfills its dependencies (`InstantiableVisitor`'s
		// `canonicalConstructionInitializer`, through `Initializer.isValid(forFulfilling:)`, which makes the same binding).
		let arguments = try initializer.createInitializerArguments(given: instantiable.dependencies, unavailableProperties: unavailableProperties, lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties)
		let isExtension = instantiable.declarationType.isExtension
		// An instantiator or a lazy wrapper is made of its builder function, which is `@Sendable` for a `Sendable` wrapper.
		let (isWrapper, isSendable) = switch world.kind(of: declaration) {
		case .instantiator, .erasedInstantiator, .lazy:
			(true, false)
		case .sendableInstantiator, .sendableErasedInstantiator, .sendableLazy:
			(true, true)
		case .constant, .alias, .hole:
			(false, false)
		}
		return BuiltPlaceRecord(
			property: property,
			isErased: world.isErased(declaration),
			concreteType: instantiable.concreteInstantiable,
			isExtension: isExtension,
			target: isExtension ? .instantiate(instantiable.concreteInstantiable) : .initializer(instantiable.concreteInstantiable),
			arguments: arguments.map {
				PlaceRead(argumentLabel: $0.argument.label, label: $0.dependency.property.label, property: $0.dependency.property, source: $0.argument.source)
			},
			forwardedProperties: instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted(),
			cycleParameters: [],
			callCycleArguments: [],
			functionName: ScopeGenerator.functionName(toBuildPropertyNamed: property.label),
			isSendable: isSendable,
			typesDeclaredEscaping: typesDeclaredEscaping,
			lineEnd: lineEnd,
			// A wrapper always declares its builder function; a constant only where its body has a statement, or where the
			// caller's kind begins it with one (`declaresFunction`).
			hasFunction: declaresFunction || isWrapper || !children.isEmpty,
			children: children,
			node: PlanNode(),
		)
	}
}
