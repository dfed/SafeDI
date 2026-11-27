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
	/// Refuses `declaration`'s world with the first kind stage 1 does not make that the node is of.
	static func checkBuiltByInitializer(_ declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) {
		// Every other construction is a call of another module's code, a hand-written mock or a fill, which a later stage or
		// another lane's kind makes.
		guard world.construction(of: declaration) == .initializer else { throw .construction }
		switch world.kind(of: declaration) {
		case .constant, .instantiator:
			break
		case .sendableInstantiator, .erasedInstantiator, .sendableErasedInstantiator, .lazy, .sendableLazy, .alias, .hole:
			throw .kind
		}
		guard !world.isOnCycle(declaration) else { throw .cycle }
		let scope = world.scope(of: declaration)
		guard !scope.isUnavailableDependency, scope.builtInlineSeamComment == nil else { throw .unavailableOrInlineSeam }
		guard scope.holeArguments.isEmpty else { throw .fill }
		guard scope.instantiatedDependenciesNotGenerated.isEmpty else { throw .renameOrHole }
		for propertyToGenerate in scope.propertiesToGenerate {
			switch propertyToGenerate {
			case let .instantiated(_, _, erasedToConcreteExistential, _):
				guard !erasedToConcreteExistential else { throw .kind }
			case .hole:
				// A node of its own, which `holeKind(of:in:)` makes.
				break
			case .aliased:
				throw .renameOrHole
			}
		}
		guard scope.declaredLazilyInstantiatedInstanceProperties.isEmpty, scope.forwardedLazilyInstantiatedInstanceProperties.isEmpty else { throw .onlyIfAvailable }
		for dependency in scope.instantiable.dependencies {
			switch dependency.source {
			case .instantiated, .forwarded, .received(onlyIfAvailable: false),
			     // A rename is among the scope's properties to generate, refused above.
			     .aliased:
				break
			case .received(onlyIfAvailable: true):
				throw .onlyIfAvailable
			}
		}
		guard declaration == 0 || scope.instantiable.initializer != nil else { throw .noInitializer }
	}

	/// The record of `declaration`'s place, a node of kind `builtByInitializer`, whose body builds `children` and whose
	/// tree declares `typesDeclaredEscaping` `@escaping`.
	static func builtByInitializerRecord(
		of declaration: DeclarationID,
		in world: some NodeRecordSources,
		typesDeclaredEscaping: Set<TypeDescription>,
		children: [GeneratedCode],
	) throws -> BuiltPlaceRecord {
		let instantiable = world.scope(of: declaration).instantiable
		// Every node but the root is built as a property, and has an initializer (`checkBuiltByInitializer(_:in:)`).
		guard let property = world.property(of: declaration), let initializer = instantiable.initializer else { throw NodeRecordRefusal.noInitializer }
		// Never throws: a type's initializer is one that fulfills its dependencies (`InstantiableVisitor`'s
		// `canonicalConstructionInitializer`, through `Initializer.isValid(forFulfilling:)`, which makes the same binding).
		let arguments = try initializer.createInitializerArguments(given: instantiable.dependencies)
		let isExtension = instantiable.declarationType.isExtension
		let isInstantiator = switch world.kind(of: declaration) {
		case .instantiator, .sendableInstantiator, .erasedInstantiator, .sendableErasedInstantiator:
			true
		case .constant, .lazy, .sendableLazy, .alias, .hole:
			false
		}
		return BuiltPlaceRecord(
			property: property,
			isErased: false,
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
			isSendable: false,
			typesDeclaredEscaping: typesDeclaredEscaping,
			lineEnd: "",
			// An `Instantiator` always declares its builder function; a constant only where its body has a statement.
			hasFunction: isInstantiator || !children.isEmpty,
			children: children,
			node: PlanNode(),
		)
	}
}
