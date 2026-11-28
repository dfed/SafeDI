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

/// Whether a `@Sendable` function of a world reads a wrapper that is not `Sendable`, declared outside it, which the tree
/// reports as an error (`ScopeGenerator.nonSendableWrapperCaptures(ofTreeRootedAt:)`): such a world keeps its tree
/// (`NodeRecordRefusal.sendableFunctionCapturesWrapper`). A check that refuses a world, never an input of a record: it
/// follows what each call hands its callee (`TypeFactsWorld.sources(ofCall:of:)`), which no record reads.
///
/// An edge that opens a `@Sendable` function (`TypeFactsEdge.opens`) builds its child inside that function, so every
/// read of the child's tree that a declaration above the child answers is made from outside the function: a capture
/// where that declaration is an `Instantiator`, an `ErasedInstantiator` or a `LazilyInstantiated`, read as itself or as
/// its instance, a parameter of a seam's own root included (`rootNonSendableWrapperLabels`), which its generated
/// initializer declares outside every function. A read a declaration inside the function answers is none of the call's
/// sources. A read of any channel counts, but for a read only if available of the declaration still being built around
/// the call, which is passed `nil` and captures nothing (`isPassedNil`).
///
/// A mock root's world resolves each read by label and type, as its tree does, since its root may declare a label in one
/// form and take another from `mock()`: the types in which the receives beneath the call read the label
/// (`receiveTypesReadFromAbove(in:)`) each read the first declaration of the nearest scope declaring the label that
/// provides their form, or themselves where none does. The two production callers (`NodeRecords.init` and its refusals)
/// still resolve a mock world by label: a public mock's wrapper parameters, which a receive of an instance reads, are
/// decided after its world is built (`ScopeGenerator.instancesReadThroughPublicMockWrapperParameters(of:mockDefaults:)`),
/// and reach the world with the mock root tree checks' move of the capture check off the tree.
///
/// A variant can be called from several places, and each call can hand a read another answer, where its key, which
/// carries what the variant's body can be handed as a parameter, does not tell them apart (seed 580 of the seam corpus:
/// one build of a type reads a wrapper only if available where it is passed `nil`, another where it is the wrapper). So
/// what can answer each read of a variant is folded over every call into it, and each call that opens a `@Sendable`
/// function is judged with what it hands, so the check finds every capture of every build of the variant.
///
/// Memory: for each read of each variant reached, the answers a capture can come through, as small IDs, while the check
/// runs; none in a world that opens no `@Sendable` function.
struct DeclarationsAnsweringReads: Sendable {
	/// A declaration a receive resolves to, as `ScopeGenerator.nonSendableWrapperCaptures` looks it up: the property, and
	/// the by-value property with which a receive reads its instance where it is a lazy wrapper that offers one.
	struct Declaration: Hashable, Sendable {
		let property: Property
		let instanceProperty: Property?

		/// Whether a receive of `unwrappedProperty`, or of its optional form, reads this declaration.
		func provides(_ unwrappedProperty: Property) -> Bool {
			property.asUnwrappedProperty == unwrappedProperty || instanceProperty?.asUnwrappedProperty == unwrappedProperty
		}
	}

	/// What a mock root's `mock()` binds above its tree, which `ScopeGenerator.nonSendableWrapperCaptures` reads where the
	/// root declares no form of a label.
	struct MockRoot: Sendable {
		/// The labels of what `mock()` binds for the receives its tree makes that nothing in the tree declares, once
		/// promotion is final: a read of any other label that nothing above binds is passed `nil`.
		let boundLabels: Set<String>
		/// The lazy wrappers a public mock takes whose instances its tree reads by value, each with that instance
		/// (`ScopeGenerator.instancesReadThroughPublicMockWrapperParameters(of:mockDefaults:)`); empty for every other mock.
		let wrapperParameters: [Declaration]
	}

