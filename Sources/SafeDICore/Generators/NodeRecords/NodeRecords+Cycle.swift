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
	/// (`closingRecord(closingOn:from:functionName:cycleArguments:in:)`).
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
	/// a call of the function that place declares, named `functionName` where the bodies between rename it
	/// (`CycleFunctionNames`), which forwards what that place's wrapper forwards, and passes the function's parameters
	/// `cycleArguments` (`cycleArguments(of:unavailableProperties:lazilyInstantiatedInstanceProperties:)`). `caller` is the
	/// variant whose body holds the call,
	/// which a production closer reads nothing of; a mock's closer, which passes what its caller binds, takes this site.
	static func closingRecord(closingOn declaration: DeclarationID, from caller: VariantID, functionName: String? = nil, cycleArguments: [PlaceRead] = [], in world: some NodeRecordSources, enteredSlots: MockEnteredSlots? = nil) throws(NodeRecordRefusal) -> PlaceRecord {
		// Every node a call reaches is built as a property: the root is called by none.
		guard let property = world.property(of: declaration) else { throw .noInitializer }
		let instantiable = world.scope(of: declaration).instantiable
		var closer = ClosingPlaceRecord(
			property: property,
			isErased: world.isErased(declaration),
			isExtension: instantiable.declarationType.isExtension,
			closedOnFunctionName: functionName ?? ScopeGenerator.functionName(toBuildPropertyNamed: property.label),
			forwardedProperties: instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property).sorted(),
			cycleArguments: cycleArguments,
		)
		// A mock's function on a cycle is handed its overrides and the places entered by every call, as its own place hands
		// them (`mockArgumentsHanded(to:labeled:by:in:slots:)`).
		if let enteredSlots {
			closer.passedArguments = mockArgumentsHanded(to: declaration, labeled: property.label, by: world.declaration(of: caller), in: world, slots: enteredSlots)
		}
		return .closer(closer)
	}

	/// `record`, a place's record as its kind makes it, with its function named `functionName` where its body renames it
	/// (`CycleFunctionNames`), `@Sendable` where a call beneath it that closes a cycle on it refers to it from a
	/// `@Sendable` function (`isMadeSendable`), as today's tree makes it (`ScopeGenerator.cycleClosings`), and taking
	/// `cycleParameters`, which its binding passes `callCycleArguments`, where a cycle closes on it. A place written as text
	/// keeps its text.
	static func record(
		_ record: PlaceRecord,
		functionName: String?,
		isMadeSendable: Bool,
		cycleParameters: [Property],
		callCycleArguments: [PlaceRead],
	) -> PlaceRecord {
		switch record {
		case let .built(built):
			guard functionName != nil || (isMadeSendable && !built.isSendable) || !cycleParameters.isEmpty else { return record }
			var named = BuiltPlaceRecord(
				property: built.property,
				isErased: built.isErased,
				concreteType: built.concreteType,
				isExtension: built.isExtension,
				target: built.target,
				arguments: built.arguments,
				forwardedProperties: built.forwardedProperties,
				cycleParameters: cycleParameters.isEmpty ? built.cycleParameters : cycleParameters,
				callCycleArguments: cycleParameters.isEmpty ? built.callCycleArguments : callCycleArguments,
				functionName: functionName ?? built.functionName,
				isSendable: built.isSendable || isMadeSendable,
				typesDeclaredEscaping: built.typesDeclaredEscaping,
				lineEnd: built.lineEnd,
				hasFunction: built.hasFunction,
				children: built.children,
				node: built.node,
			)
			named.sharingFields = built.sharingFields
			named.callFields = built.callFields
			return .built(named)
		case .alias, .closer:
			return record
		}
	}

	/// The constants and lazily instantiated declarations on the walk's path, by label and the type built, in a world with
	/// a cycle. Today's tree closes a cycle between two of a constant, a `LazilyInstantiated` and a
	/// `SendableLazilyInstantiated` declaration of one label and type on each other (`ScopeGenerator.closedOnDeclaration`),
	/// where the facts' variants hold two nodes: a twin, which the walk refuses (`cycleVariantsPartitionApart`) where a
	/// place of one is built beneath a place of the other.
	struct TwinsOnPath<World: NodeRecordSources> {
		init(world: World, holdsCycle: Bool) {
			self.world = world
			self.holdsCycle = holdsCycle
		}

		/// Notes that the walk enters a place of `declaration`.
		/// - Throws: `cycleVariantsPartitionApart` where a place of its twin, or of another variant of `declaration`, is on
		///   the path: today's tree closes the cycle on that place, which repeats the declaration's property and type, where
		///   the facts' variant builds it again.
		mutating func enter(_ declaration: DeclarationID) throws(NodeRecordRefusal) {
			guard holdsCycle else { return }
			guard placesOnPath[Int(declaration), default: 0] == 0 else { throw .cycleVariantsPartitionApart }
			placesOnPath[Int(declaration), default: 0] += 1
			guard let twin = twinKey(of: declaration) else { return }
			var counts = countsOnPath[twin.key, default: [0, 0, 0]]
			guard counts.indices.allSatisfy({ $0 == twin.form || counts[$0] == 0 }) else { throw .cycleVariantsPartitionApart }
			counts[twin.form] += 1
			countsOnPath[twin.key] = counts
		}

		/// Whether a place of `declaration`, or of its twin (another form of its label and type), is on the path.
		func holdsPlaceOfItOrItsTwin(_ declaration: DeclarationID) -> Bool {
			guard placesOnPath[Int(declaration), default: 0] == 0 else { return true }
			guard let twin = twinKey(of: declaration), let counts = countsOnPath[twin.key] else { return false }
			return counts.indices.contains { $0 != twin.form && counts[$0] > 0 }
		}

		/// Notes that the walk leaves the place of `declaration` it entered.
		mutating func leave(_ declaration: DeclarationID) {
			guard holdsCycle else { return }
			placesOnPath[Int(declaration), default: 0] -= 1
			guard let twin = twinKey(of: declaration) else { return }
			countsOnPath[twin.key, default: [0, 0, 0]][twin.form] -= 1
		}

		private struct LabelAndType: Hashable {
			let label: String
			let concreteType: TypeDescription
		}

		private let world: World
		private let holdsCycle: Bool
		/// By label and type, how many places of each form are on the path: a constant, a `LazilyInstantiated` and a
		/// `SendableLazilyInstantiated`.
		private var countsOnPath = [LabelAndType: [Int]]()
		/// By declaration, how many of its places are on the path.
		private var placesOnPath = [Int: Int]()

		/// The label and type `declaration` builds, and its form's index in `countsOnPath`, or `nil` where it is neither a
		/// constant nor lazily instantiated.
		private func twinKey(of declaration: DeclarationID) -> (key: LabelAndType, form: Int)? {
			let form = switch world.kind(of: declaration) {
			case .constant:
				0
			case .lazy:
				1
			case .sendableLazy:
				2
			case .instantiator, .sendableInstantiator, .erasedInstantiator, .sendableErasedInstantiator, .alias, .hole:
				-1
			}
			guard form >= 0, let property = world.property(of: declaration) else { return nil }
			return (LabelAndType(label: property.label, concreteType: world.scope(of: declaration).instantiable.concreteInstantiable), form)
		}
	}

	/// What a place's body holds, in the order it builds it: the place of a variant it calls, or a call that closes a cycle
	/// on a variant whose place is being built above it.
	enum BodyEntry {
		case place(VariantID)
		case closer(closingOn: VariantID)
	}

	/// The names the bodies of a world with a cycle give the functions they declare, and the functions a call that closes a
	/// cycle refers to, as today's tree names them (`ScopeGenerator.builderFunctionNames(for:enclosingFunctionNames:)`).
	///
	/// A call that closes a cycle refers by name to the function of the place it closes on, which Swift resolves to the
	/// innermost function of that name in scope, so a body between the two that declares a function of that name renames
	/// it `<name>_<type identifier>` (`ScopeGenerator.identifierSafeNames`), and the bodies beneath refer to the renamed
	/// function by its new name. A variant's place is one record wherever a body holds it, so a variant two bodies name
	/// differently, or whose body two paths hand different names, is refused (`cycleBuilderNameShared`).
	struct CycleFunctionNames {
		/// - Parameters:
		///   - entries: What each variant's body holds (`BodyEntry`), by variant.
		///   - variantsClosedOn: The variants above each variant's place that a call in its tree closes a cycle on, by
		///     variant.
		init(entries: [[BodyEntry]], variantsClosedOn: [Set<VariantID>], in world: some NodeRecordSources) throws(NodeRecordRefusal) {
			functionNames = Array(repeating: nil, count: world.variantCount)
			enclosingFunctionNames = Array(repeating: [:], count: world.variantCount)
			var isNamed = [Bool](repeating: false, count: world.variantCount)
			isNamed[0] = true
			func closedOn(_ entry: BodyEntry) -> Set<VariantID> {
				switch entry {
				case let .closer(closingOn: callee):
					[callee]
				case let .place(callee):
					variantsClosedOn[Int(callee)]
				}
			}
			func callee(of entry: BodyEntry) -> VariantID {
				switch entry {
				case let .closer(closingOn: callee), let .place(callee):
					callee
				}
			}
			var bodies: [VariantID] = [0]
			while let variant = bodies.popLast() {
				let enclosing = enclosingFunctionNames[Int(variant)]
				let body = entries[Int(variant)]
				// The functions enclosing the body that a call in it closes a cycle on, by the names the body sees them by.
				var referencedNames = Set<String>()
				for entry in body {
					for closedOnVariant in closedOn(entry) {
						if let property = world.property(of: world.declaration(of: closedOnVariant)) {
							referencedNames.insert(enclosing[closedOnVariant] ?? ScopeGenerator.functionName(toBuildPropertyNamed: property.label))
						}
					}
				}
				// Every entry built as a property declares or calls a function by its label: an alias or a hole has none.
				var candidates = [(index: Int, property: Property, name: String)]()
				for (index, entry) in body.enumerated() {
					let declaration = world.declaration(of: callee(of: entry))
					switch world.kind(of: declaration) {
					case .constant, .instantiator, .sendableInstantiator, .erasedInstantiator, .sendableErasedInstantiator, .lazy, .sendableLazy:
						if let property = world.property(of: declaration) {
							candidates.append((index, property, ScopeGenerator.functionName(toBuildPropertyNamed: property.label)))
						}
					case .alias, .hole:
						break
					}
				}
				// A call that closes a cycle declares no function.
				let renamed = candidates.filter { candidate in
					switch body[candidate.index] {
					case .place:
						referencedNames.contains(candidate.name)
					case .closer:
						false
					}
				}
				let renamedNames = ScopeGenerator.identifierSafeNames(
					for: renamed.map { candidate in
						let typeDescription = candidate.property.typeDescription
						return (label: candidate.name, suffixTypes: [typeDescription.asInstantiatedType.simplified, typeDescription.asInstantiatedType, typeDescription])
					},
					reservedNames: referencedNames.union(candidates.map(\.name)),
				)
				// safedi-source-rule: allow uniqueKeysWithValues — the keys are distinct indices of `body`.
				let renamedNameByIndex = Dictionary(uniqueKeysWithValues: zip(renamed.map(\.index), renamedNames))
				for case let (index, .place(child)) in body.enumerated() {
					let functionName = renamedNameByIndex[index]
					// A call beneath the child refers to the functions enclosing it, and to the child's own function when the
					// call closes on it.
					var childEnclosing = variantsClosedOn[Int(child)].isEmpty ? [:] : enclosing
					if let functionName, entries[Int(child)].contains(where: { closedOn($0).contains(child) }) {
						childEnclosing[child] = functionName
					}
					if isNamed[Int(child)] {
						guard functionNames[Int(child)] == functionName, enclosingFunctionNames[Int(child)] == childEnclosing else {
							throw .cycleBuilderNameShared
						}
					} else {
						isNamed[Int(child)] = true
						functionNames[Int(child)] = functionName
						enclosingFunctionNames[Int(child)] = childEnclosing
						bodies.append(child)
					}
				}
			}
		}

		/// The name of `variant`'s place's function where its body renames it, else `nil`.
		func functionName(of variant: VariantID) -> String? {
			functionNames[Int(variant)]
		}

		/// The name by which a call in the body of `variant`'s place that closes a cycle on `closedOn` refers to its function.
		func closedOnFunctionName(of closedOn: VariantID, inBodyOf variant: VariantID) -> String? {
			enclosingFunctionNames[Int(variant)][closedOn]
		}

		/// By variant: the name of its place's function where its body renames it, else `nil`.
		private var functionNames: [String?]
		/// By variant: the names of the functions enclosing its place's body that a call in it closes a cycle on, where they
		/// are renamed.
		private var enclosingFunctionNames: [[VariantID: String]]
	}
}
