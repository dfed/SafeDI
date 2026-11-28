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
/// Each variant is resolved from the first call a walk from the root meets, and read again where a later call answers a
/// read only if available that it left unanswered, as rule 1 keys such a read alike either way: a variant built where a
/// wrapper is not yet available and again where it is captures it at the second. The check goes when the facts fold
/// captures per variant (`TypeFactsOutcome`), the per-type facts' form of `nonSendableWrapperCaptures`.
///
/// It also folds the by-value properties each variant's whole tree reads as the instance of a wrapper declared above it
/// (`lazilyInstantiatedInstanceProperties(readBy:)`), which a call that closes a cycle passes its function's parameters;
/// a record reads its own type's from its key instead (`NodeRecords.lazilyInstantiatedInstanceProperties(of:variant:in:)`).
///
/// Memory: a set per variant, each empty unless the variant's tree reads a wrapper's instance, for as long as the records
/// are made, and the declaration that answers each read, one ID per key of every variant, while the walk runs; none in a
/// world that declares no lazily instantiated property, whose root is handed none, and that opens no `@Sendable` function.
struct DeclarationsAnsweringReads: Sendable {
	/// A declaration a receive resolves to, as `ScopeGenerator.nonSendableWrapperCaptures` looks it up: the property, and
	/// the by-value property with which a receive reads its instance where it is a lazy wrapper that offers one.
	struct Declaration: Equatable, Sendable {
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
	init(world: some NodeRecordSources, rootLazilyInstantiatedInstanceProperties: Set<Property> = [], rootNonSendableWrapperLabels: Set<String> = [], mockRoot: MockRoot? = nil) {
		// A world that declares no lazily instantiated property, whose root is handed none, and that opens no `@Sendable`
		// function reads no wrapper's instance and captures nothing.
		guard !rootLazilyInstantiatedInstanceProperties.isEmpty || (0..<Int32(world.declarationCount)).contains(where: { declaration in
			!world.scope(of: declaration).declaredLazilyInstantiatedInstanceProperties.isEmpty
				|| world.edgeFacts(from: declaration).contains { Self.opensSendableFunction($0) }
		}) else {
			sendableFunctionCapturesWrapper = false
			lazilyInstantiatedInstancePropertiesByVariant = []
			return
		}
		var lazilyInstantiatedInstancePropertiesByVariant = [Set<Property>](repeating: [], count: world.variantCount)
		// The root's own body reads what it is handed.
		lazilyInstantiatedInstancePropertiesByVariant[0] = rootLazilyInstantiatedInstanceProperties
		var sendableFunctionCapturesWrapper = false
		let receiveTypes = mockRoot == nil ? [] : Self.receiveTypesReadFromAbove(in: world)
		let wrapperParametersByLabel = Dictionary(grouping: mockRoot?.wrapperParameters ?? [], by: \.property.label)
		let root = world.declaration(of: 0)
		// The declarations each declaration that answers a read makes, by label, built once each.
		var declarationsByDeclaration = [DeclarationID: [String: [Declaration]]]()
		// For each variant reached, the declaration that answers each of its reads, -1 where none does. No node is above
		// the root, so what the root is handed answers what its tree reads.
		var answeringDeclarations = [[DeclarationID]?](repeating: nil, count: world.variantCount)
		answeringDeclarations[0] = [DeclarationID](repeating: -1, count: world.reads(of: world.declaration(of: 0)).count)
		// Each variant's caller, the first call a walk from the root meets, -1 for the root.
		var callerByVariant = [VariantID](repeating: -1, count: world.variantCount)
		// A stack, since a tree can be as deep as the module has types.
		var stack: [VariantID] = [0]
		while let caller = stack.popLast() {
			let callerAnsweringDeclarations = answeringDeclarations[Int(caller)] ?? []
			let edgeFacts = world.edgeFacts(from: world.declaration(of: caller))
			for (edgeIndex, callee) in world.calls(of: caller).enumerated() {
				let opensSendableFunction = Self.opensSendableFunction(edgeFacts[edgeFacts.startIndex + edgeIndex])
				let calleeReads = world.reads(of: world.declaration(of: callee))
				var calleeAnsweringDeclarations = [DeclarationID]()
				for source in world.sources(ofCall: edgeIndex, of: caller).prefix(calleeReads.count) {
					let answeringDeclaration: DeclarationID = switch source.kind {
					case .none:
						-1
					case .bound:
						source.payload
					case .passedThrough:
						callerAnsweringDeclarations[Int(source.payload)]
					}
					calleeAnsweringDeclarations.append(answeringDeclaration)
				}
				// Every call into a variant answers a read by value alike, since the variant's key holds the forms its
				// declaration provides, and crosses the one edge from its type to it, which opens a `@Sendable` function at
				// every call or at none. A read only if available is the exception: rule 1 keys it alike whether a call answers
				// it or not, so the variant is resolved as a call that answers it does, and read again, with everything it
				// calls, whichever call comes first. A capture is only ever added, so the order the calls are met in never
				// changes what is found.
				var calleeAnswers = calleeAnsweringDeclarations
				if let resolved = answeringDeclarations[Int(callee)] {
					var merged = resolved
					for (index, readID) in calleeReads.enumerated() where merged[index] < 0 && calleeAnsweringDeclarations[index] >= 0 {
						switch world.read(readID).channel {
						case .optional, .optionalValue:
							merged[index] = calleeAnsweringDeclarations[index]
						case .value, .alias, .madeAgain, .mock, .carrier, .fill, .family, .override:
							break
						}
					}
					guard merged != resolved else { continue }
					calleeAnswers = merged
				} else {
					callerByVariant[Int(callee)] = caller
				}
				answeringDeclarations[Int(callee)] = calleeAnswers
				stack.append(callee)
				for (answeringDeclaration, readID) in zip(calleeAnswers, calleeReads) {
					let read = world.read(readID)
					guard read.channel.asksAboutLabel else { continue }
					let label = world.text(ofLabel: read.label)
					// A read handed the nearest declaration of its label reads a wrapper's instance where that declaration's
					// scope declares one, or where what the root is handed offers one.
					if Self.isHandedNearestDeclaration(read.channel) {
						let instanceProperties = answeringDeclaration >= 0 ? world.scope(of: answeringDeclaration).declaredLazilyInstantiatedInstanceProperties : rootLazilyInstantiatedInstanceProperties
						for property in instanceProperties where property.label == label {
							lazilyInstantiatedInstancePropertiesByVariant[Int(callee)].insert(property)
						}
					}
					guard opensSendableFunction else { continue }
					let readsNonSendableWrapper: Bool
					if let mockRoot {
						// The root's declarations of the label replace what `mock()` declares above the tree, as any scope's
						// replace those above it; a read nothing binds is read where the root is built.
						let declaringDeclaration = answeringDeclaration < 0 ? root : answeringDeclaration
						if declarationsByDeclaration[declaringDeclaration] == nil {
							declarationsByDeclaration[declaringDeclaration] = Self.declarationsByLabel(madeBy: declaringDeclaration, in: world)
						}
						let declarations = declarationsByDeclaration[declaringDeclaration]?[label]
							?? (declaringDeclaration == root ? wrapperParametersByLabel[label] ?? [] : [])
						if answeringDeclaration < 0, declarations.isEmpty, !mockRoot.boundLabels.contains(label) {
							// Nothing binds the label, which the call passes `nil`.
							readsNonSendableWrapper = false
						} else {
							// Each type a receive beneath the call reads the label in resolves among the declarations. A read no
							// receive's type reaches is the callee's read of its own label, made only to rebind it, which captures
							// nothing.
							readsNonSendableWrapper = (receiveTypes[Int(callee)][read.label] ?? []).contains { Self.readsNonSendableWrapper(receiving: Property(label: label, typeDescription: $0), among: declarations) }
						}
					} else if answeringDeclaration >= 0 {
						readsNonSendableWrapper = world.scope(of: answeringDeclaration).sortedDeclaredPropertyForms.contains { declared in
							declared.property.label == label && Self.isNonSendableWrapper(declared.property)
						}
					} else {
						readsNonSendableWrapper = rootNonSendableWrapperLabels.contains(label)
					}
					if readsNonSendableWrapper, !Self.isPassedNil(read.channel, of: label, answeredBy: answeringDeclaration, aboveCallOf: callee, by: caller, callerByVariant: callerByVariant, in: world) {
						sendableFunctionCapturesWrapper = true
					}
				}
			}
		}
		self.sendableFunctionCapturesWrapper = sendableFunctionCapturesWrapper
		self.lazilyInstantiatedInstancePropertiesByVariant = lazilyInstantiatedInstancePropertiesByVariant
	}