	/// - Parameters:
	///   - world: A root's world: a production root's, a seam's own, or a mock root's.
	///   - rootNonSendableWrapperLabels: The labels of what the root is handed in an `Instantiator`, an
	///     `ErasedInstantiator` or a `LazilyInstantiated`. Empty unless the root is a seam's own.
	///   - mockRoot: What a mock root's `mock()` binds above its tree; `nil` unless the root is a mock root, whose reads
	///     then resolve by label and type, as its tree resolves them: each receive beneath a call reads the first
	///     declaration of its label, in the order the tree looks declarations up, that provides its form, and itself,
	///     `mock()`'s parameter, where none does (`readsNonSendableWrapper(receiving:among:)`).
	init(world: some NodeRecordSources, rootNonSendableWrapperLabels: Set<String> = [], mockRoot: MockRoot? = nil) {
		guard (0..<Int32(world.declarationCount)).contains(where: { world.edgeFacts(from: $0).contains { Self.opensSendableFunction($0) } }) else {
			sendableFunctionCapturesWrapper = false
			return
		}
		let receiveTypes = mockRoot == nil ? [] : Self.receiveTypesReadFromAbove(in: world)
		let wrapperParametersByLabel = Dictionary(grouping: mockRoot?.wrapperParameters ?? [], by: \.property.label)
		let root = world.declaration(of: 0)
		// The declarations each declaration that answers a read makes, by label, built once each.
		var declarationsByDeclaration = [DeclarationID: [String: [Declaration]]]()
		// The answers a read can capture through, interned by what decides a capture: in a production or seam world one
		// answer, a declaration of the label that is a wrapper that is not `Sendable` (spelled as no declarations); in a mock
		// root's world the declarations of the label the nearest scope declaring it makes, which the receives beneath a
		// call resolve among. An answer through which no read can capture is none.
		var answerIDs = [[Declaration]: Int32]()
		var answers = [[Declaration]]()
		/// The answer the declaration `answeringDeclaration` gives a read of `label`, -1 for none, where a read through
		/// `channel` made by the tree of `callee`, the child it builds on the path, can capture through it: never where the
		/// read is only if available and `callee` is the node of the label still being built, which is passed `nil`
		/// (`NearestDeclarations.resolvingBinding(of:)`), nor where nothing binds the label, which the call passes `nil`.
		func answer(of label: String, through channel: ReadChannel, from answeringDeclaration: DeclarationID, buildingOnPath callee: DeclarationID?) -> Int32 {
			if answeringDeclaration >= 0, let callee, Self.isPassedNil(channel, of: label, beingBuilt: callee, in: world) {
				return -1
			}
			let declarations: [Declaration]
			if let mockRoot {
				// The root's declarations of the label replace what `mock()` declares above the tree, as any scope's
				// replace those above it; a read nothing binds is read where the root is built.
				let declaringDeclaration = answeringDeclaration < 0 ? root : answeringDeclaration
				if declarationsByDeclaration[declaringDeclaration] == nil {
					declarationsByDeclaration[declaringDeclaration] = Self.declarationsByLabel(madeBy: declaringDeclaration, in: world)
				}
				declarations = declarationsByDeclaration[declaringDeclaration]?[label]
					?? (declaringDeclaration == root ? wrapperParametersByLabel[label] ?? [] : [])
				guard answeringDeclaration >= 0 || !declarations.isEmpty || mockRoot.boundLabels.contains(label) else {
					// Nothing binds the label, which the call passes `nil`.
					return -1
				}
			} else if answeringDeclaration >= 0 {
				guard world.scope(of: answeringDeclaration).sortedDeclaredPropertyForms.contains(where: { declared in
					declared.property.label == label && Self.isNonSendableWrapper(declared.property)
				}) else { return -1 }
				declarations = []
			} else {
				guard rootNonSendableWrapperLabels.contains(label) else { return -1 }
				declarations = []
			}
			if let id = answerIDs[declarations] {
				return id
			} else {
				let id = Int32(answers.count)
				answerIDs[declarations] = id
				answers.append(declarations)
				return id
			}
		}
		/// The answers a call hands a read: `answer`, or none where it is -1.
		func handing(_ answer: Int32) -> Set<Int32> {
			answer < 0 ? [] : [answer]
		}

		// For each variant, the answers each of its reads can capture through, over every call into it: the union of what
		// each call hands, grown by a worklist that queues a variant again only when its answers grow. The answers of a
		// read are as few as the declarations of its label, so the fold costs the calls times those. No node is above the
		// root, so what the root is handed answers what its tree reads.
		var answersByVariant = [[Set<Int32>]?](repeating: nil, count: world.variantCount)
		answersByVariant[0] = world.reads(of: root).map { readID in
			let read = world.read(readID)
			guard read.channel.asksAboutLabel else { return [] }
			return handing(answer(of: world.text(ofLabel: read.label), through: read.channel, from: -1, buildingOnPath: nil))
		}
		var isQueued = [Bool](repeating: false, count: world.variantCount)
		isQueued[0] = true
		// A stack, since a tree can be as deep as the module has types.
		var worklist: [VariantID] = [0]
		while let caller = worklist.popLast() {
			isQueued[Int(caller)] = false
			let callerAnswers = answersByVariant[Int(caller)] ?? []
			let edgeFacts = world.edgeFacts(from: world.declaration(of: caller))
			for (edgeIndex, callee) in world.calls(of: caller).enumerated() {
				let opensSendableFunction = Self.opensSendableFunction(edgeFacts[edgeFacts.startIndex + edgeIndex])
				let calleeDeclaration = world.declaration(of: callee)
				let reads = world.reads(of: calleeDeclaration)
				var calleeAnswers = answersByVariant[Int(callee)] ?? [Set<Int32>](repeating: [], count: reads.count)
				var grew = answersByVariant[Int(callee)] == nil
				for (position, (source, readID)) in zip(world.sources(ofCall: edgeIndex, of: caller), reads).enumerated() {
					let read = world.read(readID)
					guard read.channel.asksAboutLabel else { continue }
					let label = world.text(ofLabel: read.label)
					let handed: Set<Int32> = switch source.kind {
					case .none:
						handing(answer(of: label, through: read.channel, from: -1, buildingOnPath: nil))
					case .bound:
						handing(answer(of: label, through: read.channel, from: source.payload, buildingOnPath: calleeDeclaration))
					case .passedThrough:
						callerAnswers[Int(source.payload)]
					}
					// The call builds its callee inside a `@Sendable` function: a read an answer from above the call gives
					// captures that answer, judged for this call's answers alone.
					if opensSendableFunction {
						for handedAnswer in handed where Self.readsNonSendableWrapper(among: answers[Int(handedAnswer)], label: label, receivedAs: mockRoot == nil ? nil : receiveTypes[Int(callee)][read.label] ?? []) {
							sendableFunctionCapturesWrapper = true
							return
						}
					}
					if !handed.isSubset(of: calleeAnswers[position]) {
						calleeAnswers[position].formUnion(handed)
						grew = true
					}
				}
				answersByVariant[Int(callee)] = calleeAnswers
				if grew, !isQueued[Int(callee)] {
					isQueued[Int(callee)] = true
					worklist.append(callee)
				}
			}
		}
		sendableFunctionCapturesWrapper = false
	}

