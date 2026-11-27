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
	/// The claim of `declaration` as a node on a cycle, which discharges the refusal of the cycle, or `nil` where it is on
	/// none. A node on a cycle another kind claims is that kind's, closed on as this kind's is
	/// (`NodeRecords.kindAndRefusals(of:in:)`).
	static func cycleClaim(of declaration: DeclarationID, in world: some NodeRecordSources) -> NodeRecordClaim? {
		guard world.isOnCycle(declaration) else { return nil }
		return NodeRecordClaim(kind: .cycle, discharges: [.cycle])
	}

	/// The record of `declaration`'s place, a node of kind `cycle`: built by its initializer as a stage-1 node is, its
	/// children's places among which a call back to a place being built above it is that call's closing place
	/// (`closingRecord(closingOn:in:)`).
	static func cycleRecord(
		of declaration: DeclarationID,
		variant: VariantID,
		in world: some NodeRecordSources,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		typesDeclaredEscaping: Set<TypeDescription>,
		children: [GeneratedCode],
	) throws -> BuiltPlaceRecord {
		try builtByInitializerRecord(
			of: declaration,
			variant: variant,
			in: world,
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			typesDeclaredEscaping: typesDeclaredEscaping,
			children: children,
		)
	}

	/// Refuses `world`, which holds a cycle, where a variant of a node on a cycle holds an optional parameter's key: one
	/// body takes the label as an optional parameter there (rule 1), where today's tree may write a body per value or `nil`;
	/// or where one cycle identity (`cycle(of:)`) is built both as a lazily instantiated wrapper and otherwise: a twin.
	static func checkVariantsPartitionAlike(inWorldWithCycle world: some NodeRecordSources) throws(NodeRecordRefusal) {
		for variant in 0..<Int32(world.variantCount) where world.isOnCycle(world.declaration(of: variant)) {
			guard !world.keys(of: variant).contains(TypeFactsGraph.optionalParameterKey) else { throw .cycleVariantsPartitionApart }
		}
		var isLazyByIdentity = [CycleID: Bool]()
		for declaration in 0..<Int32(world.declarationCount) where world.isOnCycle(declaration) {
			let isLazy = switch world.kind(of: declaration) {
			case .lazy, .sendableLazy:
				true
			case .constant, .instantiator, .sendableInstantiator, .erasedInstantiator, .sendableErasedInstantiator, .alias, .hole:
				false
			}
			guard isLazyByIdentity[world.cycle(of: declaration), default: isLazy] == isLazy else { throw .cycleVariantsPartitionApart }
			isLazyByIdentity[world.cycle(of: declaration)] = isLazy
		}
	}

	/// The labels the types of `world`, which holds a cycle, receive, plainly, only if available or through a rename: read
	/// from above wherever they are, a superset of what the function a call closes a cycle on reads from above it.
	/// - Throws: `cycleReceivesBuilder` where a type receives a builder.
	static func labelsReceived(inWorldWithCycle world: some NodeRecordSources) throws(NodeRecordRefusal) -> Set<String> {
		var labels = Set<String>()
		for declaration in 0..<Int32(world.declarationCount) {
			let reads = world.scope(of: declaration).instantiable.dependencies.compactMap { dependency -> Property? in
				switch dependency.source {
				case .received:
					dependency.property
				case let .aliased(fulfillingProperty, _, _):
					fulfillingProperty
				case .instantiated, .forwarded:
					nil
				}
			}
			for read in reads {
				guard read.asUnwrappedProperty.propertyType.isConstant else { throw .cycleReceivesBuilder }
				labels.insert(read.label)
			}
		}
		return labels
	}

	/// Whether `declaration` is built in a `@Sendable` function of its own.
	static func buildsInSendableFunction(_ declaration: DeclarationID, in world: some NodeRecordSources) -> Bool {
		switch world.kind(of: declaration) {
		case .sendableInstantiator, .sendableErasedInstantiator, .sendableLazy:
			true
		case .constant, .instantiator, .erasedInstantiator, .lazy, .alias, .hole:
			false
		}
	}

	/// The labels `declaration`'s body declares: what it instantiates, what it is forwarded and the names it gives aliases.
	static func labelsDeclared(by declaration: DeclarationID, in world: some NodeRecordSources) -> [String] {
		world.scope(of: declaration).instantiable.dependencies.compactMap { dependency in
			switch dependency.source {
			case .instantiated, .forwarded, .aliased:
				dependency.property.label
			case .received:
				nil
			}
		}
	}

	/// The record of the place at which a call closes a cycle on `declaration`, whose place is being built above the call:
	/// a call of the function that place declares, which forwards what that place's wrapper forwards. The walk refuses a
	/// cycle whose function could take a parameter for the cycle (`cycleTakesParameters`), so the function takes none
	/// (`BuiltPlaceRecord.cycleParameters`), and the call passes none.
	static func closingRecord(closingOn declaration: DeclarationID, in world: some NodeRecordSources) throws(NodeRecordRefusal) -> PlaceRecord {
		// Every node a call reaches is built as a property: the root is called by none.
		guard let property = world.property(of: declaration) else { throw .noInitializer }
		let instantiable = world.scope(of: declaration).instantiable
		return .closer(ClosingPlaceRecord(
			property: property,
			isErased: world.isErased(declaration),
			isExtension: instantiable.declarationType.isExtension,
			closedOnFunctionName: ScopeGenerator.functionName(toBuildPropertyNamed: property.label),
			forwardedProperties: instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted(),
			cycleArguments: [],
		))
	}
}