	/// The by-value properties `variant`'s body reads as a wrapper's instance, of the labels its whole tree reads from
	/// above: what a call that closes a cycle on its function passes as a wrapper's instance (`NodeRecords`' cycle
	/// arguments), which its key, holding only its own type's reads, does not show.
	func lazilyInstantiatedInstanceProperties(readBy variant: VariantID) -> Set<Property> {
		lazilyInstantiatedInstancePropertiesByVariant.isEmpty ? [] : lazilyInstantiatedInstancePropertiesByVariant[Int(variant)]
	}

	/// Whether a `@Sendable` function of the world reads, from outside it, a wrapper that is not `Sendable`.
	let sendableFunctionCapturesWrapper: Bool

	/// By variant; empty in a world that declares no lazily instantiated property, whose root is handed none, and that
	/// opens no `@Sendable` function.
	private let lazilyInstantiatedInstancePropertiesByVariant: [Set<Property>]

	/// Whether every read of `label` through `channel` that `callee`'s tree makes is passed `nil` where `answeringDeclaration`,
	/// the scope that declares the label, answers it: a read only if available (`optional`, `optionalValue`) of the
	/// declaration still being built around the call, the node of the label that `answeringDeclaration` builds on the path
	/// to `callee`, which captures nothing (`NearestDeclarations.resolvingBinding(of:)`). A required read of the label reads
	/// `value` beside it, which is judged on its own.
	///
	/// A deliberate gap from the tree: a receive only if available that a required receive pins to a form it cannot read
	/// (`MockReceivesPassedNil`) is passed `nil` by the tree, but not judged here, so the world finds a capture the tree does
	/// not and keeps the tree, which is safe. `MockRootTreeChecksOracle` counts such roots in its log, and
	/// `SafeDIToolMockSendableCaptureCheckTests` holds the tree's code for the shape.
	private static func isPassedNil(
		_ channel: ReadChannel,
		of label: String,
		answeredBy answeringDeclaration: DeclarationID,
		aboveCallOf callee: VariantID,
		by caller: VariantID,
		callerByVariant: [VariantID],
		in world: some NodeRecordSources,
	) -> Bool {
		switch channel {
		case .optional, .optionalValue:
			var child = callee
			var parent = caller
			while parent >= 0, world.declaration(of: parent) != answeringDeclaration {
				child = parent
				parent = callerByVariant[Int(parent)]
			}
			return parent >= 0 && world.property(of: world.declaration(of: child))?.label == label
		case .value, .alias, .madeAgain, .mock, .carrier, .fill, .family, .override:
			return false
		}
	}

	/// Whether a read of `channel` is handed the nearest declaration of its label, in the form that declaration has: a
	/// required receive, and a receive only if available where it is handed a value.
	private static func isHandedNearestDeclaration(_ channel: ReadChannel) -> Bool {
		switch channel {
		case .value, .optionalValue:
			true
		case .optional, .alias, .madeAgain, .mock, .carrier, .fill, .family, .override:
			false
		}
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