	/// Whether a `@Sendable` function of the world reads, from outside it, a wrapper that is not `Sendable`.
	let sendableFunctionCapturesWrapper: Bool

	/// Whether every read of `label` through `channel` that `callee`'s tree makes is passed `nil` where the call that
	/// builds `callee` binds the label's answer: a read only if available (`optional`, `optionalValue`) of the
	/// declaration still being built around the call, the node of the label that the caller builds as `callee`, which
	/// captures nothing (`NearestDeclarations.resolvingBinding(of:)`). It is judged where the call binds the answer, so
	/// each call into a variant gives its own; a call that passes the answer through hands on the judgment. A required
	/// read of the label reads `value` beside it, which is judged on its own.
	///
	/// A deliberate gap from the tree: a receive only if available that a required receive pins to a form it cannot read
	/// (`MockReceivesPassedNil`) is passed `nil` by the tree, but not judged here, so the world finds a capture the tree does
	/// not and keeps the tree, which is safe. `MockRootTreeChecksOracle` counts such roots in its log, and
	/// `SafeDIToolMockSendableCaptureCheckTests` holds the tree's code for the shape.
	private static func isPassedNil(_ channel: ReadChannel, of label: String, beingBuilt callee: DeclarationID, in world: some NodeRecordSources) -> Bool {
		switch channel {
		case .optional, .optionalValue:
			world.property(of: callee)?.label == label
		case .value, .alias, .madeAgain, .mock, .carrier, .fill, .family, .override:
			false
		}
	}

	/// Whether a read of `label` captures a wrapper that is not `Sendable` through an answer, `declarations`: in a
	/// production or seam world, where `receiveTypes` is `nil`, every answer does; in a mock root's, one of the types the
	/// receives beneath the call read the label in reads such a wrapper among the declarations
	/// (`readsNonSendableWrapper(receiving:among:)`). A read no receive's type reaches is the callee's read of its own
	/// label, made only to rebind it, which captures nothing.
	private static func readsNonSendableWrapper(among declarations: [Declaration], label: String, receivedAs receiveTypes: Set<TypeDescription>?) -> Bool {
		guard let receiveTypes else { return true }
		return receiveTypes.contains { readsNonSendableWrapper(receiving: Property(label: label, typeDescription: $0), among: declarations) }
	}

	/// Whether a receive of `receive` reads a wrapper that is not `Sendable`, among the `declarations` of its label that
	/// the nearest scope declaring the label makes, as the tree resolves it (`ScopeGenerator.nonSendableWrapperCaptures`):
	/// the first that provides the receive's form, or, where none does, the receive itself, which `mock()` is handed.
	private static func readsNonSendableWrapper(receiving receive: Property, among declarations: [Declaration]) -> Bool {
		let unwrappedReceive = receive.asUnwrappedProperty
		return isNonSendableWrapper(declarations.first { $0.provides(unwrappedReceive) }?.property ?? receive)
	}

	/// Whether `property` is a wrapper that is not `Sendable`, read as itself or through its instance.
	private static func isNonSendableWrapper(_ property: Property) -> Bool {
		!property.asUnwrappedProperty.propertyType.isConstant && !property.asUnwrappedProperty.propertyType.isSendable
	}

	/// The declarations `declaration` makes for the scopes it builds, by label, each label's in the order the tree looks
	/// a receive up among them (`ScopeGenerator.nonSendableWrapperCaptures`): what its type forwards, what a mock root
	/// cannot build, then its children in the order it builds them (`TypeFactsEdge.buildPosition`), each with the instance
	/// it offers (`Dependency.lazilyInstantiatedInstanceProperty`, and an alias's of its declared binding).
	private static func declarationsByLabel(madeBy declaration: DeclarationID, in world: some NodeRecordSources) -> [String: [Declaration]] {
		let scope = world.scope(of: declaration)
		var declarations = [String: [Declaration]]()
		for dependency in scope.instantiable.dependencies.filter({ $0.source == .forwarded }) + scope.instantiatedDependenciesNotGenerated {
			declarations[dependency.property.label, default: []].append(Declaration(property: dependency.property, instanceProperty: dependency.lazilyInstantiatedInstanceProperty))
		}
		for edge in world.edgeFacts(from: declaration).sorted(by: { $0.buildPosition < $1.buildPosition }) {
			if let property = world.property(of: edge.child) {
				let instanceProperty = switch world.kind(of: edge.child) {
				case .alias:
					property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding
				case .constant, .instantiator, .erasedInstantiator, .lazy, .sendableInstantiator, .sendableErasedInstantiator, .sendableLazy, .hole:
					property.asLazilyInstantiatedInstanceProperty
				}
				declarations[property.label, default: []].append(Declaration(property: property, instanceProperty: instanceProperty))
			}
		}
		return declarations
	}

	/// For each variant, the types in which the receives its answers reach read each label it reads from above: its own
	/// type's (`ownReceiveTypes(of:in:)`), and each callee's whose read of the label the call passes through, never one
	/// the call binds. Folded by a worklist over the calls into each variant, which may close cycles: a variant is queued
	/// again only when its types grow, so the fold costs the calls times the types of a label.
	private static func receiveTypesReadFromAbove(in world: some NodeRecordSources) -> [[WorldLabelID: Set<TypeDescription>]] {
		var types = [[WorldLabelID: Set<TypeDescription>]](repeating: [:], count: world.variantCount)
		var callsInto = [[(caller: VariantID, edgeIndex: Int)]](repeating: [], count: world.variantCount)
		var ownTypesByDeclaration = [DeclarationID: [WorldLabelID: Set<TypeDescription>]]()
		for variant in 0..<world.variantCount {
			for (edgeIndex, callee) in world.calls(of: VariantID(variant)).enumerated() {
				callsInto[Int(callee)].append((caller: VariantID(variant), edgeIndex: edgeIndex))
			}
			let declaration = world.declaration(of: VariantID(variant))
			if ownTypesByDeclaration[declaration] == nil {
				ownTypesByDeclaration[declaration] = ownReceiveTypes(of: declaration, in: world)
			}
			types[variant] = ownTypesByDeclaration[declaration] ?? [:]
		}
		var worklist = (0..<world.variantCount).filter { !types[$0].isEmpty }.map(VariantID.init)
		var isQueued = types.map { !$0.isEmpty }
		while let callee = worklist.popLast() {
			isQueued[Int(callee)] = false
			let reads = world.reads(of: world.declaration(of: callee))
			for (caller, edgeIndex) in callsInto[Int(callee)] {
				var grew = false
				for (source, readID) in zip(world.sources(ofCall: edgeIndex, of: caller), reads) where source.kind == .passedThrough {
					let label = world.read(readID).label
					if let calleeTypes = types[Int(callee)][label], !calleeTypes.isSubset(of: types[Int(caller)][label] ?? []) {
						types[Int(caller)][label, default: []].formUnion(calleeTypes)
						grew = true
					}
				}
				if grew, !isQueued[Int(caller)] {
					isQueued[Int(caller)] = true
					worklist.append(caller)
				}
			}
		}
		return types
	}

	/// The types in which `declaration`'s own type receives each label it reads from above, as the graph reads them
	/// (`TypeFactsGraph.ownReads`): a node's received dependencies, the fulfilling property of each alias of a label its
	/// type creates no property of, and what the fills of its calls receive; an alias's fulfilling property; a hole's none.
	private static func ownReceiveTypes(of declaration: DeclarationID, in world: some NodeRecordSources) -> [WorldLabelID: Set<TypeDescription>] {
		var labelIDs = [String: WorldLabelID]()
		for readID in world.reads(of: declaration) {
			let label = world.read(readID).label
			labelIDs[world.text(ofLabel: label)] = label
		}
		var types = [WorldLabelID: Set<TypeDescription>]()
		func insert(_ property: Property) {
			if let label = labelIDs[property.label] {
				types[label, default: []].insert(property.typeDescription)
			}
		}
		let scope = world.scope(of: declaration)
		switch world.kind(of: declaration) {
		case .alias:
			// A leaf's scope is its parent's, which declares the alias.
			if let fulfillingProperty = NodeRecords.renamedProperty(of: declaration, in: world) {
				insert(fulfillingProperty)
			}
		case .hole:
			break
		case .constant, .instantiator, .erasedInstantiator, .lazy, .sendableInstantiator, .sendableErasedInstantiator, .sendableLazy:
			let createdLabels = Set(scope.instantiable.dependencies.filter { $0.source == .forwarded || $0.source.isInstantiated }.map(\.property.label))
			for dependency in scope.instantiable.dependencies {
				switch dependency.source {
				case .received:
					insert(dependency.property)
				case let .aliased(fulfillingProperty, _, _):
					if !createdLabels.contains(fulfillingProperty.label) {
						insert(fulfillingProperty)
					}
				case .instantiated, .forwarded:
					break
				}
			}
			for property in scope.fillReceivedProperties.values.joined() {
				insert(property)
			}
		}
		return types
	}

	private static func opensSendableFunction(_ edge: TypeFactsEdge) -> Bool {
		switch edge.opens {
		case .sendableInstantiatorBuilder, .sendableLazyWrapper, .otherSendableFunction:
			true
		case .none, .instantiatorBuilder:
			false
		}
	}
}
